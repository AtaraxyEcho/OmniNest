package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.common.util.ThrowableDescriber;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 转码编排服务：查询源视频 → 转码 → 存储结果 → 创建新视频条目 → 更新任务状态。
 * Docker 转码在事务外执行，仅 DB 写入使用短事务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TranscodeExecutionService {
    private final MediaVideoItemRepository videoItemRepository;
    private final TaskRecordService taskRecordService;
    private final VideoTranscodeService videoTranscodeService;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final TransactionTemplate transactionTemplate;
    private final NotificationPublisher notificationService;
    private final MediaSyncEventService syncEventService;
    private final FileLifecycleGuard fileLifecycleGuard;

    /**
     * 执行 H265 转码任务。
     *
     * @param taskId 任务 ID
     * @param videoItemId 源视频条目 ID
     * @param ownerUserId 所有者用户 ID
     */
    public void execute(UUID taskId, UUID videoItemId, UUID ownerUserId) {
        if (!taskRecordService.claimForExecution(taskId, "TRANSCODING")) {
            return;
        }

        MediaVideoItem sourceItem = findActiveSource(taskId, videoItemId, ownerUserId);
        if (sourceItem == null) {
            return;
        }

        // 阶段 0：音频转码（仅当音频编码不兼容 Web 端时执行）
        String audioCodec = sourceItem.getAudioCodec();
        if (audioCodec != null && VideoStreamService.WEB_UNSUPPORTED_AUDIO.contains(
                audioCodec.trim().toLowerCase(Locale.ROOT))) {
            executeAudioTranscode(taskId, videoItemId, ownerUserId, false);
            sourceItem = videoItemRepository.findById(videoItemId).orElse(sourceItem);
        }

        final MediaVideoItem finalSourceItem = sourceItem;
        Path transcodedFile = null;
        UUID derivedFileNodeId = null;
        try {
            // 阶段 1：Docker 转码（事务外，可能持续数分钟到数小时）
            transcodedFile = videoTranscodeService.transcodeToH265(
                    ownerUserId, finalSourceItem.getFileNodeId(), videoItemId);

            // 阶段 2：通过文件模块保存派生资产。
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, finalSourceItem.getFileNodeId());
            long sizeBytes = Files.size(transcodedFile);
            derivedFileNodeId = derivedAssetStorageService.store(
                    ownerUserId,
                    "VIDEO",
                    videoItemId,
                    "TRANSCODE",
                    finalSourceItem.getFileNodeId() + "_h265.mp4",
                    "h265.mp4",
                    "video/mp4",
                    transcodedFile
            );

            // 阶段 3：创建派生视频版本并更新任务状态。
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, finalSourceItem.getFileNodeId());
            UUID persistedDerivedFileNodeId = derivedFileNodeId;
            transactionTemplate.executeWithoutResult(status ->
                    persistDerivedVersion(taskId, ownerUserId, finalSourceItem, persistedDerivedFileNodeId,
                            "H265", "hevc",
                            finalSourceItem.getAudioCodec(), "mp4", true));

            log.info("H265 转码任务完成: taskId={}, videoItemId={}, newSize={}",
                    taskId, videoItemId, sizeBytes);
            // 发送转码完成通知
            notificationService.notifyOrLog(ownerUserId, "TASK_COMPLETED",
                    "视频转码完成", "H265 转码已完成",
                    Map.of("taskId", taskId.toString(), "videoItemId", videoItemId.toString()));
        } catch (BusinessException exception) {
            if (isLifecycleCancellation(exception)) {
                cancelForLifecycle(taskId, videoItemId, ownerUserId, derivedFileNodeId);
                return;
            }
            failH265Task(taskId, videoItemId, ownerUserId, exception);
        } catch (Exception e) {
            failH265Task(taskId, videoItemId, ownerUserId, e);
        } finally {
            if (transcodedFile != null) {
                try {
                    Files.deleteIfExists(transcodedFile);
                } catch (IOException ignored) {
                    log.debug("忽略: {}", ignored.getMessage());
                }
            }
        }
    }

    /**
     * 执行 AAC 音频轨道提取任务。
     *
     * @param taskId 任务 ID
     * @param videoItemId 源视频条目 ID
     * @param ownerUserId 所有者用户 ID
     * @param markTaskCompleted 是否标记任务完成
     */
    public void executeAudioTranscode(UUID taskId, UUID videoItemId, UUID ownerUserId, boolean markTaskCompleted) {
        log.info("音频提取任务开始: taskId={}, videoItemId={}, ownerUserId={}", taskId, videoItemId, ownerUserId);
        MediaVideoItem sourceItem = findActiveSource(taskId, videoItemId, ownerUserId);
        if (sourceItem == null) {
            return;
        }

        log.info("源视频信息: videoItemId={}, audioCodec={}, container={}, fileNodeId={}",
                videoItemId, sourceItem.getAudioCodec(), sourceItem.getContainerFormat(), sourceItem.getFileNodeId());

        // 检查是否已存在缓存版本
        Optional<MediaVideoItem> existing = videoItemRepository
                .findByOwnerUserIdAndSourceVideoItemIdAndVersionLabel(ownerUserId, videoItemId, "AUDIO_ONLY");
        if (existing.isPresent()) {
            log.info("音频缓存已存在，跳过: videoItemId={}, existingId={}", videoItemId, existing.get().getId());
            return;
        }

        Path transcodedFile = null;
        UUID derivedFileNodeId = null;
        try {
            // 阶段 1：仅提取音频轨道，文件处理不占用数据库事务。
            log.info("音频提取 Phase 1/3：开始 ffmpeg 提取音频: videoItemId={}", videoItemId);
            taskRecordService.updateProgress(taskId, 20);
            transcodedFile = videoTranscodeService.extractAudioToAac(
                    ownerUserId, sourceItem.getFileNodeId(), videoItemId);
            log.info("音频提取 Phase 1/3：ffmpeg 提取完成: videoItemId={}, size={}",
                    videoItemId, Files.size(transcodedFile));

            // 阶段 2：通过文件模块保存派生资产。
            log.info("音频提取 Phase 2/3：开始保存派生资产: videoItemId={}", videoItemId);
            taskRecordService.updateProgress(taskId, 50);
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, sourceItem.getFileNodeId());
            long sizeBytes = Files.size(transcodedFile);
            derivedFileNodeId = derivedAssetStorageService.store(
                    ownerUserId,
                    "VIDEO",
                    videoItemId,
                    "TRANSCODE",
                    sourceItem.getFileNodeId() + "_audio_only.aac",
                    "audio_only.aac",
                    "audio/aac",
                    transcodedFile
            );
            log.info("音频提取 Phase 2/3：派生资产保存完成: videoItemId={}, fileNodeId={}, sizeBytes={}",
                    videoItemId, derivedFileNodeId, sizeBytes);

            // 阶段 3：创建派生视频版本并更新任务状态。
            log.info("音频提取 Phase 3/3：开始持久化 DB 记录: videoItemId={}", videoItemId);
            taskRecordService.updateProgress(taskId, 80);
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, sourceItem.getFileNodeId());
            UUID persistedDerivedFileNodeId = derivedFileNodeId;
            transactionTemplate.executeWithoutResult(status ->
                    persistDerivedVersion(taskId, ownerUserId, sourceItem, persistedDerivedFileNodeId,
                            "AUDIO_ONLY", null,
                            "aac", "aac", markTaskCompleted));

            log.info("音频提取任务完成: taskId={}, videoItemId={}, sizeBytes={}", taskId, videoItemId, sizeBytes);
            // 发送音频提取完成通知
            notificationService.notifyOrLog(ownerUserId, "TASK_COMPLETED",
                    "音频提取完成", "视频音频轨已提取为 AAC",
                    Map.of("taskId", taskId.toString(), "videoItemId", videoItemId.toString()));
        } catch (BusinessException exception) {
            if (isLifecycleCancellation(exception)) {
                cancelForLifecycle(taskId, videoItemId, ownerUserId, derivedFileNodeId);
                return;
            }
            failAudioTask(taskId, videoItemId, ownerUserId, exception);
        } catch (Exception e) {
            failAudioTask(taskId, videoItemId, ownerUserId, e);
        } finally {
            if (transcodedFile != null) {
                try {
                    Files.deleteIfExists(transcodedFile);
                } catch (IOException ignored) {
                    log.debug("忽略: {}", ignored.getMessage());
                }
            }
        }
    }

    /**
     * 创建引用已落库派生文件的视频版本。
     */
    private void persistDerivedVersion(
            UUID taskId, UUID ownerUserId, MediaVideoItem sourceItem,
            UUID derivedFileNodeId, String versionLabel,
            String videoCodec, String audioCodec, String containerFormat,
            boolean markTaskCompleted
    ) {
        MediaVideoItem derivedItem = new MediaVideoItem();
        derivedItem.setOwnerUserId(ownerUserId);
        derivedItem.setFileNodeId(derivedFileNodeId);
        derivedItem.setMediaType(sourceItem.getMediaType());
        derivedItem.setSeriesId(sourceItem.getSeriesId());
        derivedItem.setSeasonId(sourceItem.getSeasonId());
        derivedItem.setSeasonNumber(sourceItem.getSeasonNumber());
        derivedItem.setEpisodeNumber(sourceItem.getEpisodeNumber());
        derivedItem.setMovieId(sourceItem.getMovieId());
        derivedItem.setEpisodeId(sourceItem.getEpisodeId());
        derivedItem.setVersionLabel(versionLabel);
        derivedItem.setDefaultVersion(false);
        derivedItem.setVideoCodec(videoCodec);
        derivedItem.setAudioCodec(audioCodec);
        derivedItem.setContainerFormat(containerFormat);
        derivedItem.setResolutionWidth(sourceItem.getResolutionWidth());
        derivedItem.setResolutionHeight(sourceItem.getResolutionHeight());
        derivedItem.setSourceVideoItemId(sourceItem.getId());
        derivedItem.setMetadataStatus(MetadataStatus.MATCHED.getValue());
        derivedItem.setScrapeLocked(true);
        MediaVideoItem savedDerived = videoItemRepository.save(derivedItem);
        syncEventService.record(
                ownerUserId,
                SyncScope.VIDEO,
                "VIDEO_ITEM",
                savedDerived.getId() == null ? null : savedDerived.getId().toString(),
                SyncAction.CREATED,
                savedDerived.getVersion(),
                Map.of("sourceVideoItemId", sourceItem.getId().toString())
        );

        if (markTaskCompleted) {
            taskRecordService.markCompleted(taskId, Map.of("status", "transcoded"));
        }
    }

    /**
     * Web 优化转码编排：将源视频转为 faststart MP4（moov atom 在文件头部）。
     * 浏览器可通过 HTTP range request 即时 seek，无需实时转码流。
     * 仅当源视频编码不兼容 Web 端时触发（容器非 mp4/webm，或音频为 DTS/AC3 等）。
     *
     * @param taskId 任务 ID
     * @param videoItemId 源视频条目 ID
     * @param ownerUserId 所有者用户 ID
     * @param markTaskCompleted 是否标记任务完成
     */
    public void executeWebOptimize(UUID taskId, UUID videoItemId, UUID ownerUserId, boolean markTaskCompleted) {
        log.info("Web 优化转码开始: taskId={}, videoItemId={}, ownerUserId={}", taskId, videoItemId, ownerUserId);
        MediaVideoItem sourceItem = findActiveSource(taskId, videoItemId, ownerUserId);
        if (sourceItem == null) {
            return;
        }

        // 检查是否已存在 Web 优化版本
        Optional<MediaVideoItem> existing = videoItemRepository
                .findByOwnerUserIdAndSourceVideoItemIdAndVersionLabel(ownerUserId, videoItemId, "WEB_OPTIMIZED");
        if (existing.isPresent()) {
            log.info("Web 优化版本已存在，跳过: videoItemId={}, existingId={}", videoItemId, existing.get().getId());
            if (markTaskCompleted) {
                taskRecordService.markCompleted(taskId, Map.of("status", "skipped", "reason", "already exists"));
            }
            return;
        }

        Path transcodedFile = null;
        UUID derivedFileNodeId = null;
        try {
            // 阶段 1：Docker 转码不占用数据库事务。
            log.info("Web 优化 Phase 1/3：开始 ffmpeg 转码: videoItemId={}, videoCodec={}",
                    videoItemId, sourceItem.getVideoCodec());
            taskRecordService.updateProgress(taskId, 20);
            transcodedFile = videoTranscodeService.transcodeToWebOptimized(
                    ownerUserId, sourceItem.getFileNodeId(), videoItemId, sourceItem.getVideoCodec());
            log.info("Web 优化 Phase 1/3：ffmpeg 转码完成: videoItemId={}, size={}",
                    videoItemId, Files.size(transcodedFile));

            // 阶段 2：通过文件模块保存派生资产。
            log.info("Web 优化 Phase 2/3：开始保存派生资产: videoItemId={}", videoItemId);
            taskRecordService.updateProgress(taskId, 50);
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, sourceItem.getFileNodeId());
            long sizeBytes = Files.size(transcodedFile);
            derivedFileNodeId = derivedAssetStorageService.store(
                    ownerUserId,
                    "VIDEO",
                    videoItemId,
                    "TRANSCODE",
                    sourceItem.getFileNodeId() + "_web_optimized.mp4",
                    "web_optimized.mp4",
                    "video/mp4",
                    transcodedFile
            );
            log.info("Web 优化 Phase 2/3：派生资产保存完成: videoItemId={}, fileNodeId={}, sizeBytes={}",
                    videoItemId, derivedFileNodeId, sizeBytes);

            // 阶段 3：创建派生视频版本并更新任务状态。
            log.info("Web 优化 Phase 3/3：开始持久化 DB 记录: videoItemId={}", videoItemId);
            taskRecordService.updateProgress(taskId, 80);
            // 视频编码：H264/H265 时 copy 保持原编码，否则转为 H264（libx264）
            String outputVideoCodec = isWebNativeCodec(sourceItem.getVideoCodec())
                    ? sourceItem.getVideoCodec()
                    : "h264";
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, sourceItem.getFileNodeId());
            UUID persistedDerivedFileNodeId = derivedFileNodeId;
            transactionTemplate.executeWithoutResult(status ->
                    persistDerivedVersion(taskId, ownerUserId, sourceItem, persistedDerivedFileNodeId,
                            "WEB_OPTIMIZED",
                            outputVideoCodec, "aac", "mp4", markTaskCompleted));

            log.info("Web 优化转码完成: taskId={}, videoItemId={}, sizeBytes={}", taskId, videoItemId, sizeBytes);
        } catch (BusinessException exception) {
            if (isLifecycleCancellation(exception)) {
                cancelForLifecycle(taskId, videoItemId, ownerUserId, derivedFileNodeId);
                return;
            }
            failWebOptimizeTask(taskId, videoItemId, exception);
        } catch (Exception e) {
            failWebOptimizeTask(taskId, videoItemId, e);
        } finally {
            if (transcodedFile != null) {
                try {
                    Files.deleteIfExists(transcodedFile);
                } catch (IOException ignored) {
                    log.debug("忽略: {}", ignored.getMessage());
                }
            }
        }
    }

    private boolean isWebNativeCodec(String videoCodec) {
        if (videoCodec == null) {
            return false;
        }
        String normalized = videoCodec.trim().toLowerCase(Locale.ROOT);
        return normalized.equals("h264") || normalized.equals("avc")
                || normalized.equals("hevc") || normalized.equals("h265");
    }

    private MediaVideoItem findActiveSource(UUID taskId, UUID videoItemId, UUID ownerUserId) {
        MediaVideoItem sourceItem = videoItemRepository.findByIdAndOwnerUserId(videoItemId, ownerUserId)
                .orElse(null);
        if (sourceItem == null) {
            taskRecordService.markCancelled(taskId);
            log.info("源视频条目已删除，取消转码任务: taskId={}, videoItemId={}", taskId, videoItemId);
            return null;
        }
        try {
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, sourceItem.getFileNodeId());
            return sourceItem;
        } catch (BusinessException exception) {
            if (!isLifecycleCancellation(exception)) {
                throw exception;
            }
            taskRecordService.markCancelled(taskId);
            log.info("源视频已删除或正在永久删除，取消转码任务: taskId={}, videoItemId={}", taskId, videoItemId);
            return null;
        }
    }

    private boolean isLifecycleCancellation(BusinessException exception) {
        return ErrorCode.FILE_LIFECYCLE_CONFLICT.equals(exception.errorCode())
                || ErrorCode.FILE_NOT_FOUND.equals(exception.errorCode());
    }

    private void cancelForLifecycle(
            UUID taskId,
            UUID videoItemId,
            UUID ownerUserId,
        UUID derivedFileNodeId
    ) {
        if (derivedFileNodeId != null) {
            try {
                derivedAssetStorageService.deleteOwned(ownerUserId, derivedFileNodeId);
            } catch (RuntimeException exception) {
                log.warn("取消转码任务时清理派生文件失败: taskId={}, fileNodeId={}",
                        taskId, derivedFileNodeId, exception);
            }
        }
        taskRecordService.markCancelled(taskId);
        log.info("源视频已删除或正在永久删除，取消转码任务: taskId={}, videoItemId={}", taskId, videoItemId);
    }

    private void failH265Task(UUID taskId, UUID videoItemId, UUID ownerUserId, Exception exception) {
        log.error("H265 转码任务失败: taskId={}, videoItemId={}", taskId, videoItemId, exception);
        taskRecordService.markFailed(taskId, exception.getMessage(), ThrowableDescriber.describe(exception));
        notificationService.notifyOrLog(ownerUserId, "TASK_FAILED",
                "视频转码失败", "转码失败: " + exception.getMessage(),
                Map.of("taskId", taskId.toString(), "videoItemId", videoItemId.toString()));
    }

    private void failAudioTask(UUID taskId, UUID videoItemId, UUID ownerUserId, Exception exception) {
        log.error("音频转码任务失败: taskId={}, videoItemId={}", taskId, videoItemId, exception);
        taskRecordService.markFailed(taskId, exception.getMessage(), ThrowableDescriber.describe(exception));
        notificationService.notifyOrLog(ownerUserId, "TASK_FAILED",
                "音频提取失败", "音频提取失败: " + exception.getMessage(),
                Map.of("taskId", taskId.toString(), "videoItemId", videoItemId.toString()));
    }

    private void failWebOptimizeTask(UUID taskId, UUID videoItemId, Exception exception) {
        log.error("Web 优化转码失败: taskId={}, videoItemId={}", taskId, videoItemId, exception);
        taskRecordService.markFailed(taskId, exception.getMessage(), ThrowableDescriber.describe(exception));
    }
}
