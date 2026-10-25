package com.omninest.modules.photos.service;

import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.photos.config.PhotoBatchRetentionProperties;
import com.omninest.modules.photos.domain.PhotoBatchTask;
import com.omninest.modules.photos.repository.PhotoBatchTaskRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import com.omninest.modules.task.runtime.ConditionalOnSchedulerRuntime;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * 照片批量任务终态记录与打包 ZIP 的过期清理。
 *
 * <p>批量下载生成的 ZIP 以 {@code source_type = 'DERIVED'} 的 FileNode 存放，
 * 既不计入个人配额，也不会被孤儿扫描器判定为可回收（FileObject 仍在引用），
 * 不主动过期就会永久占用对象存储。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnSchedulerRuntime
public class PhotoBatchRetentionService {

    private static final Set<String> TERMINAL_STATUSES = Set.of("COMPLETED", "FAILED");

    private final PhotoBatchTaskRepository batchTaskRepository;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final PhotoBatchRetentionProperties properties;

    /**
     * 按配置保留期清理终态批量任务。
     */
    @Scheduled(cron = "${omninest.photos.batch-retention.cleanup-cron:0 45 3 * * *}")
    public void cleanupExpired() {
        if (!properties.isEnabled()) {
            return;
        }
        Duration maxAge = properties.getMaxAge();
        if (maxAge == null || maxAge.isZero() || maxAge.isNegative()) {
            log.warn("照片批量任务保留时长无效，跳过清理");
            return;
        }
        int batchSize = Math.max(1, properties.getBatchSize());
        Instant cutoff = Instant.now().minus(maxAge);
        List<PhotoBatchTask> tasks = batchTaskRepository.findTerminalBefore(
                TERMINAL_STATUSES, cutoff, PageRequest.of(0, batchSize));
        int deleted = 0;
        int failed = 0;
        for (PhotoBatchTask task : tasks) {
            UUID resultFileId = parseResultFileId(task.getResult());
            if (resultFileId != null) {
                try {
                    derivedAssetStorageService.deleteDerivedFileNode(resultFileId);
                } catch (RuntimeException exception) {
                    failed++;
                    // 对象删除失败时保留任务行，下一轮继续重试，避免元数据已删、对象永久悬空。
                    log.warn("照片批量打包对象清理失败: taskId={}, errorType={}",
                            task.getId(), exception.getClass().getSimpleName());
                    continue;
                }
            }
            try {
                batchTaskRepository.delete(task);
                deleted++;
            } catch (RuntimeException exception) {
                failed++;
                log.warn("照片批量任务行清理失败: taskId={}, errorType={}",
                        task.getId(), exception.getClass().getSimpleName());
            }
        }
        if (deleted > 0 || failed > 0) {
            log.info("照片批量任务过期清理完成: deleted={}, failed={}", deleted, failed);
        }
    }

    /**
     * 解析结果字段中的 ZIP 文件节点 ID；字段缺失或格式异常时返回 {@code null}。
     */
    private UUID parseResultFileId(String result) {
        if (result == null || result.isBlank()) {
            return null;
        }
        String normalized = result.trim();
        if (normalized.length() >= 2 && normalized.startsWith("\"") && normalized.endsWith("\"")) {
            normalized = normalized.substring(1, normalized.length() - 1);
        }
        try {
            return UUID.fromString(normalized);
        } catch (IllegalArgumentException exception) {
            log.warn("照片批量任务结果格式异常，跳过对象清理: resultLength={}", normalized.length());
            return null;
        }
    }
}
