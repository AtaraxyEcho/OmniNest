package com.omninest.modules.photos.service;

import com.omninest.common.task.DomainTaskFailureConvergence;
import com.omninest.modules.photos.domain.PhotoBatchTask;
import com.omninest.modules.photos.domain.PhotoScanJob;
import com.omninest.modules.photos.repository.PhotoBatchTaskRepository;
import com.omninest.modules.photos.repository.PhotoScanJobRepository;
import com.omninest.modules.task.domain.TaskStatus;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 照片扫描/批处理任务进入死信时把领域表收敛为 FAILED。
 *
 * <p>前端轮询的是 {@code /photos/scan/{taskId}} 与 {@code /photos/batch/{taskId}}，
 * 只看领域表；{@code sys_tasks} 进 DLQ 后领域行若仍停在 {@code RUNNING}，
 * 用户侧会看到永久"扫描中"且没有重试入口。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoTaskFailureConvergence implements DomainTaskFailureConvergence {

    private static final String PHOTO_SCAN = "PHOTO_SCAN";
    private static final String PHOTO_BATCH = "PHOTO_BATCH";

    /** {@code photo_scan_jobs.message} 的列宽上限。 */
    private static final int MAX_MESSAGE_LENGTH = 500;

    /** 领域表已被他人写成终态时不再覆盖（含批处理自己的终态取值）。 */
    private static final Set<String> TERMINAL_STATUSES = Set.of(
            "COMPLETED", "FAILED", "CANCELLED", "DLQ", "DISCARDED");

    private final PhotoScanJobRepository scanJobRepository;
    private final PhotoBatchTaskRepository batchTaskRepository;

    @Override
    public boolean supports(String taskType) {
        return PHOTO_SCAN.equals(taskType) || PHOTO_BATCH.equals(taskType);
    }

    @Override
    public void converge(UUID taskId, String reason) {
        scanJobRepository.findById(taskId)
                .filter(job -> !isTerminal(job.getStatus()))
                .ifPresent(job -> failScanJob(job, reason));
        batchTaskRepository.findById(taskId)
                .filter(task -> !isTerminal(task.getStatus()))
                .ifPresent(task -> failBatchTask(task, reason));
    }

    private boolean isTerminal(String status) {
        return status != null && TERMINAL_STATUSES.contains(status.toUpperCase(java.util.Locale.ROOT));
    }

    private void failScanJob(PhotoScanJob job, String reason) {
        job.setStatus(TaskStatus.FAILED.getValue());
        job.setMessage(truncate("扫描任务超时未完成: " + reason));
        scanJobRepository.save(job);
        log.warn("照片扫描任务已收敛为失败终态: jobId={}", job.getId());
    }

    private void failBatchTask(PhotoBatchTask task, String reason) {
        task.setStatus(TaskStatus.FAILED.getValue());
        task.setErrorMessage(truncate("批处理任务超时未完成: " + reason));
        batchTaskRepository.save(task);
        log.warn("照片批处理任务已收敛为失败终态: taskId={}", task.getId());
    }

    private String truncate(String message) {
        return message.length() <= MAX_MESSAGE_LENGTH
                ? message
                : message.substring(0, MAX_MESSAGE_LENGTH);
    }
}
