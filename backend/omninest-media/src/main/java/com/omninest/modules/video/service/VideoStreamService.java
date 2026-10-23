package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.video.config.VideoStreamProperties;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Web 端流式音频转码服务。
 * 优先在后端容器本地启动 ffmpeg；缺少本地 ffmpeg 时回退到 docker exec。
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class VideoStreamService {
    private static final int BUFFER_SIZE = 64 * 1024;
    /** 流式转码超时（秒）：4 小时 */
    private static final long STREAM_TRANSCODE_TIMEOUT_SECONDS = 4 * 3600;
    private static final long TIMEOUT_JOIN_MILLIS = 5_000L;

    /** Web 端浏览器原生不支持的音频编码（flac/vorbis 现代浏览器已支持，不再列入） */
    public static final List<String> WEB_UNSUPPORTED_AUDIO = List.of(
            "ac3", "eac3", "dts", "dts-hd", "truehd", "pcm"
    );

    private final MediaVideoItemRepository videoItemRepository;
    private final VideoSourceInputResolver sourceInputResolver;
    private final MediaContentAccessService mediaContentAccessService;
    private final VideoStreamProperties streamProperties;
    private final VideoFfmpegRuntime ffmpegRuntime;
    private final VideoProcessExecutor processExecutor;

    /**
     * 同一时刻允许的实时 ffmpeg 流数。
     *
     * <p>每次 Seek 都会另起一路 HTTP 流请求，无上限时连续拖动进度条会让多个 ffmpeg
     * 同时全速拉取源视频，打满宿主机 CPU 与对象存储带宽。槽位耗尽时短暂等待
     * 客户端已断开的旧进程释放槽位，仍取不到才拒绝新流。</p>
     */
    private final Semaphore streamSlots;

    /** 同一观看者同一影片只保留最新一路 ffmpeg；拖动进度条重开流时先杀掉旧进程。 */
    private final Map<String, Process> activeStreams = new ConcurrentHashMap<>();

    /** docker 模式下的容器内进程标记，用于 destroy 客户端后终止容器内 ffmpeg。 */
    private final Map<Process, String> containerStreamMarkers = new ConcurrentHashMap<>();

    /**
     * 占用一路实时转码槽位，取不到时返回可重试的业务错误。
     */
    private void requireStreamSlot(UUID videoItemId) {
        boolean acquired;
        try {
            acquired = streamSlots.tryAcquire(
                    Math.max(0L, streamProperties.getSlotWaitTimeout().toMillis()), TimeUnit.MILLISECONDS);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "实时转码通道已满，请稍后重试");
        }
        if (!acquired) {
            log.warn("实时音频转码并发已达上限: limit={}, videoItemId={}",
                    streamProperties.getMaxConcurrentStreams(), videoItemId);
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "实时转码通道已满，请稍后重试");
        }
    }

    private void releaseStreamSlot() {
        streamSlots.release();
    }

    public VideoStreamService(
            MediaVideoItemRepository videoItemRepository,
            VideoSourceInputResolver sourceInputResolver,
            MediaContentAccessService mediaContentAccessService,
            VideoStreamProperties streamProperties,
            VideoFfmpegRuntime ffmpegRuntime,
            VideoProcessExecutor processExecutor
    ) {
        this.videoItemRepository = videoItemRepository;
        this.sourceInputResolver = sourceInputResolver;
        this.mediaContentAccessService = mediaContentAccessService;
        this.streamProperties = streamProperties;
        this.ffmpegRuntime = ffmpegRuntime;
        this.processExecutor = processExecutor;
        this.streamSlots = new Semaphore(Math.max(1, streamProperties.getMaxConcurrentStreams()), true);
    }

    /**
     * 判断指定视频条目的音频编码是否需要 Web 端转码。
     */
    public boolean needsTranscode(UUID ownerUserId, UUID videoItemId) {
        MediaVideoItem item = mediaContentAccessService.findReadableVideo(ownerUserId, videoItemId)
                .orElse(null);
        if (item == null) {
            return false;
        }
        String audioCodec = item.getAudioCodec();
        if (audioCodec == null || audioCodec.isBlank()) {
            return false;
        }
        return WEB_UNSUPPORTED_AUDIO.contains(audioCodec.trim().toLowerCase());
    }

    /**
     * 按请求的音频模式选择缓存音频复用或实时转码。
     *
     * @param ownerUserId 所属用户
     * @param videoItemId 视频条目标识
     * @param startSeconds 起始秒数
     * @param audioMode 音频模式
     * @param output HTTP 响应输出流
     */
    public void streamByAudioMode(
            UUID ownerUserId,
            UUID videoItemId,
            long startSeconds,
            String audioMode,
            OutputStream output
    ) {
        streamByAudioMode(ownerUserId, videoItemId, null, startSeconds, audioMode, output);
    }

    /**
     * 按音频模式输出转码流，并按观看者替换上一次未结束的流。
     *
     * @param ownerUserId 目录所有者
     * @param videoItemId 视频条目标识
     * @param viewerUserId 实际观看者；为空时不启用同观看者旧流替换
     * @param startSeconds 起始秒数
     * @param audioMode 音频模式
     * @param output HTTP 响应输出流
     */
    public void streamByAudioMode(
            UUID ownerUserId,
            UUID videoItemId,
            UUID viewerUserId,
            long startSeconds,
            String audioMode,
            OutputStream output
    ) {
        MediaVideoItem sourceItem = mediaContentAccessService.requireReadableVideo(ownerUserId, videoItemId);
        UUID catalogOwnerId = sourceItem.getOwnerUserId();
        String streamKey = streamKey(viewerUserId, videoItemId);
        var audioCached = videoItemRepository
                .findByOwnerUserIdAndSourceVideoItemIdAndVersionLabel(
                        catalogOwnerId,
                        videoItemId,
                        "AUDIO_ONLY"
                );
        if ("cached".equals(audioMode) && audioCached.isPresent()) {
            UUID audioFileNodeId = audioCached.get().getFileNodeId();
            log.info("使用缓存音频 mux: videoItemId={}, audioFileNodeId={}", videoItemId, audioFileNodeId);
            if (streamKey == null) {
                streamWithCachedAudio(catalogOwnerId, videoItemId, audioFileNodeId, startSeconds, output);
            } else {
                streamWithCachedAudio(
                        catalogOwnerId, videoItemId, audioFileNodeId, startSeconds, streamKey, output);
            }
            return;
        }
        if ("cached".equals(audioMode)) {
            log.info("缓存音频不存在，回退到实时转码: videoItemId={}", videoItemId);
        } else {
            log.info("使用原始音频实时转码: videoItemId={}", videoItemId);
        }
        if (streamKey == null) {
            streamAudioTranscoded(catalogOwnerId, videoItemId, startSeconds, output);
        } else {
            streamAudioTranscoded(catalogOwnerId, videoItemId, startSeconds, streamKey, output);
        }
    }

    private String streamKey(UUID viewerUserId, UUID videoItemId) {
        return viewerUserId == null ? null : viewerUserId + ":" + videoItemId;
    }

    private void terminateActiveStream(String streamKey) {
        if (streamKey == null) {
            return;
        }
        Process previous = activeStreams.remove(streamKey);
        if (previous != null) {
            log.info("替换同一观看者的旧转码流: streamKey={}", streamKey);
            terminateProcess(previous);
        }
    }

    private void registerActiveStream(String streamKey, Process process) {
        if (streamKey != null) {
            activeStreams.put(streamKey, process);
        }
    }

    private void unregisterActiveStream(String streamKey, Process process) {
        if (streamKey != null) {
            activeStreams.remove(streamKey, process);
        }
    }

    /**
     * 以流式方式将视频输出到 OutputStream。
     * 视频流 copy，音频转码为 AAC，输出 fMP4 格式。
     *
     * @param ownerUserId  所属用户
     * @param videoItemId  视频条目 ID
     * @param startSeconds 起始秒数（用于 seek）
     * @param output       HTTP 响应的 OutputStream
     */
    public void streamAudioTranscoded(
            UUID ownerUserId, UUID videoItemId, long startSeconds, OutputStream output
    ) {
        streamAudioTranscoded(ownerUserId, videoItemId, startSeconds, null, output);
    }

    private void streamAudioTranscoded(
            UUID ownerUserId, UUID videoItemId, long startSeconds, String streamKey, OutputStream output
    ) {
        MediaVideoItem item = mediaContentAccessService.requireReadableVideo(ownerUserId, videoItemId);

        String demuxer = VideoLiveInputFormats.requireDemuxer(item.getContainerFormat());
        String internalUrl = resolveInput(ownerUserId, item.getFileNodeId());
        log.info("流式转码开始: videoItemId={}, audioCodec={}, container={}, demuxer={}, startSeconds={}",
                videoItemId, item.getAudioCodec(), item.getContainerFormat(), demuxer, startSeconds);

        List<String> ffmpegArgs = buildTranscodeArgs(demuxer, internalUrl, startSeconds);
        StreamCommand streamCommand = buildStreamCommand(ffmpegArgs, List.of(internalUrl));
        terminateActiveStream(streamKey);
        requireStreamSlot(videoItemId);

        Process process = null;
        try {
            ProcessBuilder pb = new ProcessBuilder(streamCommand.command());
            pb.redirectErrorStream(false);
            process = pb.start();
            registerContainerMarker(process, streamCommand.marker());
            registerActiveStream(streamKey, process);
            log.info("ffmpeg 进程已启动: pid={}", process.pid());
            final Process ffmpegProcess = process;
            AtomicBoolean timedOut = new AtomicBoolean();
            Thread timeoutThread = startTimeoutMonitor(ffmpegProcess, timedOut);

            Thread.ofVirtual()
                    .name("ffmpeg-stderr")
                    .start(() -> drainStderr(ffmpegProcess));

            try (InputStream stdout = process.getInputStream()) {
                byte[] buffer = new byte[BUFFER_SIZE];
                int bytesRead;
                while ((bytesRead = stdout.read(buffer)) != -1) {
                    output.write(buffer, 0, bytesRead);
                    output.flush();
                }
            }

            timeoutThread.join(TIMEOUT_JOIN_MILLIS);
            if (timedOut.get()) {
                log.warn("ffmpeg 流式转码超时: videoItemId={}, timeout={}s", videoItemId, STREAM_TRANSCODE_TIMEOUT_SECONDS);
                return;
            }
            int exitCode = process.exitValue();
            if (exitCode != 0) {
                log.warn("ffmpeg 流式转码退出码异常: exitCode={}, videoItemId={}", exitCode, videoItemId);
            } else {
                log.info("流式转码完成: videoItemId={}, startSeconds={}", videoItemId, startSeconds);
            }
        } catch (IOException e) {
            log.debug("流式转码中断（客户端可能断开）: videoItemId={}, message={}", videoItemId, e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("流式转码被中断: videoItemId={}", videoItemId);
        } finally {
            unregisterActiveStream(streamKey, process);
            terminateProcess(process);
            releaseStreamSlot();
        }
    }

    /**
     * 将原始视频流 + 缓存的 AAC 音频流 mux 为 fMP4 推送给浏览器。
     * 视频流 copy（零编码开销），音频从缓存文件读取。
     *
     * @param ownerUserId      源条目的目录所有者（非请求者）
     * @param sourceVideoItemId 原始视频条目 ID（用于获取视频流）
     * @param audioFileNodeId  缓存 AAC 音频的 FileNode ID
     * @param startSeconds     起始秒数（用于 seek）
     * @param output           HTTP 响应的 OutputStream
     */
    public void streamWithCachedAudio(
            UUID ownerUserId, UUID sourceVideoItemId, UUID audioFileNodeId,
            long startSeconds, OutputStream output
    ) {
        streamWithCachedAudio(ownerUserId, sourceVideoItemId, audioFileNodeId, startSeconds, null, output);
    }

    private void streamWithCachedAudio(
            UUID ownerUserId, UUID sourceVideoItemId, UUID audioFileNodeId,
            long startSeconds, String streamKey, OutputStream output
    ) {
        MediaVideoItem sourceItem = mediaContentAccessService.requireReadableVideo(ownerUserId, sourceVideoItemId);

        String videoDemuxer = VideoLiveInputFormats.requireDemuxer(sourceItem.getContainerFormat());
        String videoInternalUrl = resolveInput(ownerUserId, sourceItem.getFileNodeId());
        String audioInternalUrl = resolveInput(ownerUserId, audioFileNodeId);

        log.info("缓存音频 mux 开始: sourceVideoItemId={}, demuxer={}, startSeconds={}",
                sourceVideoItemId, videoDemuxer, startSeconds);

        List<String> ffmpegArgs = buildCachedAudioArgs(
                videoDemuxer, videoInternalUrl, audioInternalUrl, startSeconds);
        StreamCommand streamCommand = buildStreamCommand(
                ffmpegArgs, List.of(videoInternalUrl, audioInternalUrl));
        terminateActiveStream(streamKey);
        requireStreamSlot(sourceVideoItemId);

        Process process = null;
        try {
            ProcessBuilder pb = new ProcessBuilder(streamCommand.command());
            pb.redirectErrorStream(false);
            process = pb.start();
            registerContainerMarker(process, streamCommand.marker());
            registerActiveStream(streamKey, process);
            log.info("ffmpeg mux 进程已启动: pid={}", process.pid());
            final Process ffmpegProcess = process;
            AtomicBoolean timedOut = new AtomicBoolean();
            Thread timeoutThread = startTimeoutMonitor(ffmpegProcess, timedOut);

            Thread.ofVirtual()
                    .name("ffmpeg-stderr")
                    .start(() -> drainStderr(ffmpegProcess));

            try (InputStream stdout = process.getInputStream()) {
                byte[] buffer = new byte[BUFFER_SIZE];
                int bytesRead;
                while ((bytesRead = stdout.read(buffer)) != -1) {
                    output.write(buffer, 0, bytesRead);
                    output.flush();
                }
            }

            timeoutThread.join(TIMEOUT_JOIN_MILLIS);
            if (timedOut.get()) {
                log.warn(
                        "ffmpeg mux 超时: sourceVideoItemId={}, timeout={}s",
                        sourceVideoItemId,
                        STREAM_TRANSCODE_TIMEOUT_SECONDS
                );
                return;
            }
            int exitCode = process.exitValue();
            if (exitCode != 0) {
                log.warn("ffmpeg mux 退出码异常: exitCode={}, sourceVideoItemId={}", exitCode, sourceVideoItemId);
            } else {
                log.info("缓存音频 mux 完成: sourceVideoItemId={}, startSeconds={}", sourceVideoItemId, startSeconds);
            }
        } catch (IOException e) {
            log.debug("mux 中断（客户端可能断开）: sourceVideoItemId={}, message={}", sourceVideoItemId, e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("mux 被中断: sourceVideoItemId={}", sourceVideoItemId);
        } finally {
            unregisterActiveStream(streamKey, process);
            terminateProcess(process);
            releaseStreamSlot();
        }
    }

    /**
     * 构建实时转码的 ffmpeg 参数（不含执行前缀，不含 -i 之前的协议白名单）。
     */
    List<String> buildTranscodeArgs(String demuxer, String inputUrl, long startSeconds) {
        List<String> args = new ArrayList<>();
        if (startSeconds > 0) {
            args.addAll(List.of("-ss", String.valueOf(startSeconds)));
        }
        // 不映射字幕流：字幕通过独立的 /vtt 端点按需提取为 WebVTT
        args.addAll(List.of(
                "-f", demuxer,
                "-i", inputUrl,
                "-map", "0:v",
                "-map", "0:a"
        ));
        // 视频流直接 copy（零编码开销），浏览器负责解码
        // hevc/h265: Chrome 107+ 支持硬件解码，Safari 原生支持
        args.addAll(List.of("-c:v", "copy"));
        args.addAll(List.of(
                "-c:a", "aac", "-b:a", "192k",
                "-f", "mp4",
                "-movflags", "frag_keyframe+empty_moov",
                "pipe:1"
        ));
        return args;
    }

    /**
     * 构建缓存音频 mux 的 ffmpeg 参数。
     */
    List<String> buildCachedAudioArgs(
            String videoDemuxer, String videoUrl, String audioUrl, long startSeconds) {
        List<String> args = new ArrayList<>();
        if (startSeconds > 0) {
            args.addAll(List.of("-ss", String.valueOf(startSeconds)));
        }
        args.addAll(List.of(
                "-f", videoDemuxer,
                "-i", videoUrl,
                // 派生音频固定为 ADTS AAC，同样不允许自动探测。
                "-f", "aac",
                "-i", audioUrl,
                "-map", "0:v", "-map", "1:a"
        ));
        // 视频流直接 copy（零编码开销），浏览器负责解码
        args.addAll(List.of("-c:v", "copy"));
        // 音频重新编码为 AAC-LC：原始 ADTS 流的元数据（时长/码率）可能不准确，
        // copy 会导致浏览器收到畸形数据断开连接；re-encode 确保输出正确的 ASC 头和 MP4 兼容格式
        args.addAll(List.of(
                "-c:a", "aac", "-b:a", "192k", "-ac", "2",
                "-f", "mp4",
                "-movflags", "frag_keyframe+empty_moov",
                "pipe:1"
        ));
        return args;
    }

    /**
     * 按运行位置构建完整命令：两种模式都限制协议，docker 模式另加带 PID 文件的 shell 包装。
     */
    StreamCommand buildStreamCommand(List<String> ffmpegArgs, List<String> inputs) {
        if (ffmpegRuntime.isDisabled()) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "ffmpeg 不可用，无法实时转码");
        }
        List<String> args = new ArrayList<>();
        // 协议白名单必须出现在第一个 -i 之前。本地后端容器与 ffmpeg 容器都持有本地挂载，
        // 且本机进程还有出网能力，不能让媒体内容里的 file:/concat: 引用成为读取或跳板。
        args.add("-protocol_whitelist");
        args.add(combinedProtocolWhitelist(inputs));
        args.addAll(ffmpegArgs);
        if (ffmpegRuntime.isDocker()) {
            String marker = ffmpegRuntime.newMarker();
            return new StreamCommand(ffmpegRuntime.dockerStreamCommand(marker, args), marker);
        }
        List<String> command = new ArrayList<>();
        command.add("ffmpeg");
        command.add("-y");
        command.addAll(args);
        return new StreamCommand(command, null);
    }

    private String resolveInput(UUID ownerUserId, UUID fileNodeId) {
        return ffmpegRuntime.isDocker()
                ? sourceInputResolver.resolveDockerInput(ownerUserId, fileNodeId)
                : sourceInputResolver.resolveLocalInput(ownerUserId, fileNodeId);
    }

    private String combinedProtocolWhitelist(List<String> inputs) {
        boolean hasHttp = inputs.stream().anyMatch(this::isHttpInput);
        boolean hasLocal = inputs.stream().anyMatch(input -> !isHttpInput(input));
        if (hasHttp && hasLocal) {
            return "file,crypto,data,http,https,tcp,tls";
        }
        return hasLocal ? "file,crypto,data" : "http,https,tcp,tls";
    }

    private boolean isHttpInput(String input) {
        if (input == null) {
            return false;
        }
        String lower = input.toLowerCase(Locale.ROOT);
        return lower.startsWith("http://") || lower.startsWith("https://");
    }

    private void registerContainerMarker(Process process, String marker) {
        if (process != null && marker != null) {
            containerStreamMarkers.put(process, marker);
        }
    }

    record StreamCommand(List<String> command, String marker) {
    }

    private void terminateProcess(Process process) {
        if (process == null) {
            return;
        }
        // docker exec 客户端被销毁后容器内 ffmpeg 仍可能存活；先按 PID 文件终止容器内进程。
        String marker = containerStreamMarkers.remove(process);
        if (marker != null) {
            terminateContainerProcess(marker);
        }
        process.destroyForcibly();
        try {
            process.waitFor(2, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        try {
            process.getInputStream().close();
        } catch (IOException e) {
            log.debug("关闭已销毁进程流失败: {}", e.getMessage());
        }
        try {
            process.getErrorStream().close();
        } catch (IOException e) {
            log.debug("关闭已销毁进程流失败: {}", e.getMessage());
        }
        try {
            process.getOutputStream().close();
        } catch (IOException e) {
            log.debug("关闭已销毁进程流失败: {}", e.getMessage());
        }
    }

    private void terminateContainerProcess(String marker) {
        try {
            VideoProcessExecutor.Result result = processExecutor.execute(
                    ffmpegRuntime.dockerKillCommand(marker),
                    Duration.ofSeconds(10)
            );
            if (!result.succeeded()) {
                log.debug("终止容器内 ffmpeg 未确认: timedOut={}, exitCode={}",
                        result.timedOut(), result.exitCode());
            }
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
        } catch (IOException exception) {
            log.debug("终止容器内 ffmpeg 失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    private Thread startTimeoutMonitor(Process process, AtomicBoolean timedOut) {
        return Thread.ofVirtual()
                .name("ffmpeg-timeout")
                .start(() -> {
                    try {
                        boolean finished = process.waitFor(STREAM_TRANSCODE_TIMEOUT_SECONDS, TimeUnit.SECONDS);
                        if (!finished) {
                            timedOut.set(true);
                            process.destroyForcibly();
                        }
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        process.destroyForcibly();
                    }
                });
    }

    private void drainStderr(Process process) {
        long drainedBytes = 0;
        try (InputStream stderr = process.getErrorStream()) {
            byte[] buffer = new byte[4096];
            int bytesRead;
            while ((bytesRead = stderr.read(buffer)) != -1) {
                drainedBytes += bytesRead;
            }
            log.debug("ffmpeg stderr 已排空: bytes={}", drainedBytes);
        } catch (IOException e) {
            log.debug("ffmpeg stderr 读取结束: {}", e.getMessage());
        }
    }
}
