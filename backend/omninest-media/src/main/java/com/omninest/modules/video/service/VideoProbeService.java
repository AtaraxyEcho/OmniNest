package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaSubtitleTrack;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.event.VideoProbeEvent;
import com.omninest.modules.video.repository.MediaSubtitleTrackRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
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
    private static final long RANGE_BYTES = 5 * 1024 * 1024;
    private static final Duration COMMAND_CHECK_TIMEOUT = Duration.ofSeconds(30);
    private static final Duration PROBE_TIMEOUT = Duration.ofSeconds(60);
    private static final Duration COPY_TIMEOUT = Duration.ofSeconds(120);
    private static final Duration CLEANUP_TIMEOUT = Duration.ofSeconds(10);
    private static final String DOCKER_CONTAINER = "omninest-ffmpeg";
    private static final String DOCKER_PROBE_DIR = "/tmp/probe";

    private final FileQueryService fileQueryService;
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaSubtitleTrackRepository subtitleTrackRepository;
    private final TaskRecordService taskRecordService;
    private final MovieTaskService movieTaskService;
    private final MediaRuntimeConfigService mediaRuntimeConfigService;
    private final VideoTranscodeService videoTranscodeService;
    private final VideoProcessExecutor processExecutor;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final PlatformTransactionManager transactionManager;

    /**
     * ffprobe 可用方式。
     *
     * @author OmniNest
     */
    private enum ProbeMode { LOCAL, DOCKER, DISABLED }

    private volatile ProbeMode probeMode = ProbeMode.DISABLED;

    @PostConstruct
    void checkFfprobe() {
        // 优先尝试本地 ffprobe
        if (tryCommand("ffprobe", "-version")) {
            probeMode = ProbeMode.LOCAL;
            log.info("ffprobe 可用（本地），视频探测功能已启用");
            return;
        }
        // 回退到 Docker 容器
        if (tryCommand("docker", "exec", DOCKER_CONTAINER, "ffprobe", "-version")) {
            probeMode = ProbeMode.DOCKER;
            log.info("ffprobe 可用（Docker 容器 {}），视频探测功能已启用", DOCKER_CONTAINER);
            return;
        }
        probeMode = ProbeMode.DISABLED;
        log.warn("ffprobe 不可用，视频探测功能已禁用。"
                + "请安装 ffmpeg 或启动 Docker 容器: docker compose up -d ffmpeg");
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
        if (probeMode == ProbeMode.DISABLED) {
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

    public void probeByVideoItemId(UUID ownerUserId, UUID videoItemId) {
        MediaVideoItem item = videoItemRepository.findByIdAndOwnerUserId(videoItemId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "视频条目不存在: " + videoItemId));
        probe(item);
        // 探测事务提交后，提取内嵌字幕
        extractEmbeddedSubtitles(item);
    }

    public void probe(MediaVideoItem item) {
        UUID ownerUserId = item.getOwnerUserId();
        UUID fileNodeId = item.getFileNodeId();

        Path tempFile = null;
        try {
            // 内容读取与 ffprobe 均为 I/O 或 CPU 密集段，置于事务之外，避免独占数据库连接。
            tempFile = downloadPartial(ownerUserId, fileNodeId);
            if (tempFile == null) {
                return;
            }
            JSONObject probeResult = probeMode == ProbeMode.DOCKER
                    ? runFfprobeDocker(tempFile)
                    : runFfprobeLocal(tempFile);
            if (probeResult == null) {
                return;
            }
            // 仅结果落库置于独立事务内。
            TransactionTemplate writeTx = new TransactionTemplate(transactionManager);
            writeTx.executeWithoutResult(status -> {
                applyProbeResult(item, probeResult);
                videoItemRepository.save(item);
                triggerAudioExtractIfNeeded(item);
            });
            log.info("视频探测完成: itemId={}, videoCodec={}, audioCodec={}, resolution={}x{}",
                    item.getId(), item.getVideoCodec(), item.getAudioCodec(),
                    item.getResolutionWidth(), item.getResolutionHeight());
        } catch (Exception e) {
            log.warn("视频探测处理异常: itemId={}", item.getId(), e);
        } finally {
            if (tempFile != null) {
                try {
                    Files.deleteIfExists(tempFile);
                } catch (IOException ignored) {
                    log.debug("忽略: {}", ignored.getMessage());
                }
            }
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
        for (MediaSubtitleTrack track : tracks) {
            if (track.getStreamIndex() == null || track.getFileNodeId() != null) {
                continue;
            }
            try {
                extractSingleSubtitle(item, track);
            } catch (Exception e) {
                log.warn("字幕提取失败: videoItemId={}, streamIndex={}, message={}",
                        videoItemId, track.getStreamIndex(), e.getMessage());
            }
        }
    }

    /**
     * 提取单条内嵌字幕并更新字幕轨道引用。
     */
    private void extractSingleSubtitle(MediaVideoItem item, MediaSubtitleTrack track) {
        UUID ownerUserId = item.getOwnerUserId();
        UUID videoItemId = item.getId();
        int streamIndex = track.getStreamIndex();

        // Phase 1：ffmpeg 提取 WebVTT（事务外 I/O）
        Path vttFile = videoTranscodeService.extractSubtitleToWebVtt(
                ownerUserId, item.getFileNodeId(), videoItemId, streamIndex);
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
        } finally {
            try {
                Files.deleteIfExists(vttFile);
            } catch (IOException ignored) {
                log.debug("忽略: {}", ignored.getMessage());
            }
        }
    }

    private Path downloadPartial(UUID ownerUserId, UUID fileNodeId) {
        Path tempFile = null;
        try (FileContentStream content = fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId)) {
                tempFile = Files.createTempFile("probe-", ".tmp");
                try (OutputStream output = Files.newOutputStream(tempFile)) {
                    copyAtMost(content.inputStream(), output, RANGE_BYTES);
                }
            return tempFile;
        } catch (Exception e) {
            log.warn("读取视频探测片段异常: fileNodeId={}", fileNodeId, e);
            deleteTempFile(tempFile);
            return null;
        }
    }

    /**
     * 将输入流复制到输出流，但不超过指定字节数。
     *
     * @param input    输入流
     * @param output   输出流
     * @param maxBytes 最大复制字节数
     * @return 实际复制字节数
     * @throws IOException 流读取或写入失败
     */
    static long copyAtMost(InputStream input, OutputStream output, long maxBytes) throws IOException {
        if (maxBytes <= 0) {
            throw new IllegalArgumentException("最大复制字节数必须大于零");
        }
        byte[] buffer = new byte[8192];
        long copied = 0;
        while (copied < maxBytes) {
            int requested = (int) Math.min(buffer.length, maxBytes - copied);
            int read = input.read(buffer, 0, requested);
            if (read == -1) {
                break;
            }
            output.write(buffer, 0, read);
            copied += read;
        }
        return copied;
    }

    private void deleteTempFile(Path tempFile) {
        if (tempFile == null) {
            return;
        }
        try {
            Files.deleteIfExists(tempFile);
        } catch (IOException cleanupException) {
            log.debug("视频探测临时文件清理失败: {}", cleanupException.getMessage());
        }
    }

    private JSONObject runFfprobeLocal(Path file) {
        try {
            VideoProcessExecutor.Result result = processExecutor.execute(List.of(
                    "ffprobe",
                    "-v", "quiet",
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
            return JSON.parseObject(result.output());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("ffprobe 执行被中断");
            return null;
        } catch (IOException e) {
            log.warn("ffprobe 执行失败", e);
            return null;
        }
    }

    private JSONObject runFfprobeDocker(Path hostFile) {
        String containerFile = DOCKER_PROBE_DIR + "/" + hostFile.getFileName().toString();
        try {
            VideoProcessExecutor.Result copyResult = processExecutor.execute(List.of(
                    "docker", "cp",
                    hostFile.toAbsolutePath().toString(),
                    DOCKER_CONTAINER + ":" + containerFile
            ), COPY_TIMEOUT);
            if (copyResult.timedOut()) {
                log.warn("docker cp 超时");
                return null;
            }
            if (!copyResult.succeeded()) {
                log.warn("docker cp 失败: exitCode={}", copyResult.exitCode());
                return null;
            }

            VideoProcessExecutor.Result probeResult = processExecutor.execute(List.of(
                    "docker", "exec", DOCKER_CONTAINER,
                    "ffprobe",
                    "-v", "quiet",
                    "-print_format", "json",
                    "-show_format",
                    "-show_streams",
                    containerFile
            ), PROBE_TIMEOUT);
            if (probeResult.timedOut()) {
                log.warn("Docker ffprobe 超时");
                return null;
            }
            if (!probeResult.succeeded()) {
                log.warn("Docker ffprobe 退出码异常: exitCode={}", probeResult.exitCode());
                return null;
            }
            return JSON.parseObject(probeResult.output());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("Docker ffprobe 执行被中断");
            return null;
        } catch (IOException e) {
            log.warn("Docker ffprobe 执行失败", e);
            return null;
        } finally {
            cleanupDockerProbeFile(containerFile);
        }
    }

    private void cleanupDockerProbeFile(String containerFile) {
        try {
            VideoProcessExecutor.Result result = processExecutor.execute(List.of(
                    "docker", "exec", DOCKER_CONTAINER, "rm", "-f", containerFile
            ), CLEANUP_TIMEOUT);
            if (!result.succeeded()) {
                log.debug("Docker 探测临时文件清理未完成: timedOut={}, exitCode={}",
                        result.timedOut(), result.exitCode());
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (IOException e) {
            log.debug("Docker 探测临时文件清理失败: {}", e.getMessage());
        }
    }

    private void applyProbeResult(MediaVideoItem item, JSONObject probeResult) {
        JSONArray streams = probeResult.getJSONArray("streams");
        if (streams == null) {
            return;
        }
        List<MediaSubtitleTrack> embeddedSubtitles = new ArrayList<>();

        for (int i = 0; i < streams.size(); i++) {
            JSONObject stream = streams.getJSONObject(i);
            String codecType = stream.getString("codec_type");
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

        JSONObject format = probeResult.getJSONObject("format");
        if (format != null) {
            String formatName = format.getString("format_name");
            if (formatName != null && !formatName.isBlank()) {
                item.setContainerFormat(formatName);
            }
            // 提取视频总时长（秒），ffprobe 返回浮点字符串如 "7200.123456"
            String durationStr = format.getString("duration");
            if (durationStr != null && !durationStr.isBlank()) {
                try {
                    item.setDurationSeconds((int) Double.parseDouble(durationStr));
                } catch (NumberFormatException ignored) {
                    log.debug("无法解析视频时长: {}", durationStr);
                }
            }
        }

        if (!embeddedSubtitles.isEmpty()) {
            subtitleTrackRepository.saveAll(embeddedSubtitles);
        }
    }

    private void applyVideoStream(MediaVideoItem item, JSONObject stream) {
        String codecName = stream.getString("codec_name");
        if (codecName != null && !codecName.isBlank()) {
            item.setVideoCodec(codecName);
        }
        Integer width = stream.getInteger("width");
        Integer height = stream.getInteger("height");
        if (width != null && width > 0) {
            item.setResolutionWidth(width);
        }
        if (height != null && height > 0) {
            item.setResolutionHeight(height);
        }
    }

    private void applyAudioStream(MediaVideoItem item, JSONObject stream) {
        String codecName = stream.getString("codec_name");
        if (codecName != null && !codecName.isBlank()) {
            item.setAudioCodec(codecName);
        }
    }

    /** 位图字幕编码（无法转换为 WebVTT 文本，Web 端不支持） */
    private static final List<String> BITMAP_SUBTITLE_CODECS = List.of(
            "hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle"
    );

    private MediaSubtitleTrack buildEmbeddedSubtitle(MediaVideoItem item, JSONObject stream, int index) {
        String codecName = stream.getString("codec_name");
        if (codecName == null || codecName.isBlank()) {
            return null;
        }
        // 过滤位图字幕（PGS/VobSub/DVB），无法转换为文本格式
        if (BITMAP_SUBTITLE_CODECS.contains(codecName.trim().toLowerCase())) {
            return null;
        }
        String language = stream.getString("tags.language");
        if (language == null || language.isBlank()) {
            JSONObject tags = stream.getJSONObject("tags");
            language = tags != null ? tags.getString("language") : null;
        }
        if (language == null || language.isBlank()) {
            language = "und";
        }
        String title = null;
        JSONObject tags = stream.getJSONObject("tags");
        if (tags != null) {
            title = tags.getString("title");
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
