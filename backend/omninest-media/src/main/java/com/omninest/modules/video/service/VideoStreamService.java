package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * Web 端流式音频转码服务。
 * 通过 Docker exec 启动 ffmpeg，从 MinIO URL 读取源视频。
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class VideoStreamService {
    private static final String DOCKER_CONTAINER = "omninest-ffmpeg";
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

    public VideoStreamService(
            MediaVideoItemRepository videoItemRepository,
            VideoSourceInputResolver sourceInputResolver
    ) {
        this.videoItemRepository = videoItemRepository;
        this.sourceInputResolver = sourceInputResolver;
    }

    /**
     * 判断指定视频条目的音频编码是否需要 Web 端转码。
     */
    public boolean needsTranscode(UUID ownerUserId, UUID videoItemId) {
        MediaVideoItem item = videoItemRepository.findByIdAndOwnerUserId(videoItemId, ownerUserId)
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
        var audioCached = videoItemRepository
                .findByOwnerUserIdAndSourceVideoItemIdAndVersionLabel(
                        ownerUserId,
                        videoItemId,
                        "AUDIO_ONLY"
                );
        if ("cached".equals(audioMode) && audioCached.isPresent()) {
            UUID audioFileNodeId = audioCached.get().getFileNodeId();
            log.info("使用缓存音频 mux: videoItemId={}, audioFileNodeId={}", videoItemId, audioFileNodeId);
            streamWithCachedAudio(ownerUserId, videoItemId, audioFileNodeId, startSeconds, output);
            return;
        }
        if ("cached".equals(audioMode)) {
            log.info("缓存音频不存在，回退到实时转码: videoItemId={}", videoItemId);
        } else {
            log.info("使用原始音频实时转码: videoItemId={}", videoItemId);
        }
        streamAudioTranscoded(ownerUserId, videoItemId, startSeconds, output);
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
        MediaVideoItem item = videoItemRepository.findByIdAndOwnerUserId(videoItemId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "视频条目不存在"));

        String internalUrl = sourceInputResolver.resolveDockerInput(ownerUserId, item.getFileNodeId());
        log.info("流式转码开始: videoItemId={}, audioCodec={}, container={}, startSeconds={}",
                videoItemId, item.getAudioCodec(), item.getContainerFormat(), startSeconds);

        String[] command = buildFfmpegTranscodeCommand(internalUrl, startSeconds);

        Process process = null;
        try {
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(false);
            process = pb.start();
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
            terminateProcess(process);
        }
    }

    /**
     * 将原始视频流 + 缓存的 AAC 音频流 mux 为 fMP4 推送给浏览器。
     * 视频流 copy（零编码开销），音频从缓存文件读取。
     *
     * @param ownerUserId      所属用户
     * @param sourceVideoItemId 原始视频条目 ID（用于获取视频流）
     * @param audioFileNodeId  缓存 AAC 音频的 FileNode ID
     * @param startSeconds     起始秒数（用于 seek）
     * @param output           HTTP 响应的 OutputStream
     */
    public void streamWithCachedAudio(
            UUID ownerUserId, UUID sourceVideoItemId, UUID audioFileNodeId,
            long startSeconds, OutputStream output
    ) {
        MediaVideoItem sourceItem = videoItemRepository.findByIdAndOwnerUserId(sourceVideoItemId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "视频条目不存在"));

        String videoInternalUrl = sourceInputResolver.resolveDockerInput(ownerUserId, sourceItem.getFileNodeId());
        String audioInternalUrl = sourceInputResolver.resolveDockerInput(ownerUserId, audioFileNodeId);

        log.info("缓存音频 mux 开始: sourceVideoItemId={}, startSeconds={}", sourceVideoItemId, startSeconds);

        List<String> cmd = new ArrayList<>(List.of(
                "docker", "exec", DOCKER_CONTAINER,
                "ffmpeg", "-y"
        ));
        if (startSeconds > 0) {
            cmd.addAll(List.of("-ss", String.valueOf(startSeconds)));
        }
        cmd.addAll(List.of(
                "-i", videoInternalUrl,
                "-i", audioInternalUrl,
                "-map", "0:v", "-map", "1:a"
        ));
        // 视频流直接 copy（零编码开销），浏览器负责解码
        // hevc/h265: Chrome 107+ 支持硬件解码，Safari 原生支持
        cmd.addAll(List.of("-c:v", "copy"));
        // 音频重新编码为 AAC-LC：原始 ADTS 流的元数据（时长/码率）可能不准确，
        // copy 会导致浏览器收到畸形数据断开连接；re-encode 确保输出正确的 ASC 头和 MP4 兼容格式
        cmd.addAll(List.of(
                "-c:a", "aac", "-b:a", "192k", "-ac", "2",
                "-f", "mp4",
                "-movflags", "frag_keyframe+empty_moov",
                "pipe:1"
        ));

        String[] command = cmd.toArray(new String[0]);

        Process process = null;
        try {
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(false);
            process = pb.start();
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
            terminateProcess(process);
        }
    }

    /**
     * 构建 ffmpeg 转码命令（DRY：seek 参数条件插入）。
     */
    private String[] buildFfmpegTranscodeCommand(String minioUrl, long startSeconds) {
        List<String> cmd = new ArrayList<>(List.of(
                "docker", "exec", DOCKER_CONTAINER,
                "ffmpeg", "-y"
        ));
        if (startSeconds > 0) {
            cmd.addAll(List.of("-ss", String.valueOf(startSeconds)));
        }
        // 不映射字幕流：字幕通过独立的 /vtt 端点按需提取为 WebVTT
        cmd.addAll(List.of(
                "-i", minioUrl,
                "-map", "0:v",
                "-map", "0:a"
        ));
        // 视频流直接 copy（零编码开销），浏览器负责解码
        // hevc/h265: Chrome 107+ 支持硬件解码，Safari 原生支持
        cmd.addAll(List.of("-c:v", "copy"));
        cmd.addAll(List.of(
                "-c:a", "aac", "-b:a", "192k",
                "-f", "mp4",
                "-movflags", "frag_keyframe+empty_moov",
                "pipe:1"
        ));
        return cmd.toArray(new String[0]);
    }

    private void terminateProcess(Process process) {
        if (process == null) {
            return;
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
