package com.omninest.modules.music.service;

import com.omninest.common.task.DomainTaskFailureConvergence;
import com.omninest.modules.music.domain.MusicScanJob;
import com.omninest.modules.music.repository.MusicScanJobRepository;
import com.omninest.modules.task.domain.TaskStatus;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 音乐扫描/刮削任务进入死信时把 {@code music_scan_jobs} 收敛为 FAILED。
 *
 * <p>领域表是前端轮询的唯一数据源：{@code sys_tasks} 已进死信而领域行停在
 * {@code RUNNING} 时，用户既看不到失败也无法重新发起（幂等去重会复用该行）。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicTaskFailureConvergence implements DomainTaskFailureConvergence {

    private static final Set<String> SUPPORTED_TASK_TYPES = Set.of("MUSIC_SCAN", "MUSIC_SCRAPE");

    /** {@code music_scan_jobs.message} 的列宽上限。 */
    private static final int MAX_MESSAGE_LENGTH = 500;

    /** 领域表已被写成终态时不再覆盖。 */
    private static final Set<String> TERMINAL_STATUSES = Set.of(
            "COMPLETED", "FAILED", "CANCELLED", "DLQ", "DISCARDED");

    private final MusicScanJobRepository scanJobRepository;

    @Override
    public boolean supports(String taskType) {
        return SUPPORTED_TASK_TYPES.contains(taskType);
    }

    @Override
    public void converge(UUID taskId, String reason) {
        scanJobRepository.findById(taskId)
                .filter(job -> !isTerminal(job.getStatus()))
                .ifPresent(job -> fail(job, reason));
    }

    private boolean isTerminal(String status) {
        return status != null && TERMINAL_STATUSES.contains(status.toUpperCase(java.util.Locale.ROOT));
    }

    private void fail(MusicScanJob job, String reason) {
        job.setStatus(TaskStatus.FAILED.getValue());
        job.setMessage(truncate("音乐任务超时未完成: " + reason));
        scanJobRepository.save(job);
        log.warn("音乐任务已收敛为失败终态: jobId={}, taskType={}", job.getId(), job.getStatus());
    }

    private String truncate(String message) {
        return message.length() <= MAX_MESSAGE_LENGTH
                ? message
                : message.substring(0, MAX_MESSAGE_LENGTH);
    }
}
