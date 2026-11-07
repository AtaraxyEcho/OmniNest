package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.ImportTaskStatus;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.repository.FileIngressItemRepository;
import com.omninest.modules.file.repository.StorageImportTaskRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 外部存储导入业务行的终态收敛。
 *
 * <p>失败终态必须与配额结算同事务：{@code storage_import_tasks.status} 改成 FAILED
 * 却不结算 {@code EXTERNAL_IMPORT} 预占，用户会在最长 24 小时内既传不了新文件、
 * 也看不到是谁占着额度。执行侧与死信收敛侧共用同一份实现，避免两处口径漂移。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ExternalImportTaskStatusService {

    private final StorageImportTaskRepository importTaskRepository;
    private final FileIngressItemRepository ingressItemRepository;
    private final StorageQuotaService storageQuotaService;

    /**
     * 把业务行落到失败终态并结算预占。
     *
     * @param importTaskId 导入任务 ID
     * @param errorSummary 失败原因摘要
     */
    @Transactional(rollbackFor = Exception.class)
    public void markFailed(UUID importTaskId, String errorSummary) {
        importTaskRepository.findById(importTaskId)
                .filter(task -> !ImportTaskStatus.CANCELLED.getValue().equals(task.getStatus()))
                .filter(task -> !ImportTaskStatus.FAILED.getValue().equals(task.getStatus()))
                .ifPresent(task -> fail(task, errorSummary));
    }

    private void fail(StorageImportTask task, String errorSummary) {
        // 共享空间导入不建个人预留，settle 在无预留行时是空操作。
        storageQuotaService.settleReservation(
                "EXTERNAL_IMPORT", task.getId(), importedBytes(task.getId()));
        task.setStatus(ImportTaskStatus.FAILED.getValue());
        task.setSpeedBytes(0L);
        task.setErrorSummary(errorSummary);
        importTaskRepository.save(task);
        log.warn("外部存储导入任务已收敛为失败终态: taskId={}", task.getId());
    }

    /**
     * 该导入任务已真正落库的字节数：结算退还没写入的部分，已入库的仍需计入用量。
     */
    private long importedBytes(UUID importTaskId) {
        return ingressItemRepository.sumImportedBytesByTaskId(importTaskId);
    }
}
