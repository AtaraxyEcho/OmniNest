package com.omninest.modules.file.service;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SharedSpaceUsage;
import com.omninest.modules.file.dto.SharedSpaceUsageDto;
import com.omninest.modules.file.repository.FileMetricsRepository;
import com.omninest.modules.file.repository.SharedSpaceUsageProjection;
import com.omninest.modules.file.repository.SharedSpaceUsageRepository;
import com.omninest.modules.quota.port.SharedSpaceUsageReconcile;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 共享空间配额服务，管理共享空间的容量限制、用量统计和账本对账。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class SharedSpaceQuotaService implements SharedSpaceUsageReconcile {

    private final SharedSpaceUsageRepository usageRepository;
    private final FileMetricsRepository fileMetricsRepository;
    private final ConfigValueProvider configValueProvider;

    private static final String CONFIG_MAX_BYTES = "share.max-bytes";
    private static final String LEGACY_CONFIG_MAX_BYTES = "shared_space.max_bytes";
    // 数据库配置缺失时使用保守的 100GB 部署回退值；正常安装由 share.max-bytes 提供 300GB 默认值。
    private static final long DEFAULT_MAX_BYTES = 100L * 1024 * 1024 * 1024;

    /**
     * 检查共享空间是否有足够容量。
     */
    @Transactional(readOnly = true)
    public void checkQuota(long additionalBytes) {
        long maxBytes = configuredMaxBytes();
        if (maxBytes <= 0) {
            return;
        }
        SharedSpaceUsage usage = getUsage();
        long projected = usage.getUsedBytes() + usage.getReservedBytes() + Math.max(additionalBytes, 0L);
        if (projected > maxBytes) {
            throw new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "共享空间容量不足");
        }
    }

    /**
     * 为共享空间上传会话原子预留容量。
     *
     * <p>共享空间没有个人配额预留表可复用：这里在单行账本上同时守卫已用与已预留字节，
     * 多个成员并发创建上传会话时只有一个条件更新能成功，避免“并发会话都通过只读预检、
     * 超额数据全部写进隔离桶后才在晋升阶段一起失败”。</p>
     *
     * @param bytes 预留字节数
     */
    @Transactional(rollbackFor = Exception.class)
    public void reserve(long bytes) {
        if (bytes <= 0) {
            return;
        }
        SharedSpaceUsage usage = getUsage();
        int updated = usageRepository.tryReserve(
                usage.getId(), bytes, capacityCeiling(), Instant.now());
        if (updated == 0) {
            throw new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "共享空间容量不足");
        }
    }

    /**
     * 释放未结算的共享空间预留。
     *
     * @param bytes 释放字节数
     */
    @Transactional(rollbackFor = Exception.class)
    public void releaseReservation(long bytes) {
        if (bytes <= 0) {
            return;
        }
        SharedSpaceUsage usage = getUsage();
        usageRepository.releaseReservation(usage.getId(), bytes, Instant.now());
    }

    /**
     * 将共享空间上传预留结算为实际用量。
     *
     * @param reservedBytes 原预留字节数
     * @param committedBytes 实际写入字节数
     * @param files 新增文件数
     */
    @Transactional(rollbackFor = Exception.class)
    public void settleReservation(long reservedBytes, long committedBytes, long files) {
        SharedSpaceUsage usage = getUsage();
        usageRepository.settleReservation(
                usage.getId(),
                Math.max(reservedBytes, 0L),
                Math.max(committedBytes, 0L),
                Math.max(files, 0L),
                Instant.now()
        );
    }

    /**
     * 增加共享空间用量。
     *
     * <p>容量上限在同一条条件更新里判定，因此并发上传不会双双通过预检后把空间写超；
     * 更新 0 行即表示本次增量放不下。</p>
     *
     * @param bytes 新增字节数
     * @param files 新增文件数
     */
    @Transactional(rollbackFor = Exception.class)
    public void increaseUsage(long bytes, long files) {
        if (bytes <= 0 && files <= 0) {
            return;
        }
        SharedSpaceUsage usage = getUsage();
        int updated = usageRepository.tryIncreaseUsage(
                usage.getId(),
                Math.max(bytes, 0),
                Math.max(files, 0),
                capacityCeiling(),
                Instant.now()
        );
        if (updated == 0) {
            throw new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "共享空间容量不足");
        }
    }

    /**
     * 减少共享空间用量。
     *
     * @param bytes 释放字节数
     * @param files 释放文件数，删除整个文件夹时必须传子树内的真实文件数
     */
    @Transactional(rollbackFor = Exception.class)
    public void decreaseUsage(long bytes, long files) {
        if (bytes <= 0 && files <= 0) {
            return;
        }
        SharedSpaceUsage usage = getUsage();
        usageRepository.decreaseUsage(
                usage.getId(),
                Math.max(bytes, 0),
                Math.max(files, 0),
                Instant.now()
        );
    }

    /**
     * 获取共享空间用量 DTO。
     */
    @Transactional(readOnly = true)
    public SharedSpaceUsageDto getUsageDto() {
        SharedSpaceUsage usage = getUsage();
        long maxBytes = configuredMaxBytes();
        return new SharedSpaceUsageDto(usage.getUsedBytes(), maxBytes, usage.getFileCount());
    }

    /**
     * 按共享空间节点与历史版本的实际字节重算单行账本。
     *
     * <p>数值一致时条件更新不动版本行，避免每天无谓地推高乐观锁版本。</p>
     */
    @Transactional(rollbackFor = Exception.class)
    @Override
    public void reconcileUsage() {
        SharedSpaceUsage usage = getUsage();
        SharedSpaceUsageProjection actual = fileMetricsRepository.aggregateSharedSpaceUsage();
        int updated = usageRepository.reconcileTo(
                usage.getId(),
                actual.getTotalBytes(),
                actual.getTotalFiles(),
                Instant.now()
        );
        if (updated > 0) {
            log.info("共享空间用量对账完成: usedBytes={}, fileCount={}",
                    actual.getTotalBytes(), actual.getTotalFiles());
        }
    }

    /**
     * 从 config_entries 读取 long 配置值。
     */
    private long getConfigLong(String key, String legacyKey, long defaultValue) {
        return configValueProvider.findByKey(key)
                .or(() -> configValueProvider.findByKey(legacyKey))
                .map(value -> {
                    try {
                        return Long.parseLong(value);
                    } catch (NumberFormatException e) {
                        log.warn("配置项{}值格式错误，使用默认值: {}", key, defaultValue);
                        return defaultValue;
                    }
                })
                .orElse(defaultValue);
    }

    /**
     * 共享空间容量上限，配置为 0 或负值表示不限制。
     */
    private long configuredMaxBytes() {
        return getConfigLong(CONFIG_MAX_BYTES, LEGACY_CONFIG_MAX_BYTES, DEFAULT_MAX_BYTES);
    }

    /**
     * 条件更新用的容量天花板：不限时取足够大的值，避免 usedBytes + delta 溢出比较恒真。
     */
    private long capacityCeiling() {
        long maxBytes = configuredMaxBytes();
        return maxBytes <= 0 ? Long.MAX_VALUE / 4 : maxBytes;
    }

    private SharedSpaceUsage getUsage() {
        return usageRepository.findFirstBy()
                .orElseThrow(() -> new BusinessException(ErrorCode.INTERNAL_ERROR, "共享空间用量记录不存在"));
    }
}
