package com.omninest.modules.video.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.LocalMediaScanEntry;
import com.omninest.modules.file.service.LocalMediaIndexService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaScanBatch;
import com.omninest.modules.video.domain.MediaScanCandidate;
import com.omninest.modules.video.domain.MediaScanRun;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.event.LocalVideoLibraryApplyRequestedEvent;
import com.omninest.modules.video.repository.MediaScanBatchRepository;
import com.omninest.modules.video.repository.MediaScanCandidateRepository;
import com.omninest.modules.video.repository.MediaScanRunRepository;
import com.omninest.modules.video.repository.VideoLibrarySourceRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 将用户选择的媒体候选分批登记为 FileNode 和媒体实体。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MediaLibraryApplyExecutor {

    private final MediaScanRunRepository runRepository;
    private final MediaScanCandidateRepository candidateRepository;
    private final MediaScanBatchRepository batchRepository;
    private final VideoLibrarySourceRepository sourceRepository;
    private final LocalMediaIndexService localMediaIndexService;
    private final LocalMediaLibraryClassifier classifier;
    private final AdaptiveChunkPolicy chunkPolicy;
    private final TaskRecordService taskRecordService;
    private final ReadThroughCache readThroughCache;
    private final MediaSyncEventService syncEventService;
    private final PlatformTransactionManager transactionManager;

    /** 执行按需入库任务。 */
    public void execute(LocalVideoLibraryApplyRequestedEvent event) {
        if (!taskRecordService.claimForExecution(event.taskId(), "APPLYING")) {
            return;
        }
        try {
            VideoLibrarySource source = prepare(event);
            if (applyBatches(event, source)) {
                complete(event, source);
            }
        } catch (RuntimeException exception) {
            markFailed(event, exception);
            throw exception;
        }
    }

    private VideoLibrarySource prepare(LocalVideoLibraryApplyRequestedEvent event) {
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        return transaction.execute(status -> {
            MediaScanRun run = requireRun(event.ownerUserId(), event.scanRunId());
            if (!List.of("QUEUED", "PAUSED", "PARTIAL", "FAILED").contains(run.getStatus())) {
                throw new BusinessException(ErrorCode.CONFLICT, "当前媒体发现运行不能开始入库");
            }
            candidateRepository.resetInterruptedCandidates(event.ownerUserId(), event.scanRunId());
            if ("PARTIAL".equals(run.getStatus())) {
                candidateRepository.resetSelectedFailures(event.ownerUserId(), event.scanRunId());
            }
            VideoLibrarySource source = requireSource(event.ownerUserId(), event.sourceId());
            run.setStatus("APPLYING");
            run.setPhase("APPLY");
            run.setFinishedAt(null);
            runRepository.save(run);
            source.setScanStatus("APPLYING");
            source.setLastErrorCode(null);
            return sourceRepository.save(source);
        });
    }

    private boolean applyBatches(LocalVideoLibraryApplyRequestedEvent event, VideoLibrarySource source) {
        long selectedCount = candidateRepository.countByOwnerUserIdAndScanRunIdAndSelectedTrue(
                event.ownerUserId(),
                event.scanRunId()
        );
        MediaScanBatch latest = batchRepository
                .findFirstByOwnerUserIdAndScanRunIdAndPhaseOrderByBatchNoDesc(
                        event.ownerUserId(),
                        event.scanRunId(),
                        "APPLY"
                )
                .orElse(null);
        int batchNo = latest == null ? 0 : latest.getBatchNo() + 1;
        int plannedSize = latest == null
                ? chunkPolicy.initialSize(BatchWorkloadProfile.APPLY, selectedCount)
                : latest.getNextSuggestedSize();
        while (true) {
            MediaScanRun current = requireRun(event.ownerUserId(), event.scanRunId());
            if ("CANCELLED".equals(current.getStatus()) || taskRecordService.isCancelled(event.taskId())) {
                taskRecordService.markCancelled(event.taskId());
                return false;
            }
            if ("PAUSED".equals(current.getStatus())) {
                taskRecordService.markCompleted(event.taskId(), Map.of("runStatus", current.getStatus()));
                return false;
            }
            List<MediaScanCandidate> candidates = candidateRepository
                    .findByOwnerUserIdAndScanRunIdAndSelectedTrueAndApplyStatusOrderByRelativePathAsc(
                            event.ownerUserId(),
                            event.scanRunId(),
                            "PENDING",
                            PageRequest.of(0, plannedSize)
                    )
                    .getContent();
            if (candidates.isEmpty()) {
                return true;
            }
            Instant startedAt = Instant.now();
            int success = 0;
            int failure = 0;
            long payloadBytes = 0;
            for (MediaScanCandidate candidate : candidates) {
                payloadBytes += 256L + candidate.getRelativePath().length() * 2L;
                if (applyCandidate(event.ownerUserId(), source, candidate)) {
                    success++;
                } else {
                    failure++;
                }
            }
            long durationMillis = Math.max(1, Duration.between(startedAt, Instant.now()).toMillis());
            long processed = candidateRepository.countByOwnerUserIdAndScanRunIdAndApplyStatus(
                    event.ownerUserId(),
                    event.scanRunId(),
                    "APPLIED"
            ) + candidateRepository.countByOwnerUserIdAndScanRunIdAndApplyStatus(
                    event.ownerUserId(),
                    event.scanRunId(),
                    "FAILED"
            );
            Long remaining = Math.max(0, selectedCount - processed);
            int nextSize = chunkPolicy.nextSize(
                    BatchWorkloadProfile.APPLY,
                    selectedCount,
                    plannedSize,
                    new AdaptiveChunkPolicy.ChunkFeedback(
                            candidates.size(),
                            payloadBytes,
                            durationMillis,
                            failure > success
                    ),
                    remaining == 0 ? null : remaining
            );
            saveBatch(
                    event,
                    batchNo++,
                    plannedSize,
                    nextSize,
                    candidates.size(),
                    success,
                    failure,
                    payloadBytes,
                    durationMillis
            );
            updateProgress(event, selectedCount, processed);
            plannedSize = nextSize;
        }
    }

    private boolean applyCandidate(
            UUID ownerUserId,
            VideoLibrarySource source,
            MediaScanCandidate candidate
    ) {
        if ("UNMATCHED".equals(candidate.getMatchStatus()) || "AMBIGUOUS".equals(candidate.getMatchStatus())) {
            candidate.setApplyStatus("FAILED");
            candidate.setErrorSummary("候选项需要先完成手动匹配");
            candidateRepository.save(candidate);
            return false;
        }
        try {
            candidate.setApplyStatus("APPLYING");
            MediaScanCandidate working = candidateRepository.save(candidate);
            LocalMediaScanEntry entry = localMediaIndexService.registerSelected(
                    ownerUserId,
                    source.getStorageLocationId(),
                    working.getRelativePath()
            );
            LocalMediaLibraryClassifier.ClassificationOutcome outcome = classifier.classify(ownerUserId, source, entry);
            if (outcome == LocalMediaLibraryClassifier.ClassificationOutcome.UNMATCHED) {
                working.setApplyStatus("FAILED");
                working.setErrorSummary("媒体分类器无法确认该候选项");
                candidateRepository.save(working);
                return false;
            }
            working.setAppliedFileNodeId(entry.fileNodeId());
            working.setApplyStatus("APPLIED");
            working.setErrorSummary(null);
            candidateRepository.save(working);
            return true;
        } catch (RuntimeException exception) {
            MediaScanCandidate failed = candidateRepository
                    .findById(candidate.getId())
                    .orElse(candidate);
            failed.setApplyStatus("FAILED");
            failed.setErrorSummary(errorSummary(exception));
            candidateRepository.save(failed);
            return false;
        }
    }

    private void saveBatch(
            LocalVideoLibraryApplyRequestedEvent event,
            int batchNo,
            int plannedSize,
            int nextSize,
            int itemCount,
            int success,
            int failure,
            long payloadBytes,
            long durationMillis
    ) {
        MediaScanBatch batch = new MediaScanBatch();
        batch.setOwnerUserId(event.ownerUserId());
        batch.setScanRunId(event.scanRunId());
        batch.setPhase("APPLY");
        batch.setBatchNo(batchNo);
        batch.setStatus(failure == 0 ? "COMPLETED" : success == 0 ? "FAILED" : "PARTIAL");
        batch.setPlannedSize(plannedSize);
        batch.setItemCount(itemCount);
        batch.setSuccessCount(success);
        batch.setFailureCount(failure);
        batch.setPayloadBytes(payloadBytes);
        batch.setDurationMillis(durationMillis);
        batch.setNextSuggestedSize(nextSize);
        batch.setFinishedAt(Instant.now());
        batchRepository.save(batch);
    }

    private void updateProgress(LocalVideoLibraryApplyRequestedEvent event, long selectedCount, long processed) {
        int progress = selectedCount == 0
                ? 95
                : Math.min(95, 10 + (int) Math.round(processed * 85.0 / selectedCount));
        taskRecordService.updateExecution(event.taskId(), "APPLYING", progress);
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        transaction.executeWithoutResult(status -> {
            MediaScanRun run = requireRun(event.ownerUserId(), event.scanRunId());
            run.setAppliedCount(Math.toIntExact(candidateRepository.countByOwnerUserIdAndScanRunIdAndApplyStatus(
                    event.ownerUserId(),
                    event.scanRunId(),
                    "APPLIED"
            )));
            run.setFailedCount(Math.toIntExact(candidateRepository.countByOwnerUserIdAndScanRunIdAndApplyStatus(
                    event.ownerUserId(),
                    event.scanRunId(),
                    "FAILED"
            )));
            runRepository.save(run);
        });
    }

    private void complete(LocalVideoLibraryApplyRequestedEvent event, VideoLibrarySource source) {
        long applied = candidateRepository.countByOwnerUserIdAndScanRunIdAndApplyStatus(
                event.ownerUserId(),
                event.scanRunId(),
                "APPLIED"
        );
        long failed = candidateRepository.countByOwnerUserIdAndScanRunIdAndApplyStatus(
                event.ownerUserId(),
                event.scanRunId(),
                "FAILED"
        );
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        transaction.executeWithoutResult(status -> {
            String finalStatus = failed == 0 ? "COMPLETED" : "PARTIAL";
            MediaScanRun run = requireRun(event.ownerUserId(), event.scanRunId());
            run.setStatus(finalStatus);
            run.setAppliedCount(Math.toIntExact(applied));
            run.setFailedCount(Math.toIntExact(failed));
            run.setFinishedAt(Instant.now());
            runRepository.save(run);
            VideoLibrarySource current = requireSource(event.ownerUserId(), source.getId());
            current.setScanStatus(finalStatus);
            current.setLastCreatedCount(Math.toIntExact(applied));
            current.setLastErrorCode(failed == 0 ? null : "MEDIA_LIBRARY_PARTIAL_APPLY");
            sourceRepository.save(current);
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("selectedCount", run.getSelectedCount());
            result.put("appliedCount", applied);
            result.put("failedCount", failed);
            result.put("externalMetadataRequestCount", 0);
            // 入库改变了影视库统计与最近添加，需立即失效 dashboard 缓存，
            // 并广播库级同步事件让各端实时感知新入库内容。
            readThroughCache.invalidate("omninest:dashboard:video:" + event.ownerUserId());
            syncEventService.invalidate(
                    event.ownerUserId(),
                    SyncScope.VIDEO,
                    "VIDEO_LIBRARY",
                    Map.of("source", "APPLY", "applied", applied)
            );
            taskRecordService.markCompleted(event.taskId(), result);
        });
        log.info(
                "本地媒体按需入库完成: sourceId={}, scanRunId={}, applied={}, failed={}",
                source.getId(),
                event.scanRunId(),
                applied,
                failed
        );
    }

    private void markFailed(LocalVideoLibraryApplyRequestedEvent event, RuntimeException exception) {
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        transaction.executeWithoutResult(status -> {
            runRepository.findByIdAndOwnerUserId(event.scanRunId(), event.ownerUserId()).ifPresent(run -> {
                run.setStatus("FAILED");
                run.setFinishedAt(Instant.now());
                runRepository.save(run);
            });
            sourceRepository.findByIdAndOwnerUserId(event.sourceId(), event.ownerUserId()).ifPresent(source -> {
                source.setScanStatus("FAILED");
                source.setLastErrorCode(errorSummary(exception));
                sourceRepository.save(source);
            });
        });
    }

    private String errorSummary(RuntimeException exception) {
        if (exception instanceof BusinessException businessException) {
            return businessException.errorCode().name();
        }
        return exception.getClass().getSimpleName();
    }

    private MediaScanRun requireRun(UUID ownerUserId, UUID runId) {
        return runRepository.findByIdAndOwnerUserId(runId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "媒体发现运行不存在"));
    }

    private VideoLibrarySource requireSource(UUID ownerUserId, UUID sourceId) {
        return sourceRepository.findByIdAndOwnerUserId(sourceId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "影视库来源不存在"));
    }
}
