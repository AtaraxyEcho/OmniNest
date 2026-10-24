package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileProbeSourceService;
import com.omninest.modules.file.service.MediaProbeSourceStager;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaSubtitleTrack;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.domain.TrackKind;
import com.omninest.modules.video.event.VideoProbeEvent;
import com.omninest.modules.video.event.VideoSubtitleExtractEvent;
import com.omninest.modules.video.repository.MediaSubtitleTrackRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.common.json.JsonSupport;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.Semaphore;
import tools.jackson.databind.JsonNode;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 视频媒体信息探测与内嵌字幕提取服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class VideoProbeService {
    private static final Duration COMMAND_CHECK_TIMEOUT = Duration.ofSeconds(30);
    private static final Duration PROBE_TIMEOUT = Duration.ofSeconds(60);
    /** 同一时刻允许并行的 ffprobe 进程上限。 */
    private static final int MAX_CONCURRENT_PROBES = 2;
    /** 同一时刻允许并行提取的字幕 ffmpeg 进程上限。 */
    private static final int MAX_CONCURRENT_SUBTITLE_EXTRACTS = 2;

    private final FileProbeSourceService fileProbeSourceService;
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaSubtitleTrackRepository subtitleTrackRepository;
    private final TaskRecordService taskRecordService;
    private final MovieTaskService movieTaskService;
    private final MediaRuntimeConfigService mediaRuntimeConfigService;
    private final VideoTranscodeService videoTranscodeService;
    private final VideoProcessExecutor processExecutor;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final PlatformTransactionManager transactionManager;
    private final ApplicationEventPublisher applicationEventPublisher;
    private final MediaLibraryAccessService mediaLibraryAccessService;

    /**
     * 字幕提取槽位。
     *
     * <p>每路内嵌字幕都要在 ffmpeg 容器里做一遍 demux（上限 180 分钟），无上限时
     * 并发探测多个视频会同时拉起多路容器进程打满宿主机。取不到槽位即跳过该轨道，
     * 由下一次探测重试，而不是让既有提取一起阻塞。</p>
     */
    private final Semaphore subtitleExtractSlots = new Semaphore(MAX_CONCURRENT_SUBTITLE_EXTRACTS);

    /**
     * ffprobe 子进程槽位：媒体异步执行器改为虚拟线程后，不能让它同时拉起过多探测进程。
     * 取不到槽位时放弃本次探测，由后续任务重试。
     */
    private final Semaphore probeSlots = new Semaphore(MAX_CONCURRENT_PROBES);

    private volatile boolean probeAvailable = true;

    @PostConstruct
    void checkFfprobe() {
        if (tryCommand("ffprobe", "-version")) {
            probeAvailable = true;
            log.info("ffprobe 可用（本地），视频探测功能已启用");
            return;
        }
        probeAvailable = false;
        log.warn("ffprobe 不可用，视频探测功能已禁用。请在后端镜像安装 ffmpeg。");
    }

    private boolean tryCommand(String... command) {
        try {
            VideoProcessExecutor.Result result = processExecutor.execute(
                    List.of(command),
                    COMMAND_CHECK_TIMEOUT
            );
            return result.succeeded();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        } catch (IOException e) {
            return false;
        }
    }

    @Async("mediaAsyncExecutor")
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onScrapeComplete(VideoProbeEvent event) {
        if (!probeAvailable) {
            return;
        }
        try {
            probe(event.item());
            // 探测完成后，将内嵌字幕提取为 WebVTT 并存储到 MinIO
            extractEmbeddedSubtitles(event.item());
        } catch (Exception e) {
            log.warn("视频探测失败: itemId={}", event.item().getId(), e);
        }
    }

    /**
     * 请求线程外的字幕提取入口：由 {@link #probeByVideoItemId} 发布事件触发，
     * 复用 mediaAsyncExecutor 异步执行；无活动事务时 fallbackExecution 立即投递。
     */
    @Async("mediaAsyncExecutor")
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT, fallbackExecution = true)
    public void onSubtitleExtractRequest(VideoSubtitleExtractEvent event) {
        try {
            extractEmbeddedSubtitles(event.item());
        } catch (Exception e) {
            log.warn("异步字幕提取失败: itemId={}", event.item().getId(), e);
        }
    }

    public void probeByVideoItemId(UUID ownerUserId, UUID videoItemId) {
        MediaVideoItem item = videoItemRepository.findById(videoItemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "视频条目不存在: " + videoItemId));
        // 媒体库条目的 owner 是扫描执行者：其他管理员探测同一库来源时不能 404，
        // 但跨所有者操作只放行 MEDIA_LIBRARY_MANAGE，不退回可读权限。
        if (!item.getOwnerUserId().equals(ownerUserId)) {
            if (item.getLibrarySourceId() == null) {
                throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "视频条目不存在: " + videoItemId);
            }
            try {
                mediaLibraryAccessService.requireManage(ownerUserId, item.getLibrarySourceId());
            } catch (BusinessException exception) {
                throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "视频条目不存在: " + videoItemId);
            }
        }
        probe(item);
        // 每路字幕提取都要在容器内跑一遍 ffmpeg demux（上限 180 分钟且无 Range 支持），
        // 不得占用请求线程；轻量 ffprobe 保持同步，提取经既有 @Async + AFTER_COMMIT
        // 机制发布事件在提交后异步执行。
        applicationEventPublisher.publishEvent(new VideoSubtitleExtractEvent(item));
    }

    public void probe(MediaVideoItem item) {
        if (!probeAvailable) {
            return;
        }
        UUID ownerUserId = item.getOwnerUserId();
        UUID fileNodeId = item.getFileNodeId();
        if (!probeSlots.tryAcquire()) {
            log.warn("ffprobe 并发已达上限，跳过本次探测: itemId={}, limit={}",
                    item.getId(), MAX_CONCURRENT_PROBES);
            return;
        }
        try {
            // 首尾窗口暂存与 ffprobe 均为 I/O 或 CPU 密集段，置于事务之外，避免独占数据库连接。
            JsonNode probeResult;
            boolean widerTailCouldHelp;
            Optional<MediaProbeSourceStager.StagedSource> staged =
                    fileProbeSourceService.stageOwned(ownerUserId, fileNodeId);
            if (staged.isEmpty()) {
                log.warn("视频探测输入暂存失败: itemId={}, fileNodeId={}", item.getId(), fileNodeId);
                return;
            }
            try (MediaProbeSourceStager.StagedSource source = staged.get()) {
                probeResult = runFfprobe(source.path());
                widerTailCouldHelp = source.widerTailCouldHelp();
            }
            if (probeResult == null && widerTailCouldHelp) {
                // 默认尾窗装不下索引时只放长一次尾窗；两次都读不到才算该内容没有元数据。
                Optional<MediaProbeSourceStager.StagedSource> wide = fileProbeSourceService.stageOwned(
                        ownerUserId,
                        fileNodeId,
                        MediaProbeSourceStager.ESCALATED_TAIL_BYTES
                );
                if (wide.isPresent()) {
                    try (MediaProbeSourceStager.StagedSource source = wide.get()) {
                        probeResult = runFfprobe(source.path());
                    }
                }
            }
            if (probeResult == null) {
                // 两次窗口都读不到索引时做最后一次整文件兜底（有大小上限）。
                Optional<MediaProbeSourceStager.StagedSource> full =
                        fileProbeSourceService.stageOwnedFull(ownerUserId, fileNodeId);
                if (full.isPresent()) {
                    try (MediaProbeSourceStager.StagedSource source = full.get()) {
                        probeResult = runFfprobe(source.path());
                    }
                }
            }
            if (probeResult == null) {
                return;
            }
            // 仅结果落库置于独立事务内。
            JsonNode result = probeResult;
            TransactionTemplate writeTx = new TransactionTemplate(transactionManager);
            writeTx.executeWithoutResult(status -> {
                applyProbeResult(item, result);
                videoItemRepository.save(item);
                triggerAudioExtractIfNeeded(item);
            });
            log.info("视频探测完成: itemId={}, videoCodec={}, audioCodec={}, resolution={}x{}",
                    item.getId(), item.getVideoCodec(), item.getAudioCodec(),
                    item.getResolutionWidth(), item.getResolutionHeight());
        } catch (Exception e) {
            log.warn("视频探测处理异常: itemId={}", item.getId(), e);
        } finally {
            probeSlots.release();
        }
    }

    /**
     * 探测完成后立即检查音频兼容性，不兼容则自动触发 AAC 提取任务。
     * 避免等到用户首次播放时才实时转码。
     * 使用 REQUIRES_NEW 独立事务，避免任务创建失败导致探测结果回滚。
     */
    private void triggerAudioExtractIfNeeded(MediaVideoItem item) {
        String audioCodec = item.getAudioCodec();
        if (audioCodec == null) {
            return;
        }
        String normalized = audioCodec.trim().toLowerCase(Locale.ROOT);
        if (!VideoStreamService.WEB_UNSUPPORTED_AUDIO.contains(normalized)) {
            return;
        }
        UUID ownerUserId = item.getOwnerUserId();
        UUID videoItemId = item.getId();
        // 保底去重：已有 AUDIO_ONLY 缓存则跳过
        boolean hasCached = videoItemRepository
                .findByOwnerUserIdAndSourceVideoItemIdAndVersionLabel(
                        ownerUserId, videoItemId, "AUDIO_ONLY")
                .isPresent();
        if (hasCached) {
            return;
        }
        // 保底去重：已有进行中的提取任务则跳过
        if (taskRecordService.hasActiveTaskByPayload(
                ownerUserId,
                "AUDIO_EXTRACT",
                "videoItemId",
                videoItemId.toString(),
                List.of(TaskStatus.QUEUED.getValue(), TaskStatus.RUNNING.getValue()))) {
            return;
        }
        if (!mediaRuntimeConfigService.transcodeEnabled()) {
            return;
        }
        // 独立写事务：任务创建失败不影响探测结果
        TransactionTemplate writeTx = new TransactionTemplate(transactionManager);
        writeTx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        try {
            writeTx.executeWithoutResult(status -> {
                movieTaskService.createTranscodeTask(ownerUserId, videoItemId, true);
            });
            log.info("探测后自动触发音频提取: videoItemId={}, audioCodec={}", videoItemId, audioCodec);
        } catch (Exception e) {
            log.debug("探测后触发音频提取失败（可能已存在任务）: videoItemId={}, message={}",
                    videoItemId, e.getMessage());
        }
    }

    /**
     * 探测完成后，将内嵌字幕提取为 WebVTT 并存储到 MinIO。
     * 提取后的字幕作为外挂文件使用，前端可直接通过 URL 加载。
     * 仅处理有 streamIndex 且无 fileNodeId 的内嵌字幕轨道。
     */
    private void extractEmbeddedSubtitles(MediaVideoItem item) {
        UUID ownerUserId = item.getOwnerUserId();
        UUID videoItemId = item.getId();
        List<MediaSubtitleTrack> tracks = subtitleTrackRepository
                .findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(ownerUserId, videoItemId);
        List<MediaSubtitleTrack> pending = tracks.stream()
                .filter(track -> track.getStreamIndex() != null && track.getFileNodeId() == null)
                .toList();
        if (pending.isEmpty()) {
            return;
        }
        if (!subtitleExtractSlots.tryAcquire()) {
            log.warn("字幕提取并发已达上限，跳过本次提取待下次探测重试: videoItemId={}, limit={}",
                    videoItemId, MAX_CONCURRENT_SUBTITLE_EXTRACTS);
            return;
        }
        try {
            // 一次暂存覆盖所有轨道，避免 N 条字幕把整部影片重复下载 N 次。
            Map<Integer, Path> extractedByIndex = new HashMap<>();
            for (VideoTranscodeService.ExtractedSubtitle extracted : videoTranscodeService
                    .extractSubtitlesToWebVtt(
                            ownerUserId,
                            item.getFileNodeId(),
                            videoItemId,
                            pending.stream().map(MediaSubtitleTrack::getStreamIndex).toList()
                    )) {
                extractedByIndex.put(extracted.streamIndex(), extracted.file());
            }
            for (MediaSubtitleTrack track : pending) {
                Path vttFile = extractedByIndex.get(track.getStreamIndex());
                if (vttFile == null) {
                    continue;
                }
                try {
                    storeExtractedSubtitle(item, track, vttFile);
                } finally {
                    deleteQuietly(vttFile);
                }
            }
        } finally {
            subtitleExtractSlots.release();
        }
    }

    /**
     * 把已提取的字幕落库并更新字幕轨道引用。
     */
    private void storeExtractedSubtitle(MediaVideoItem item, MediaSubtitleTrack track, Path vttFile) {
        UUID ownerUserId = item.getOwnerUserId();
        UUID videoItemId = item.getId();
        int streamIndex = track.getStreamIndex();
        try {
            long sizeBytes = Files.size(vttFile);
            UUID subtitleFileId = derivedAssetStorageService.store(
                    ownerUserId,
                    "VIDEO",
                    videoItemId,
                    "SUBTITLES",
                    streamIndex + ".vtt",
                    "text/vtt",
                    vttFile
            );

            // 文件资产独立落库后，在短事务中更新字幕轨道引用。
            TransactionTemplate writeTx = new TransactionTemplate(transactionManager);
            writeTx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
            writeTx.executeWithoutResult(status -> {
                track.setFileNodeId(subtitleFileId);
                track.setTrackKind("EXTERNAL");
                if (track.getLabel() != null && !track.getLabel().contains("[提取]")) {
                    track.setLabel(track.getLabel() + " [提取]");
                }
                subtitleTrackRepository.save(track);
            });

            log.info("字幕提取完成: videoItemId={}, streamIndex={}, sizeBytes={}",
                    videoItemId, streamIndex, sizeBytes);
        } catch (Exception e) {
            log.warn("字幕存储失败: videoItemId={}, streamIndex={}, message={}",
                    videoItemId, streamIndex, e.getMessage());
        }
    }

    private void deleteQuietly(Path file) {
        try {
            Files.deleteIfExists(file);
        } catch (IOException ignored) {
            log.debug("忽略: {}", ignored.getMessage());
        }
    }

    private JsonNode runFfprobe(Path file) {
        try {
            VideoProcessExecutor.Result result = processExecutor.execute(List.of(
                    "ffprobe",
                    "-v", "quiet",
                    "-protocol_whitelist", "file,crypto,data",
                    "-print_format", "json",
                    "-show_format",
                    "-show_streams",
                    file.toAbsolutePath().toString()
            ), PROBE_TIMEOUT);
            if (result.timedOut()) {
                log.warn("ffprobe 超时");
                return null;
            }
            if (!result.succeeded()) {
                log.warn("ffprobe 退出码异常: exitCode={}", result.exitCode());
                return null;
            }
            return JsonSupport.readTree(result.output());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("ffprobe 执行被中断");
            return null;
        } catch (IOException e) {
            log.warn("ffprobe 执行失败", e);
            return null;
        }
    }

    private void applyProbeResult(MediaVideoItem item, JsonNode probeResult) {
        JsonNode streams = probeResult.path("streams");
        if (!streams.isArray()) {
            return;
        }
        List<MediaSubtitleTrack> embeddedSubtitles = new ArrayList<>();

        for (int i = 0; i < streams.size(); i++) {
            JsonNode stream = streams.get(i);
            String codecType = stream.path("codec_type").asString(null);
            if ("video".equals(codecType)) {
                applyVideoStream(item, stream);
            } else if ("audio".equals(codecType)) {
                applyAudioStream(item, stream);
            } else if ("subtitle".equals(codecType)) {
                MediaSubtitleTrack track = buildEmbeddedSubtitle(item, stream, i);
                if (track != null) {
                    embeddedSubtitles.add(track);
                }
            }
        }
        JsonNode format = probeResult.path("format");
        if (format.isObject()) {
            String formatName = format.path("format_name").asString(null);
            if (formatName != null && !formatName.isBlank()) {
                item.setContainerFormat(formatName);
            }
            // 提取视频总时长（秒），ffprobe 返回浮点字符串如 "7200.123456"
            String durationStr = format.path("duration").asString(null);
            if (durationStr != null && !durationStr.isBlank()) {
                try {
                    item.setDurationSeconds((int) Double.parseDouble(durationStr));
                } catch (NumberFormatException ignored) {
                    log.debug("无法解析视频时长: {}", durationStr);
                }
            }
        }

        syncEmbeddedSubtitleTracks(item, embeddedSubtitles);
    }

    /**
     * 将探测得到的内嵌字幕轨道按 streamIndex 幂等合并。
     *
     * <p>合并基准为该条目下所有携带 streamIndex 的字幕行：既包含未提取的内嵌行
     * （trackKind 为 SUBTITLE 且 fileNodeId 为空），也包含提取后被改写为 EXTERNAL
     * 的行；若只按内嵌判据取基准，已提取行会被当作消失流删除并重新插入未提取行，
     * 导致每次重探测都全量重跑提取。匹配行原位更新并保留 id、fileNodeId 与
     * trackKind，消失流 bulk 删除，仅真正新增的流插入新行。</p>
     */
    private void syncEmbeddedSubtitleTracks(MediaVideoItem item, List<MediaSubtitleTrack> probedTracks) {
        List<MediaSubtitleTrack> existingTracks = subtitleTrackRepository
                .findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(item.getOwnerUserId(), item.getId())
                .stream()
                .filter(track -> track.getStreamIndex() != null)
                .filter(track -> TrackKind.SUBTITLE.getValue().equals(track.getTrackKind())
                        || (TrackKind.EXTERNAL.getValue().equals(track.getTrackKind())
                                && track.getFileNodeId() != null))
                .toList();
        Map<Integer, MediaSubtitleTrack> primaryByStreamIndex = new LinkedHashMap<>();
        for (MediaSubtitleTrack track : existingTracks) {
            MediaSubtitleTrack previous = primaryByStreamIndex.get(track.getStreamIndex());
            if (previous == null) {
                primaryByStreamIndex.put(track.getStreamIndex(), track);
            } else if (previous.getFileNodeId() == null && track.getFileNodeId() != null) {
                // 同一流号遗留多行时优先保留已提取行作为合并基准。
                primaryByStreamIndex.put(track.getStreamIndex(), track);
            }
        }

        Set<UUID> keptIds = new HashSet<>();
        List<MediaSubtitleTrack> toSave = new ArrayList<>();
        for (MediaSubtitleTrack probed : probedTracks) {
            MediaSubtitleTrack current = primaryByStreamIndex.get(probed.getStreamIndex());
            if (current == null) {
                toSave.add(probed);
                continue;
            }
            // 复用原行标识与提取结果：已提取行保留 fileNodeId 与 trackKind，
            // 避免重复提取；未提取行仅刷新探测得到的描述字段。
            probed.setId(current.getId());
            probed.setCreatedAt(current.getCreatedAt());
            if (current.getFileNodeId() != null) {
                probed.setFileNodeId(current.getFileNodeId());
                probed.setTrackKind(current.getTrackKind());
                probed.setLabel(current.getLabel());
            }
            keptIds.add(current.getId());
            toSave.add(probed);
        }
        List<UUID> removedIds = existingTracks.stream()
                .filter(track -> !keptIds.contains(track.getId()))
                .map(MediaSubtitleTrack::getId)
                .toList();
        // 消失流与同流号遗留的重复行一并 bulk 删除。
        if (!removedIds.isEmpty()) {
            subtitleTrackRepository.deleteAllByIdIn(item.getOwnerUserId(), removedIds);
        }
        if (!toSave.isEmpty()) {
            subtitleTrackRepository.saveAll(toSave);
        }
    }

    private void applyVideoStream(MediaVideoItem item, JsonNode stream) {
        String codecName = stream.path("codec_name").asString(null);
        if (codecName != null && !codecName.isBlank()) {
            item.setVideoCodec(codecName);
        }
        Integer width = stream.hasNonNull("width") ? stream.path("width").asInt() : null;
        Integer height = stream.hasNonNull("height") ? stream.path("height").asInt() : null;
        if (width != null && width > 0) {
            item.setResolutionWidth(width);
        }
        if (height != null && height > 0) {
            item.setResolutionHeight(height);
        }
    }

    private void applyAudioStream(MediaVideoItem item, JsonNode stream) {
        String codecName = stream.path("codec_name").asString(null);
        if (codecName != null && !codecName.isBlank()) {
            item.setAudioCodec(codecName);
        }
    }

    /** 位图字幕编码（无法转换为 WebVTT 文本，Web 端不支持） */
    private static final List<String> BITMAP_SUBTITLE_CODECS = List.of(
            "hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle"
    );

    private MediaSubtitleTrack buildEmbeddedSubtitle(MediaVideoItem item, JsonNode stream, int index) {
        String codecName = stream.path("codec_name").asString(null);
        if (codecName == null || codecName.isBlank()) {
            return null;
        }
        // 过滤位图字幕（PGS/VobSub/DVB），无法转换为文本格式
        if (BITMAP_SUBTITLE_CODECS.contains(codecName.trim().toLowerCase())) {
            return null;
        }
        String language = stream.path("tags").path("language").asString(null);
        if (language == null || language.isBlank()) {
            JsonNode tags = stream.path("tags");
            language = tags.isObject() ? tags.path("language").asString(null) : null;
        }
        if (language == null || language.isBlank()) {
            language = "und";
        }
        String title = null;
        JsonNode tags = stream.path("tags");
        if (tags.isObject()) {
            title = tags.path("title").asString(null);
        }
        String label = (title != null && !title.isBlank()) ? title : language + " #" + (index + 1);

        MediaSubtitleTrack track = new MediaSubtitleTrack();
        track.setId(UUID.randomUUID());
        track.setOwnerUserId(item.getOwnerUserId());
        track.setVideoItemId(item.getId());
        track.setFileNodeId(null);
        track.setLanguage(language);
        track.setLabel(label);
        track.setTrackKind("SUBTITLE");
        track.setStreamIndex(index);
        track.setSortOrder(100 + index);
        return track;
    }
}
