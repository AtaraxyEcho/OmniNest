package com.omninest.modules.video.service;

import com.omninest.common.config.ProcessingTempProperties;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileQueryService;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * FFmpeg 转码与字幕提取服务，全部在后端容器本地执行。
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class VideoTranscodeService {
    private static final Duration TRANSCODE_TIMEOUT = Duration.ofMinutes(180);

    private final ProcessingTempProperties processingTempProperties;
    private final VideoSourceInputResolver sourceInputResolver;
    private final VideoProcessExecutor processExecutor;
    private final VideoFfmpegRuntime ffmpegRuntime;
    private final FileQueryService fileQueryService;

    /**
     * 创建视频转码服务。
     *
     * @param sourceInputResolver 视频源输入解析器
     * @param processExecutor  视频外部进程执行器
     * @param ffmpegRuntime ffmpeg 运行位置探测
     */
    public VideoTranscodeService(
            ProcessingTempProperties processingTempProperties,
            VideoSourceInputResolver sourceInputResolver,
            VideoProcessExecutor processExecutor,
            VideoFfmpegRuntime ffmpegRuntime,
            FileQueryService fileQueryService
    ) {
        this.processingTempProperties = processingTempProperties;
        this.sourceInputResolver = sourceInputResolver;
        this.processExecutor = processExecutor;
        this.ffmpegRuntime = ffmpegRuntime;
        this.fileQueryService = fileQueryService;
    }

    /**
     * 在本地执行 H265 转码，返回转码后文件的本地临时路径。
     * 调用方负责删除返回的临时文件。
     */
    public Path transcodeToH265(UUID ownerUserId, UUID fileNodeId, UUID videoItemId) {
        return executeTranscode(ownerUserId, fileNodeId, videoItemId, ".mp4",
                List.of("-c:v", "libx265", "-crf", "28", "-preset", "medium",
                        "-tag:v", "hvc1", "-movflags", "faststart", "-c:a", "copy"),
                "H265 转码");
    }

    /**
     * 视频流 copy + 音频转码 AAC，输出标准 MP4（faststart）。
     * 仅处理音频编码不兼容 Web 端的视频（AC3/DTS/TrueHD 等）。
     * 调用方负责删除返回的临时文件。
     */
    public Path transcodeAudioToAac(UUID ownerUserId, UUID fileNodeId, UUID videoItemId) {
        return executeTranscode(ownerUserId, fileNodeId, videoItemId, ".mp4",
                List.of("-map", "0:v", "-map", "0:a",
                        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                        "-movflags", "faststart"),
                "音频 AAC 转码");
    }

    /**
     * 仅提取音频轨道为 AAC，不处理视频流。
     * 输出文件体积远小于完整转码（~200-400MB vs ~30GB）。
     * 调用方负责删除返回的临时文件。
     */
    public Path extractAudioToAac(UUID ownerUserId, UUID fileNodeId, UUID videoItemId) {
        // -map 0:a:0 显式选择第一条音频流，避免多音轨时的歧义
        return executeTranscode(ownerUserId, fileNodeId, videoItemId, ".aac",
                List.of("-vn", "-map", "0:a:0", "-c:a", "aac", "-b:a", "192k"),
                "音频提取");
    }

    /**
     * Web 端优化转码：视频流 copy（H264/H265）或转码 H264，音频转码 AAC，输出 faststart MP4。
     * faststart 将 moov atom 移到文件头部，浏览器可通过 HTTP range request 即时 seek。
     * 调用方负责删除返回的临时文件。
     */
    public Path transcodeToWebOptimized(UUID ownerUserId, UUID fileNodeId, UUID videoItemId, String sourceVideoCodec) {
        List<String> ffmpegArgs = new ArrayList<>();
        String normalizedCodec = sourceVideoCodec == null ? "" : sourceVideoCodec.trim().toLowerCase(Locale.ROOT);
        if (normalizedCodec.equals("h264") || normalizedCodec.equals("avc")
                || normalizedCodec.equals("hevc") || normalizedCodec.equals("h265")) {
            // 视频流直接 copy（零编码开销）
            ffmpegArgs.addAll(List.of("-map", "0:v", "-map", "0:a", "-c:v", "copy"));
        } else {
            // 视频编码不兼容 Web 端，转码为 H.264
            ffmpegArgs.addAll(List.of("-map", "0:v", "-map", "0:a",
                    "-c:v", "libx264", "-crf", "23", "-preset", "medium"));
        }
        // 音频统一转码为 AAC-LC
        ffmpegArgs.addAll(List.of("-c:a", "aac", "-b:a", "192k", "-ac", "2"));
        // faststart：moov atom 移到文件头部，支持 HTTP range request 即时 seek
        ffmpegArgs.addAll(List.of("-movflags", "faststart"));
        return executeTranscode(ownerUserId, fileNodeId, videoItemId, ".mp4",
                ffmpegArgs, "Web 优化转码");
    }

    /**
     * 单条内嵌字幕提取。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 源视频文件节点 ID
     * @param videoItemId 视频条目 ID
     * @param streamIndex 字幕流索引
     * @return WebVTT 临时文件，调用方负责删除
     */
    public Path extractSubtitleToWebVtt(UUID ownerUserId, UUID fileNodeId, UUID videoItemId, int streamIndex) {
        return extractSubtitlesToWebVtt(ownerUserId, fileNodeId, videoItemId, List.of(streamIndex))
                .stream()
                .findFirst()
                .map(ExtractedSubtitle::file)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.MEDIA_TRANSCODE_FAILED,
                        "字幕提取失败: streamIndex=" + streamIndex
                ));
    }

    /**
     * 一次暂存、批量提取多条内嵌字幕。
     *
     * <p>多轨视频若逐轨调用单条接口，每条轨道都会把整部影片从对象存储复制到本地；
     * 这里只暂存一次，所有轨道提取完成后统一清理。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 源视频文件节点 ID
     * @param videoItemId 视频条目 ID
     * @param streamIndexes 字幕流索引列表
     * @return 成功提取的轨道与临时文件；失败轨道已跳过
     */
    public List<ExtractedSubtitle> extractSubtitlesToWebVtt(
            UUID ownerUserId,
            UUID fileNodeId,
            UUID videoItemId,
            List<Integer> streamIndexes
    ) {
        if (streamIndexes == null || streamIndexes.isEmpty()) {
            return List.of();
        }
        requireFfmpeg("提取内嵌字幕");
        String internalUrl = resolveInput(ownerUserId, fileNodeId);
        Path staged = null;
        try {
            staged = stageLocalInput(ownerUserId, fileNodeId, internalUrl);
            String localInput = staged != null ? staged.toAbsolutePath().toString() : internalUrl;
            List<ExtractedSubtitle> extracted = new ArrayList<>(streamIndexes.size());
            for (int streamIndex : streamIndexes) {
                try {
                    extracted.add(new ExtractedSubtitle(
                            streamIndex,
                            extractSubtitleLocally(localInput, videoItemId, streamIndex)
                    ));
                } catch (RuntimeException exception) {
                    log.warn("字幕提取失败: videoItemId={}, streamIndex={}, errorType={}",
                            videoItemId, streamIndex, exception.getClass().getSimpleName());
                }
            }
            return extracted;
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED,
                    "字幕提取源暂存失败: " + exception.getMessage());
        } finally {
            deleteQuietly(staged);
        }
    }

    /**
     * 提取结果。
     *
     * @param streamIndex 字幕流索引
     * @param file WebVTT 临时文件
     */
    public record ExtractedSubtitle(int streamIndex, Path file) {
    }

    private Path extractSubtitleLocally(String input, UUID videoItemId, int streamIndex) {
        Path tempOutput = null;
        try {
            tempOutput = Files.createTempFile(
                    processingTempProperties.ensureSubdirectory("transcode"),
                    "subtitle-" + videoItemId + "-" + streamIndex,
                    ".vtt");
            List<String> args = List.of(
                    "-map", "0:" + streamIndex,
                    "-c:s", "webvtt",
                    tempOutput.toAbsolutePath().toString()
            );
            log.info("开始本地字幕提取: videoItemId={}, streamIndex={}", videoItemId, streamIndex);
            runLocalFfmpeg(ffmpegRuntime.localCommand(input, args), TRANSCODE_TIMEOUT, "字幕提取");
            log.info("字幕提取完成: videoItemId={}, streamIndex={}, size={}",
                    videoItemId, streamIndex, Files.size(tempOutput));
            return tempOutput;
        } catch (BusinessException exception) {
            deleteQuietly(tempOutput);
            throw exception;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            deleteQuietly(tempOutput);
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, "字幕提取执行被中断");
        } catch (Exception exception) {
            deleteQuietly(tempOutput);
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED,
                    "字幕提取执行失败: " + exception.getMessage());
        }
    }

    /**
     * 通用转码执行流程：源落到本地受控文件 → 转码 → 返回临时文件。
     *
     * @param ext          输出文件扩展名
     * @param ffmpegArgs   ffmpeg 参数（不含 -y -i input output）
     * @param logLabel     日志标签
     */
    private Path executeTranscode(
            UUID ownerUserId, UUID fileNodeId, UUID videoItemId,
            String ext, List<String> ffmpegArgs, String logLabel
    ) {
        requireFfmpeg(logLabel);
        String internalUrl = resolveInput(ownerUserId, fileNodeId);
        Path staged = null;
        try {
            staged = stageLocalInput(ownerUserId, fileNodeId, internalUrl);
            String localInput = staged != null ? staged.toAbsolutePath().toString() : internalUrl;
            return executeLocalTranscode(localInput, videoItemId, ext, ffmpegArgs, logLabel);
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED,
                    logLabel + "源暂存失败: " + exception.getMessage());
        } finally {
            deleteQuietly(staged);
        }
    }

    /**
     * 本地 ffmpeg 转码：输出直接落到后端临时目录。
     */
    private Path executeLocalTranscode(
            String input, UUID videoItemId, String ext, List<String> ffmpegArgs, String logLabel
    ) {
        Path tempOutput = null;
        try {
            tempOutput = Files.createTempFile(
                    processingTempProperties.ensureSubdirectory("transcode"),
                    "transcode-" + videoItemId,
                    ext);
            List<String> args = new ArrayList<>(ffmpegArgs);
            args.add(tempOutput.toAbsolutePath().toString());
            log.info("开始本地{}: videoItemId={}", logLabel, videoItemId);
            runLocalFfmpeg(ffmpegRuntime.localCommand(input, args), TRANSCODE_TIMEOUT, logLabel);
            log.info("本地{}完成: videoItemId={}, size={}", logLabel, videoItemId, Files.size(tempOutput));
            return tempOutput;
        } catch (BusinessException exception) {
            deleteQuietly(tempOutput);
            throw exception;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            deleteQuietly(tempOutput);
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, logLabel + "执行被中断");
        } catch (Exception exception) {
            deleteQuietly(tempOutput);
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED,
                    logLabel + "执行失败: " + exception.getMessage());
        }
    }

    private String resolveInput(UUID ownerUserId, UUID fileNodeId) {
        return sourceInputResolver.resolveLocalInput(ownerUserId, fileNodeId);
    }

    /**
     * 把非本地来源的内容落到受控临时文件，供本地 ffmpeg 以 file 协议读取。
     *
     * @return 本地临时文件；输入本来就是本地路径时返回 null，调用方直接使用原路径
     */
    private Path stageLocalInput(UUID ownerUserId, UUID fileNodeId, String input) throws IOException {
        if (!isHttpInput(input)) {
            return null;
        }
        Path staged = Files.createTempFile(
                processingTempProperties.ensureSubdirectory("transcode"), "input-", ".bin");
        try (FileContentStream content = fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId);
                InputStream stream = content.inputStream()) {
            Files.copy(stream, staged, StandardCopyOption.REPLACE_EXISTING);
            return staged;
        } catch (IOException | RuntimeException exception) {
            deleteQuietly(staged);
            throw exception;
        }
    }

    private boolean isHttpInput(String input) {
        if (input == null) {
            return false;
        }
        String lower = input.toLowerCase(Locale.ROOT);
        return lower.startsWith("http://") || lower.startsWith("https://");
    }

    private void requireFfmpeg(String operation) {
        if (ffmpegRuntime.isDisabled()) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE,
                    "ffmpeg 不可用，无法执行" + operation);
        }
    }

    private void runLocalFfmpeg(List<String> command, Duration timeout, String logLabel)
            throws IOException, InterruptedException {
        VideoProcessExecutor.Result result = processExecutor.execute(command, timeout);
        if (result.timedOut()) {
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, logLabel + "超时");
        }
        if (!result.succeeded()) {
            log.warn("本地 ffmpeg 执行失败: operation={}, exitCode={}, outputLength={}",
                    logLabel, result.exitCode(), result.output().length());
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED,
                    logLabel + "失败: exitCode=" + result.exitCode());
        }
    }

    private void deleteQuietly(Path path) {
        if (path == null) {
            return;
        }
        try {
            Files.deleteIfExists(path);
        } catch (IOException exception) {
            log.debug("删除转码临时文件失败: errorType={}", exception.getClass().getSimpleName());
        }
    }
}
