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
 * FFmpeg 转码服务：优先在后端容器本地执行，缺少本地 ffmpeg 时回退到
 * {@code docker exec omninest-ffmpeg}。
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class VideoTranscodeService {
    private static final String DOCKER_TRANSCODE_DIR = "/tmp/transcode";
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

    private static final Duration TRANSCODE_TIMEOUT = Duration.ofMinutes(180);
    private static final Duration COPY_TIMEOUT = Duration.ofMinutes(30);
    private static final Duration CLEANUP_TIMEOUT = Duration.ofMinutes(5);

    /**
     * 在 Docker 容器内执行 H265 转码，返回转码后文件的本地临时路径。
     * 调用方负责删除返回的临时文件。
     */
    public Path transcodeToH265(UUID ownerUserId, UUID fileNodeId, UUID videoItemId) {
        return executeTranscode(ownerUserId, fileNodeId, videoItemId, "-h265", ".mp4",
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
        return executeTranscode(ownerUserId, fileNodeId, videoItemId, "-aac", ".mp4",
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
        return executeTranscode(ownerUserId, fileNodeId, videoItemId, "-aac-only", ".aac",
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
        return executeTranscode(ownerUserId, fileNodeId, videoItemId, "-web", ".mp4",
                ffmpegArgs, "Web 优化转码");
    }

    /**
     * 提取内嵌字幕流为 WebVTT 格式。
     * ffmpeg 从 MinIO 读取源视频，提取指定字幕流并转换为 WebVTT。
     * 调用方负责删除返回的临时文件。
     */
    public Path extractSubtitleToWebVtt(UUID ownerUserId, UUID fileNodeId, UUID videoItemId, int streamIndex) {
        String internalUrl = resolveInput(ownerUserId, fileNodeId);
        if (ffmpegRuntime.isDisabled()) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE,
                    "ffmpeg 不可用，无法提取内嵌字幕");
        }
        if (!ffmpegRuntime.isDocker()) {
            // 本地 ffmpeg 必须吃受控本地文件：预签名 URL 交给本地进程后，
            // 恶意媒体内嵌的远程引用（HLS 分片、concat）会绕开出站地址校验。
            Path staged = null;
            try {
                staged = stageLocalInput(ownerUserId, fileNodeId, internalUrl);
                String localInput = staged != null ? staged.toAbsolutePath().toString() : internalUrl;
                return extractSubtitleLocally(localInput, videoItemId, streamIndex);
            } catch (IOException exception) {
                throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED,
                        "字幕提取源暂存失败: " + exception.getMessage());
            } finally {
                deleteQuietly(staged);
            }
        }

        String containerDir = DOCKER_TRANSCODE_DIR + "/" + videoItemId + "-sub-" + streamIndex;
        String containerOutput = containerDir + "/subtitle.vtt";

        try {
            exec("mkdir", "-p", containerDir);

            log.info("开始字幕提取: videoItemId={}, streamIndex={}", videoItemId, streamIndex);
            List<String> cmd = new ArrayList<>(List.of(
                    "ffmpeg", "-y",
                    "-i", internalUrl,
                    "-map", "0:" + streamIndex,
                    "-c:s", "webvtt",
                    containerOutput
            ));
            log.debug("ffmpeg 字幕提取命令已准备: videoItemId={}, argumentCount={}", videoItemId, cmd.size());
            exec(cmd.toArray(new String[0]));
            log.info("字幕提取 ffmpeg 完成: videoItemId={}, streamIndex={}", videoItemId, streamIndex);

            Path tempOutput = Files.createTempFile(
                    processingTempProperties.ensureSubdirectory("transcode"),
                    "subtitle-" + videoItemId + "-" + streamIndex,
                    ".vtt");
            VideoProcessExecutor.Result copyResult = copyFromContainer(containerOutput, tempOutput);
            if (copyResult.timedOut()) {
                Files.deleteIfExists(tempOutput);
                throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, "字幕提取结果复制超时");
            }
            if (!copyResult.succeeded()) {
                Files.deleteIfExists(tempOutput);
                throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, "字幕提取结果复制失败");
            }

            log.info("字幕提取完成: videoItemId={}, streamIndex={}, size={}",
                    videoItemId, streamIndex, Files.size(tempOutput));
            return tempOutput;
        } catch (BusinessException e) {
            throw e;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, "字幕提取执行被中断");
        } catch (Exception e) {
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, "字幕提取执行失败: " + e.getMessage());
        } finally {
            cleanupContainerDirectory(containerDir);
        }
    }

    /**
     * 本地 ffmpeg 字幕提取：直接写临时文件，不需要 docker cp/清理容器目录。
     */
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
     * 通用转码执行流程：ffmpeg 直接从 MinIO URL 读取源文件 → 转码 → 复制到宿主机 → 清理。
     *
     * @param suffix       容器目录后缀，区分不同转码类型
     * @param ext          输出文件扩展名
     * @param ffmpegArgs   ffmpeg 参数（不含 -y -i input output）
     * @param logLabel     日志标签
     */
    private Path executeTranscode(
            UUID ownerUserId, UUID fileNodeId, UUID videoItemId,
            String suffix, String ext, List<String> ffmpegArgs, String logLabel
    ) {
        if (ffmpegRuntime.isDisabled()) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE,
                    "ffmpeg 不可用，无法执行" + logLabel);
        }
        String internalUrl = resolveInput(ownerUserId, fileNodeId);
        if (!ffmpegRuntime.isDocker()) {
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

        String containerDir = DOCKER_TRANSCODE_DIR + "/" + videoItemId + suffix;
        String containerOutput = containerDir + "/output" + ext;

        try {
            exec("mkdir", "-p", containerDir);

            log.info("开始{}: videoItemId={}, fileNodeId={}", logLabel, videoItemId, fileNodeId);
            List<String> cmd = new ArrayList<>();
            cmd.add("ffmpeg");
            cmd.add("-y");
            cmd.add("-i");
            cmd.add(internalUrl);
            cmd.addAll(ffmpegArgs);
            cmd.add(containerOutput);
            log.debug("ffmpeg 转码命令已准备: videoItemId={}, argumentCount={}", videoItemId, cmd.size());
            exec(cmd.toArray(new String[0]));
            log.info("{} ffmpeg 完成: videoItemId={}", logLabel, videoItemId);

            log.info("{} 复制到宿主机: videoItemId={}", logLabel, videoItemId);
            Path tempOutput = Files.createTempFile(
                    processingTempProperties.ensureSubdirectory("transcode"),
                    "transcode-" + videoItemId,
                    ext);
            VideoProcessExecutor.Result copyResult = copyFromContainer(containerOutput, tempOutput);
            if (copyResult.timedOut()) {
                Files.deleteIfExists(tempOutput);
                throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, logLabel + "结果复制超时");
            }
            if (!copyResult.succeeded()) {
                Files.deleteIfExists(tempOutput);
                throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, logLabel + "结果复制失败");
            }

            log.info("{}完成: videoItemId={}, size={}", logLabel, videoItemId, Files.size(tempOutput));
            return tempOutput;
        } catch (BusinessException e) {
            throw e;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, logLabel + "执行被中断");
        } catch (Exception e) {
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, logLabel + "执行失败: " + e.getMessage());
        } finally {
            cleanupContainerDirectory(containerDir);
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
        return ffmpegRuntime.isDocker()
                ? sourceInputResolver.resolveDockerInput(ownerUserId, fileNodeId)
                : sourceInputResolver.resolveLocalInput(ownerUserId, fileNodeId);
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

    private void exec(String... command) throws IOException, InterruptedException {
        List<String> dockerCommand = new ArrayList<>(command.length + 3);
        dockerCommand.add("docker");
        dockerCommand.add("exec");
        dockerCommand.add(VideoFfmpegRuntime.DOCKER_CONTAINER);
        dockerCommand.addAll(List.of(command));

        VideoProcessExecutor.Result result = processExecutor.execute(dockerCommand, resolveTimeout(command));
        if (result.timedOut()) {
            throw new IOException("Docker 命令超时: operation=" + resolveOperation(command));
        }
        if (!result.succeeded()) {
            log.warn("Docker 命令失败: operation={}, exitCode={}, outputTruncated={}, outputLength={}",
                    resolveOperation(command), result.exitCode(), result.outputTruncated(), result.output().length());
            throw new IOException("Docker 命令失败: operation=" + resolveOperation(command)
                    + ", exitCode=" + result.exitCode());
        }
    }

    private VideoProcessExecutor.Result copyFromContainer(String containerOutput, Path tempOutput)
            throws IOException, InterruptedException {
        return processExecutor.execute(List.of(
                "docker", "cp",
                VideoFfmpegRuntime.DOCKER_CONTAINER + ":" + containerOutput,
                tempOutput.toAbsolutePath().toString()
        ), COPY_TIMEOUT);
    }

    private void cleanupContainerDirectory(String containerDir) {
        try {
            VideoProcessExecutor.Result result = processExecutor.execute(List.of(
                    "docker", "exec", VideoFfmpegRuntime.DOCKER_CONTAINER,
                    "rm", "-rf", containerDir
            ), CLEANUP_TIMEOUT);
            if (!result.succeeded()) {
                log.debug("Docker 转码目录清理未完成: timedOut={}, exitCode={}",
                        result.timedOut(), result.exitCode());
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (IOException e) {
            log.debug("Docker 转码目录清理失败: {}", e.getMessage());
        }
    }

    private Duration resolveTimeout(String[] command) {
        if (command.length > 0 && "ffmpeg".equals(command[0])) {
            return TRANSCODE_TIMEOUT;
        }
        return CLEANUP_TIMEOUT;
    }

    private String resolveOperation(String[] command) {
        if (command.length == 0) {
            return "unknown";
        }
        return command[0];
    }
}
