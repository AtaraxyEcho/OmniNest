package com.omninest.modules.video.service;

import com.omninest.common.concurrency.DistributedLock;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.LocalMediaDiscoveredFile;
import com.omninest.modules.file.dto.LocalMediaDiscoveryResult;
import com.omninest.modules.file.dto.LocalMediaExistingRef;
import com.omninest.modules.file.service.LocalMediaAvailabilityService;
import com.omninest.modules.file.service.LocalMediaDiscoveryService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaImportPolicy;
import com.omninest.modules.video.domain.MediaScanBatch;
import com.omninest.modules.video.domain.MediaScanCandidate;
import com.omninest.modules.video.domain.MediaScanRun;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.event.LocalVideoLibraryScanRequestedEvent;
import com.omninest.modules.video.repository.MediaScanBatchRepository;
import com.omninest.modules.video.repository.MediaScanCandidateRepository;
import com.omninest.modules.video.repository.MediaScanRunRepository;
import com.omninest.modules.video.repository.VideoLibrarySourceRepository;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CancellationException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Worker 中执行本地来源的流式发现和候选持久化。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MediaLibraryDiscoveryExecutor {
    private static final Duration DISCOVERY_LOCK_TTL = Duration.ofHours(6);
    private static final int MISSING_CONFIRMATION_SCANS = 2;
    private static final Duration MISSING_GRACE_PERIOD = Duration.ofHours(24);

    private final MediaScanRunRepository runRepository;
    private final MediaScanCandidateRepository candidateRepository;
    private final MediaScanBatchRepository batchRepository;
    private final VideoLibrarySourceRepository sourceRepository;
    private final LocalMediaDiscoveryService discoveryService;
    private final LocalMediaAvailabilityService availabilityService;
    private final LocalMediaLibraryClassifier classifier;
    private final AdaptiveChunkPolicy chunkPolicy;
    private final TaskRecordService taskRecordService;
    private final DistributedLock distributedLock;
    private final PlatformTransactionManager transactionManager;

    /** 执行发现任务，发现阶段不会创建正式 FileNode 或媒体实体。 */
    public void execute(LocalVideoLibraryScanRequestedEvent event) {
        if (!taskRecordService.claimForExecution(event.taskId(), "DISCOVERING")) {
            return;
        }
        VideoLibrarySource source = requireSource(event.ownerUserId(), event.sourceId());
        String lockKey = "lock:media-discovery:" + source.getStorageLocationId();
        String lockToken = distributedLock.newToken();
        if (!distributedLock.tryLock(lockKey, lockToken, DISCOVERY_LOCK_TTL)) {
            throw new BusinessException(ErrorCode.CONFLICT, "该存储位置已有媒体发现任务正在执行");
        }
        try {
            prepareRun(event, source);
            DiscoveryAccumulator accumulator = new DiscoveryAccumulator(event, source);
            LocalMediaDiscoveryResult discovery = discoveryService.discover(
                    event.ownerUserId(),
                    source.getStorageLocationId(),
                    source.getRelativeRoot(),
                    accumulator::accept
            );
            accumulator.flush();
            int missingCount = availabilityService.finishSuccessfulScan(
                    event.ownerUserId(),
                    source.getStorageLocationId(),
                    source.getRelativeRoot(),
                    event.scanRunId(),
                    MISSING_CONFIRMATION_SCANS,
                    MISSING_GRACE_PERIOD
            );
            completeRun(event, source, discovery, accumulator, missingCount);
        } catch (CancellationException exception) {
            markCancelled(event);
        } catch (RuntimeException exception) {
            markFailed(event, exception);
            throw exception;
        } finally {
            if (!distributedLock.unlock(lockKey, lockToken)) {
                log.warn("本地媒体发现锁释放失败: sourceId={}, scanRunId={}", event.sourceId(), event.scanRunId());
            }
        }
    }

    private void prepareRun(LocalVideoLibraryScanRequestedEvent event, VideoLibrarySource source) {
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        transaction.executeWithoutResult(status -> {
            MediaScanRun run = requireRun(event.ownerUserId(), event.scanRunId());
            run.setStatus("DISCOVERING");
            run.setPhase("DISCOVERY");
            run.setStartedAt(run.getStartedAt() == null ? Instant.now() : run.getStartedAt());
            run.setFinishedAt(null);
            runRepository.save(run);
            VideoLibrarySource current = requireSource(event.ownerUserId(), source.getId());
            current.setScanStatus("DISCOVERING");
            current.setHealthStatus("AVAILABLE");
            current.setLastErrorCode(null);
            sourceRepository.save(current);
        });
    }

    private void completeRun(
            LocalVideoLibraryScanRequestedEvent event,
            VideoLibrarySource source,
            LocalMediaDiscoveryResult discovery,
            DiscoveryAccumulator accumulator,
            int missingCount
    ) {
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        transaction.executeWithoutResult(status -> {
            Instant now = Instant.now();
            MediaScanRun run = requireRun(event.ownerUserId(), event.scanRunId());
            run.setStatus("READY");
            run.setPhase("DISCOVERY");
            run.setDiscoveredCount(discovery.scannedFileCount());
            run.setCandidateCount(accumulator.candidateCount);
            run.setExistingCount(accumulator.existingCount);
            run.setConflictCount(accumulator.changedCount);
            run.setUnmatchedCount(accumulator.unmatchedCount);
            run.setMissingCount(missingCount);
            run.setSelectedCount(accumulator.selectedCount);
            run.setFinishedAt(now);
            runRepository.save(run);

            VideoLibrarySource current = requireSource(event.ownerUserId(), source.getId());
            current.setScanStatus("READY");
            current.setHealthStatus(missingCount > 0 ? "DEGRADED" : "AVAILABLE");
            current.setLastScannedAt(now);
            current.setLastSuccessfulScanAt(now);
            current.setLastScannedCount(discovery.videoCount());
            current.setLastCandidateCount(accumulator.candidateCount);
            current.setLastMissingCount(missingCount);
            current.setLastErrorCode(null);
            sourceRepository.save(current);

            taskRecordService.markCompleted(event.taskId(), resultMap(discovery, accumulator, missingCount));
        });
        log.info(
                "本地媒体发现完成: sourceId={}, scanRunId={}, candidates={}, existing={}, unmatched={}, missing={}",
                source.getId(),
                event.scanRunId(),
                accumulator.candidateCount,
                accumulator.existingCount,
                accumulator.unmatchedCount,
                missingCount
        );
    }

    private Map<String, Object> resultMap(
            LocalMediaDiscoveryResult discovery,
            DiscoveryAccumulator accumulator,
            int missingCount
    ) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("scannedFileCount", discovery.scannedFileCount());
        result.put("videoCount", discovery.videoCount());
        result.put("candidateCount", accumulator.candidateCount);
        result.put("existingCount", accumulator.existingCount);
        result.put("changedCount", accumulator.changedCount);
        result.put("unmatchedCount", accumulator.unmatchedCount);
        result.put("selectedCount", accumulator.selectedCount);
        result.put("missingCount", missingCount);
        result.put("externalMetadataRequestCount", 0);
        return result;
    }

    private void markFailed(LocalVideoLibraryScanRequestedEvent event, RuntimeException exception) {
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        transaction.executeWithoutResult(status -> {
            runRepository.findByIdAndOwnerUserId(event.scanRunId(), event.ownerUserId()).ifPresent(run -> {
                run.setStatus("FAILED");
                run.setFinishedAt(Instant.now());
                runRepository.save(run);
            });
            sourceRepository.findByIdAndOwnerUserId(event.sourceId(), event.ownerUserId()).ifPresent(source -> {
                source.setScanStatus("FAILED");
                source.setLastErrorCode(errorCode(exception));
                if (exception instanceof BusinessException businessException
                        && businessException.errorCode() == ErrorCode.DEPENDENCY_UNAVAILABLE) {
                    source.setHealthStatus("OFFLINE");
                }
                sourceRepository.save(source);
            });
        });
    }

    private void markCancelled(LocalVideoLibraryScanRequestedEvent event) {
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        transaction.executeWithoutResult(status -> {
            runRepository.findByIdAndOwnerUserId(event.scanRunId(), event.ownerUserId()).ifPresent(run -> {
                run.setStatus("CANCELLED");
                run.setFinishedAt(Instant.now());
                runRepository.save(run);
            });
            sourceRepository.findByIdAndOwnerUserId(event.sourceId(), event.ownerUserId()).ifPresent(source -> {
                source.setScanStatus("CANCELLED");
                sourceRepository.save(source);
            });
            taskRecordService.markCancelled(event.taskId());
        });
    }

    private String errorCode(RuntimeException exception) {
        if (exception instanceof BusinessException businessException) {
            return businessException.errorCode().name();
        }
        return ErrorCode.INTERNAL_ERROR.name();
    }

    private VideoLibrarySource requireSource(UUID ownerUserId, UUID sourceId) {
        return sourceRepository.findByIdAndOwnerUserId(sourceId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "影视库来源不存在"));
    }

    private MediaScanRun requireRun(UUID ownerUserId, UUID runId) {
        return runRepository.findByIdAndOwnerUserId(runId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "媒体发现运行不存在"));
    }

    private final class DiscoveryAccumulator {
        private final LocalVideoLibraryScanRequestedEvent event;
        private final VideoLibrarySource source;
        private final List<LocalMediaDiscoveredFile> buffer = new ArrayList<>();
        private int plannedSize;
        private int batchNo;
        private int candidateCount;
        private int existingCount;
        private int changedCount;
        private int unmatchedCount;
        private int selectedCount;
        private long payloadBytes;

        private DiscoveryAccumulator(LocalVideoLibraryScanRequestedEvent event, VideoLibrarySource source) {
            this.event = event;
            this.source = source;
            MediaScanBatch latest = batchRepository
                    .findFirstByOwnerUserIdAndScanRunIdAndPhaseOrderByBatchNoDesc(
                            event.ownerUserId(),
                            event.scanRunId(),
                            "DISCOVERY"
                    )
                    .orElse(null);
            this.batchNo = latest == null ? 0 : latest.getBatchNo() + 1;
            this.plannedSize = latest == null
                    ? chunkPolicy.initialSize(
                            BatchWorkloadProfile.DISCOVERY,
                            Math.max(1, source.getLastScannedCount())
                    )
                    : latest.getNextSuggestedSize();
            this.candidateCount = Math.toIntExact(candidateRepository.countByOwnerUserIdAndScanRunId(
                    event.ownerUserId(),
                    event.scanRunId()
            ));
            this.existingCount = Math.toIntExact(candidateRepository.countByOwnerUserIdAndScanRunIdAndMatchStatus(
                    event.ownerUserId(),
                    event.scanRunId(),
                    "EXISTING"
            ));
            this.changedCount = Math.toIntExact(candidateRepository.countByOwnerUserIdAndScanRunIdAndMatchStatus(
                    event.ownerUserId(),
                    event.scanRunId(),
                    "CHANGED"
            ));
            this.unmatchedCount = Math.toIntExact(candidateRepository.countByOwnerUserIdAndScanRunIdAndMatchStatus(
                    event.ownerUserId(),
                    event.scanRunId(),
                    "UNMATCHED"
            ));
            this.selectedCount = Math.toIntExact(candidateRepository.countByOwnerUserIdAndScanRunIdAndSelectedTrue(
                    event.ownerUserId(),
                    event.scanRunId()
            ));
        }

        private void accept(LocalMediaDiscoveredFile file) {
            if (taskRecordService.isCancelled(event.taskId())) {
                throw new CancellationException("media discovery cancelled");
            }
            buffer.add(file);
            payloadBytes += estimateBytes(file);
            if (buffer.size() >= plannedSize || payloadBytes >= BatchWorkloadProfile.DISCOVERY.memoryBudgetBytes()) {
                flush();
            }
        }

        private void flush() {
            if (buffer.isEmpty()) {
                return;
            }
            List<LocalMediaDiscoveredFile> batchFiles = List.copyOf(buffer);
            long batchBytes = payloadBytes;
            buffer.clear();
            payloadBytes = 0;
            Instant startedAt = Instant.now();
            List<String> relativePaths = batchFiles.stream().map(LocalMediaDiscoveredFile::relativePath).toList();
            Map<String, LocalMediaExistingRef> existing = availabilityService.findExisting(
                    event.ownerUserId(),
                    source.getStorageLocationId(),
                    relativePaths
            );
            Set<String> persistedPaths = Set.copyOf(candidateRepository.findPersistedRelativePaths(
                    event.ownerUserId(),
                    event.scanRunId(),
                    relativePaths
            ));
            List<MediaScanCandidate> candidates = batchFiles.stream()
                    .filter(file -> !persistedPaths.contains(file.relativePath()))
                    .map(file -> toCandidate(file, existing.get(file.relativePath())))
                    .toList();
            if (!candidates.isEmpty()) {
                TransactionTemplate transaction = new TransactionTemplate(transactionManager);
                transaction.executeWithoutResult(status -> candidateRepository.saveAll(candidates));
            }
            availabilityService.observe(
                    event.ownerUserId(),
                    source.getStorageLocationId(),
                    event.scanRunId(),
                    existing.keySet()
            );
            long durationMillis = Math.max(1, Duration.between(startedAt, Instant.now()).toMillis());
            int previousSize = plannedSize;
            plannedSize = chunkPolicy.nextSize(
                    BatchWorkloadProfile.DISCOVERY,
                    Math.max(source.getLastScannedCount(), candidateCount + candidates.size()),
                    plannedSize,
                    new AdaptiveChunkPolicy.ChunkFeedback(
                            candidates.size(),
                            batchBytes,
                            durationMillis,
                            false
                    ),
                    null
            );
            updateCounters(candidates);
            if (!candidates.isEmpty()) {
                saveBatch(previousSize, candidates.size(), batchBytes, durationMillis);
            }
            updateProgress();
        }

        private MediaScanCandidate toCandidate(
                LocalMediaDiscoveredFile file,
                LocalMediaExistingRef existing
        ) {
            LocalMediaLibraryClassifier.PreviewIdentity identity = classifier.preview(
                    source,
                    file.relativePath(),
                    file.fileName()
            );
            String matchStatus = identity.matchStatus();
            if (existing != null && !"UNMATCHED".equals(matchStatus)) {
                matchStatus = file.providerEtag().equals(existing.providerEtag()) ? "EXISTING" : "CHANGED";
            }
            MediaScanCandidate candidate = new MediaScanCandidate();
            candidate.setOwnerUserId(event.ownerUserId());
            candidate.setScanRunId(event.scanRunId());
            candidate.setLibrarySourceId(source.getId());
            candidate.setRelativePath(file.relativePath());
            candidate.setFileName(file.fileName());
            candidate.setSizeBytes(file.sizeBytes());
            candidate.setModifiedAt(file.modifiedAt());
            candidate.setProviderEtag(file.providerEtag());
            candidate.setCandidateType(identity.candidateType());
            candidate.setGroupTitle(identity.groupTitle());
            candidate.setGroupId(groupId(source.getId(), identity.groupTitle()));
            candidate.setSeasonNumber(identity.seasonNumber());
            candidate.setEpisodeNumber(identity.episodeNumber());
            candidate.setMatchStatus(matchStatus);
            candidate.setReasonCode(identity.reasonCode());
            candidate.setExistingFileNodeId(existing == null ? null : existing.fileNodeId());
            candidate.setSelected(defaultSelected(source, matchStatus));
            candidate.setApplyStatus("PENDING");
            return candidate;
        }

        private boolean defaultSelected(VideoLibrarySource currentSource, String matchStatus) {
            if ("UNMATCHED".equals(matchStatus) || "AMBIGUOUS".equals(matchStatus)) {
                return false;
            }
            MediaImportPolicy policy = MediaImportPolicy.valueOf(currentSource.getImportPolicy());
            return policy != MediaImportPolicy.MANUAL_REVIEW;
        }

        private void updateCounters(List<MediaScanCandidate> candidates) {
            candidateCount += candidates.size();
            existingCount += (int) candidates.stream().filter(item -> "EXISTING".equals(item.getMatchStatus())).count();
            changedCount += (int) candidates.stream().filter(item -> "CHANGED".equals(item.getMatchStatus())).count();
            unmatchedCount += (int) candidates.stream().filter(item -> "UNMATCHED".equals(item.getMatchStatus())).count();
            selectedCount += (int) candidates.stream().filter(MediaScanCandidate::isSelected).count();
        }

        private void saveBatch(int previousSize, int itemCount, long bytes, long durationMillis) {
            MediaScanBatch batch = new MediaScanBatch();
            batch.setOwnerUserId(event.ownerUserId());
            batch.setScanRunId(event.scanRunId());
            batch.setPhase("DISCOVERY");
            batch.setBatchNo(batchNo++);
            batch.setStatus("COMPLETED");
            batch.setPlannedSize(previousSize);
            batch.setItemCount(itemCount);
            batch.setSuccessCount(itemCount);
            batch.setPayloadBytes(bytes);
            batch.setDurationMillis(durationMillis);
            batch.setNextSuggestedSize(plannedSize);
            batch.setFinishedAt(Instant.now());
            batchRepository.save(batch);
        }

        private void updateProgress() {
            long estimate = Math.max(source.getLastScannedCount(), candidateCount);
            int progress = estimate <= 0
                    ? 10
                    : Math.min(90, 10 + (int) Math.round(candidateCount * 80.0 / Math.max(estimate, candidateCount)));
            taskRecordService.updateExecution(event.taskId(), "DISCOVERING", progress);
            TransactionTemplate transaction = new TransactionTemplate(transactionManager);
            transaction.executeWithoutResult(status -> {
                MediaScanRun run = requireRun(event.ownerUserId(), event.scanRunId());
                run.setDiscoveredCount(candidateCount);
                run.setCandidateCount(candidateCount);
                run.setExistingCount(existingCount);
                run.setConflictCount(changedCount);
                run.setUnmatchedCount(unmatchedCount);
                run.setSelectedCount(selectedCount);
                runRepository.save(run);
            });
        }

        private long estimateBytes(LocalMediaDiscoveredFile file) {
            return 256L + (file.relativePath().length() + file.fileName().length()) * 2L;
        }

        private UUID groupId(UUID sourceId, String title) {
            String key = sourceId + ":" + title.trim().toLowerCase(Locale.ROOT);
            return UUID.nameUUIDFromBytes(key.getBytes(StandardCharsets.UTF_8));
        }
    }
}
