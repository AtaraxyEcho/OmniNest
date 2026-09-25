package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.domain.MediaPlaybackProgress;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;
import com.omninest.modules.media.service.MediaPlaybackProgressService;
import com.omninest.modules.video.domain.MediaSubtitleTrack;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.domain.MediaWatchHistory;
import com.omninest.modules.video.dto.MovieDtos.PlaybackPlanDto;
import com.omninest.modules.video.dto.MovieDtos.PlaybackProgressRequest;
import com.omninest.modules.video.dto.MovieDtos.PlaybackSubtitleDto;
import com.omninest.modules.video.repository.MediaSubtitleTrackRepository;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.MediaWatchHistoryRepository;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 影视播放计划、进度与字幕内容服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MoviePlaybackService {


    private final MediaVideoItemRepository videoItemRepository;
    private final MediaMovieRepository movieRepository;
    private final MediaTvEpisodeRepository episodeRepository;
    private final MediaPlaybackProgressService progressService;
    private final MediaSubtitleTrackRepository subtitleTrackRepository;
    private final FileQueryService fileQueryService;
    private final MediaWatchHistoryRepository historyRepository;
    private final MovieTaskService movieTaskService;
    private final MediaProcessingLimitsProperties processingLimits;
    private final MediaRuntimeConfigService mediaRuntimeConfigService;
    private final PlatformTransactionManager transactionManager;
    private final VideoTranscodeService videoTranscodeService;
    private final MediaContentAccessService mediaContentAccessService;
    private final MediaPlaybackTokenService mediaPlaybackTokenService;

    public PlaybackPlanDto playbackPlan(UUID ownerUserId, UUID videoItemId) {
        // 查询在只读事务中执行
        TransactionTemplate readOnlyTx = new TransactionTemplate(transactionManager);
        readOnlyTx.setReadOnly(true);
        readOnlyTx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRED);
        PlaybackPlanDto plan = readOnlyTx.execute(status -> {
            MediaVideoItem item = findVideo(ownerUserId, videoItemId);
            MediaPlaybackProgress progress = progressService
                    .find(ownerUserId, MediaPlaybackType.VIDEO, videoItemId.toString())
                    .orElse(null);
            return buildPlaybackPlan(ownerUserId, item, progress);
        });
        // 自动触发在独立的写事务中执行，避免 readOnly 事务冲突
        TransactionTemplate writeTx = new TransactionTemplate(transactionManager);
        writeTx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        writeTx.executeWithoutResult(status ->
                autoTriggerAudioTranscode(ownerUserId, plan));
        return plan;
    }

    private PlaybackPlanDto buildPlaybackPlan(UUID ownerUserId, MediaVideoItem item, MediaPlaybackProgress progress) {
        String container = item.getContainerFormat();
        String videoCodec = item.getVideoCodec();
        String audioCodec = item.getAudioCodec();
        String mode = playbackMode(container, videoCodec, audioCodec);

        UUID catalogOwnerId = item.getOwnerUserId();
        MediaPlaybackTokenService.IssuedMediaToken mediaToken = mediaPlaybackTokenService.issue(
                ownerUserId,
                item.getId()
        );
        FileDownloadUrlDto downloadUrl = item.getLibrarySourceId() == null
                ? fileQueryService.createDownloadUrl(catalogOwnerId, item.getFileNodeId())
                : new FileDownloadUrlDto(
                        item.getFileNodeId(),
                        null,
                        "/api/v1/public/video/items/" + item.getId() + "/content?token=" + mediaToken.token(),
                        mediaToken.expiresAt()
                );
        String streamUrl = null;
        boolean hasAudioCache = false;

        if ("TRANSCODE_REQUIRED".equals(mode)) {
            // 检查是否有已缓存的 AAC 音频（仅音频转码，视频流 copy）
            MediaVideoItem audioCached = videoItemRepository
                    .findByOwnerUserIdAndSourceVideoItemIdAndVersionLabel(catalogOwnerId, item.getId(), "AUDIO_ONLY")
                    .orElse(null);
            hasAudioCache = audioCached != null;
            streamUrl = "/api/v1/public/video/items/" + item.getId() + "/stream?token=" + mediaToken.token();
        }

        log.info("播放计划: videoItemId={}, container={}, videoCodec={}, audioCodec={}, mode={}, hasAudioCache={}",
                item.getId(), container, videoCodec, audioCodec, mode, hasAudioCache);

        List<PlaybackSubtitleDto> subtitles = subtitleTrackRepository
                .findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(catalogOwnerId, item.getId())
                .stream()
                .map(track -> toSubtitleDto(item.getId(), mediaToken.token(), track))
                .toList();
        long safeDur = safeDuration(item);
        long progressDur = progress == null ? 0 : progress.getDurationSeconds();
        return new PlaybackPlanDto(
                item.getId(),
                mode,
                downloadUrl.downloadUrl(),
                downloadUrl.expiresAt(),
                progress == null ? 0 : progress.getPositionSeconds(),
                Math.max(safeDur, progressDur),
                container,
                videoCodec,
                audioCodec,
                subtitles,
                streamUrl,
                hasAudioCache
        );
    }

    @Transactional(rollbackFor = Exception.class)
    public PlaybackPlanDto updateProgress(UUID ownerUserId, UUID videoItemId, PlaybackProgressRequest request) {
        MediaVideoItem item = findVideo(ownerUserId, videoItemId);
        long duration = request.durationSeconds() > 0 ? request.durationSeconds() : safeDuration(item);
        long position = Math.max(0, request.positionSeconds());
        MediaPlaybackProgress progress = progressService.save(
                ownerUserId,
                MediaPlaybackType.VIDEO,
                videoItemId.toString(),
                position,
                duration,
                request.completed(),
                request.clientUpdatedAt(),
                request.deviceId()
        );
        historyRepository.save(upsertHistory(ownerUserId, videoItemId, progress));
        // 复用已加载的 item，避免重复查询
        return buildPlaybackPlan(ownerUserId, item, progress);
    }

    private MediaWatchHistory upsertHistory(UUID ownerUserId, UUID videoItemId, MediaPlaybackProgress progress) {
        MediaWatchHistory history = historyRepository
                .findFirstByOwnerUserIdAndVideoItemIdOrderByPlayedAtDesc(ownerUserId, videoItemId)
                .orElseGet(MediaWatchHistory::new);
        history.setOwnerUserId(ownerUserId);
        history.setVideoItemId(videoItemId);
        history.setPositionSeconds(progress.getPositionSeconds());
        history.setDurationSeconds(progress.getDurationSeconds());
        history.setCompleted(progress.isCompleted());
        return history;
    }

    private MediaVideoItem findVideo(UUID ownerUserId, UUID videoItemId) {
        return mediaContentAccessService.requireReadableVideo(ownerUserId, videoItemId);
    }

    private PlaybackSubtitleDto toSubtitleDto(UUID videoItemId, String token, MediaSubtitleTrack track) {
        String url = "/api/v1/public/video/items/" + videoItemId
                + "/subtitles/" + track.getId() + "?token=" + token;
        return new PlaybackSubtitleDto(
                track.getId(),
                track.getLanguage(),
                track.getLabel(),
                track.getTrackKind(),
                url,
                track.getStreamIndex()
        );
    }

    /** 使用媒体短期令牌流式写出字幕，且每次请求重新校验媒体库授权。 */
    @Transactional(readOnly = true)
    public void writeSubtitleContentByToken(String token, UUID videoItemId, UUID subtitleId, java.io.OutputStream out)
            throws java.io.IOException {
        MediaPlaybackTokenService.MediaGrant grant = mediaPlaybackTokenService.requireGrant(token, videoItemId);
        MediaSubtitleTrack track = subtitleTrackRepository.findById(subtitleId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "字幕轨道不存在"));
        if (!videoItemId.equals(track.getVideoItemId())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "媒体令牌不能访问其他影片的字幕");
        }
        writeSubtitleContent(grant.requesterUserId(), subtitleId, out);
    }

    /**
     * 流式写出字幕文件内容。
     * 外挂字幕：从 File 模块受控内容流拷贝（SRT/ASS/VTT）。
     * 内嵌字幕：从 File 读取探测时提取的 WebVTT；若未提取则实时提取。
     */
    @Transactional(readOnly = true)
    public void writeSubtitleContent(UUID ownerUserId, UUID subtitleId, java.io.OutputStream out)
            throws java.io.IOException {
        MediaSubtitleTrack track = subtitleTrackRepository.findById(subtitleId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "字幕轨道不存在"));
        MediaVideoItem item = mediaContentAccessService.requireReadableVideo(ownerUserId, track.getVideoItemId());
        UUID catalogOwnerId = item.getOwnerUserId();
        try {
            if (track.getFileNodeId() != null) {
                try (FileContentStream content = fileQueryService.openOwnedFileContent(
                        catalogOwnerId,
                        track.getFileNodeId()
                )) {
                    if (content.sizeBytes() > processingLimits.getMaxSubtitleBytes()) {
                        throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "字幕文件超过大小限制");
                    }
                    content.inputStream().transferTo(out);
                }
            } else if (track.getStreamIndex() != null) {
                Path vttFile = videoTranscodeService.extractSubtitleToWebVtt(
                        catalogOwnerId, item.getFileNodeId(), item.getId(), track.getStreamIndex());
                try {
                    if (Files.size(vttFile) > processingLimits.getMaxSubtitleBytes()) {
                        throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "字幕文件超过大小限制");
                    }
                    Files.copy(vttFile, out);
                } finally {
                    Files.deleteIfExists(vttFile);
                }
            } else {
                throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "字幕轨道无可用内容");
            }
        } catch (BusinessException e) {
            throw e;
        } catch (java.io.IOException e) {
            throw e;
        } catch (Exception e) {
            throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "字幕内容读取失败: " + e.getMessage());
        }
    }

    private long safeDuration(MediaVideoItem item) {
        // 优先使用元数据时长（TMDB 等来源）
        if (item.getMovieId() != null) {
            long movieDur = movieRepository.findById(item.getMovieId())
                    .map(m -> m.getRuntimeSeconds() == null ? 0L : (long) m.getRuntimeSeconds())
                    .orElse(0L);
            if (movieDur > 0) return movieDur;
        }
        if (item.getEpisodeId() != null) {
            long episodeDur = episodeRepository.findById(item.getEpisodeId())
                    .map(e -> e.getRuntimeSeconds() == null ? 0L : (long) e.getRuntimeSeconds())
                    .orElse(0L);
            if (episodeDur > 0) return episodeDur;
        }
        // 回退到 ffprobe 探测的视频文件时长
        return item.getDurationSeconds() == null ? 0L : item.getDurationSeconds().longValue();
    }

    private String playbackMode(String container, String videoCodec, String audioCodec) {
        String normalizedContainer = normalize(container);
        String normalizedVideo = normalize(videoCodec);
        String normalizedAudio = normalize(audioCodec);
        // WebM 本是 Matroska 子集：Chrome/Edge 的解复用器可直接播放
        // matroska 容器中的 av1/vp9/vp8 + opus/vorbis 轨道（按 video/webm 提供）。
        // 此前仅因容器名 MATROSKA 落入转码流，Seek 精度受限（D-007）。
        boolean webmFamily = normalizedContainer != null
                && (normalizedContainer.contains("webm") || normalizedContainer.contains("matroska"));
        boolean webmVideo = normalizedVideo != null
                && (normalizedVideo.equals("av1")
                        || normalizedVideo.equals("vp9")
                        || normalizedVideo.equals("vp8"));
        boolean webmAudio = normalizedAudio == null
                || normalizedAudio.equals("opus")
                || normalizedAudio.equals("vorbis");
        if (webmFamily && webmVideo && webmAudio) {
            return "DIRECT_PLAY";
        }
        boolean directContainer = normalizedContainer == null
                || normalizedContainer.equals("mp4")
                || normalizedContainer.equals("m4v")
                || normalizedContainer.equals("webm");
        // hevc/h265: Chrome 107+ 支持硬件解码（需 GPU + 硬件加速），Safari 原生支持
        boolean directVideo = normalizedVideo == null
                || normalizedVideo.equals("h264")
                || normalizedVideo.equals("avc")
                || normalizedVideo.equals("hevc")
                || normalizedVideo.equals("h265")
                || normalizedVideo.equals("vp9")
                || normalizedVideo.equals("av1");
        boolean directAudio = normalizedAudio == null
                || normalizedAudio.equals("aac")
                || normalizedAudio.equals("mp3")
                || normalizedAudio.equals("opus");
        return directContainer && directVideo && directAudio ? "DIRECT_PLAY" : "TRANSCODE_REQUIRED";
    }

    private String normalize(String value) {
        return value == null ? null : value.trim().toLowerCase(Locale.ROOT);
    }

    /**
     * 首次播放时自动触发音频转码后台任务（仅提取 AAC 音频轨道）。
     * 条件：源视频需要转码（TRANSCODE_REQUIRED）+ 无 AUDIO_ONLY 缓存版本。
     * 仅转音频（~35MB），视频流播放时从原始文件 copy，不额外占用存储。
     * 在独立写事务中执行，与 playbackPlan 的只读事务隔离。
     */
    private void autoTriggerAudioTranscode(UUID ownerUserId, PlaybackPlanDto plan) {
        if (!mediaRuntimeConfigService.transcodeEnabled()) {
            return;
        }
        if (!"TRANSCODE_REQUIRED".equals(plan.mode())) {
            return;
        }
        UUID videoItemId = plan.videoItemId();
        MediaVideoItem item = mediaContentAccessService.requireReadableVideo(ownerUserId, videoItemId);
        UUID catalogOwnerId = item.getOwnerUserId();
        boolean hasAudioCache = videoItemRepository
                .findByOwnerUserIdAndSourceVideoItemIdAndVersionLabel(catalogOwnerId, videoItemId, "AUDIO_ONLY")
                .isPresent();
        if (hasAudioCache) {
            return;
        }
        try {
            movieTaskService.createTranscodeTask(ownerUserId, videoItemId, true);
            log.info("自动触发音频转码: videoItemId={}", videoItemId);
        } catch (Exception e) {
            log.debug("自动触发音频转码失败（可能已存在任务）: videoItemId={}, message={}",
                    videoItemId, e.getMessage());
        }
    }
}
