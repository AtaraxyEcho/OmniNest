package com.omninest.modules.file.service;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SharedSpaceUsage;
import com.omninest.modules.file.dto.SharedSpaceUsageDto;
import com.omninest.modules.file.repository.SharedSpaceUsageRepository;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 共享空间配额服务，管理共享空间的容量限制和用量统计。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class SharedSpaceQuotaService {

    private final SharedSpaceUsageRepository usageRepository;
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
        if (usage.getUsedBytes() + additionalBytes > maxBytes) {
            throw new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "共享空间容量不足");
        }
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
