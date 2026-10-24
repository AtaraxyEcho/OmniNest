package com.omninest.modules.backdrop.service;

import com.omninest.modules.video.service.VideoProcessExecutor;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 背景视频首帧抽帧器。
 *
 * <p>使用本机 ffmpeg 直接读取 staging 文件；抽帧失败由调用方决定是否阻断业务。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class BackdropVideoThumbnailExtractor {

    /** 本地抽帧/探测只处理已落盘的 staging 文件，禁止媒体内嵌引用再出网。 */
    private static final String LOCAL_PROTOCOL_WHITELIST = "file,crypto,data";
    private static final Duration COMMAND_CHECK_TIMEOUT = Duration.ofSeconds(10);
    /** 编码名落库列长度上限，与 backdrop_assets.video_codec 保持一致。 */
    private static final int PROBE_CODEC_MAX_LENGTH = 32;

    private final VideoProcessExecutor processExecutor;

    private volatile Boolean localFfmpegAvailable;

    /**
     * 提取视频首帧为 JPEG 临时文件。
     *
     * @param stagingFile 上传 staging 本地文件
     * @param timeout 抽帧超时
     * @return 首帧 JPEG 临时文件;不可用或失败时为空
     */
    public Optional<Path> extractFirstFrame(Path stagingFile, Duration timeout) {
        if (stagingFile == null || !Files.isRegularFile(stagingFile)) {
            return Optional.empty();
        }
        try {
            if (isLocalFfmpegAvailable()) {
                return extractWithLocal(stagingFile, timeout);
            }
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("背景视频抽帧被中断: staging={}", stagingFile.getFileName());
        } catch (IOException ex) {
            log.warn("背景视频抽帧失败: staging={}, message={}", stagingFile.getFileName(), ex.getMessage());
        }
        return Optional.empty();
    }

    /**
     * 将视频缩放到壁纸播放用分辨率(最长边 ≤1920,高度 ≤1080),降低客户端解码压力。
     *
     * <p>当前无调用方,与 {@code BackdropAssetService.generateAndStorePlayback} 一并保留待 Web 兼容策略定稿。
     * 输入不做分辨率判断:只要本地 ffmpeg 可用就会重编码,因此调用方需自行决定是否值得跑。
     * ffmpeg 不可用、产物为空或执行失败时返回空,调用方回退使用原始文件。</p>
     *
     * @param stagingFile 上传 staging 本地文件
     * @param timeout 转码超时
     * @return 降分辨率 MP4 临时文件;失败或不可用时为空
     */
    public Optional<Path> scaleForWallpaperPlayback(Path stagingFile, Duration timeout) {
        if (stagingFile == null || !Files.isRegularFile(stagingFile)) {
            return Optional.empty();
        }
        if (!isLocalFfmpegAvailable()) {
            return Optional.empty();
        }
        Path output;
        try {
            output = Files.createTempFile("backdrop-playback-", ".mp4");
        } catch (IOException ex) {
            log.warn("壁纸播放衍生临时文件创建失败: {}", ex.getMessage());
            return Optional.empty();
        }
        try {
            List<String> command = new ArrayList<>();
            command.add("ffmpeg");
            command.add("-y");
            command.add("-protocol_whitelist");
            command.add(LOCAL_PROTOCOL_WHITELIST);
            command.add("-i");
            command.add(stagingFile.toAbsolutePath().toString());
            command.add("-vf");
            command.add("scale='min(1920,iw)':-2");
            command.add("-c:v");
            command.add("libx264");
            command.add("-preset");
            command.add("veryfast");
            command.add("-crf");
            command.add("23");
            command.add("-an");
            command.add("-movflags");
            command.add("+faststart");
            command.add(output.toAbsolutePath().toString());
            VideoProcessExecutor.Result result = processExecutor.execute(command, timeout);
            if (result.succeeded() && Files.isRegularFile(output) && Files.size(output) > 0) {
                return Optional.of(output);
            }
            Files.deleteIfExists(output);
            return Optional.empty();
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            deleteQuietly(output);
            return Optional.empty();
        } catch (IOException ex) {
            log.warn("壁纸播放衍生转码失败: {}", ex.getMessage());
            deleteQuietly(output);
            return Optional.empty();
        }
    }

    /**
     * 探测视频首流编码名,用于判定 Web 客户端是否可解码。
     *
     * @param stagingFile 上传 staging 本地文件
     * @param timeout 探测超时
     * @return ffprobe 输出的编码名;不可用、超时或无输出时为空
     */
    public Optional<String> probeVideoCodec(Path stagingFile, Duration timeout) {
        if (stagingFile == null || !Files.isRegularFile(stagingFile)) {
            return Optional.empty();
        }
        if (!isLocalFfmpegAvailable()) {
            return Optional.empty();
        }
        try {
            VideoProcessExecutor.Result result = processExecutor.execute(List.of(
                    "ffprobe",
                    "-v", "error",
                    "-protocol_whitelist", LOCAL_PROTOCOL_WHITELIST,
                    "-select_streams", "v:0",
                    "-show_entries", "stream=codec_name",
                    "-of", "default=noprint_wrappers=1:nokey=1",
                    stagingFile.toAbsolutePath().toString()
            ), timeout);
            if (!result.succeeded()) {
                return Optional.empty();
            }
            String codec = result.output().lines()
                    .map(String::trim)
                    .filter(line -> !line.isEmpty())
                    .findFirst()
                    .orElse("");
            return codec.isEmpty()
                    ? Optional.empty()
                    : Optional.of(codec.substring(0, Math.min(codec.length(), PROBE_CODEC_MAX_LENGTH)));
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            log.warn("壁纸视频编码探测被中断: file={}", stagingFile.getFileName());
            return Optional.empty();
        } catch (IOException | RuntimeException ex) {
            log.warn("壁纸视频编码探测失败: message={}", ex.getMessage());
            return Optional.empty();
        }
    }

    private void deleteQuietly(Path file) {
        try {
            Files.deleteIfExists(file);
        } catch (IOException ex) {
            log.debug("临时文件清理失败: {}", ex.getMessage());
        }
    }

    private Optional<Path> extractWithLocal(Path stagingFile, Duration timeout)            throws IOException, InterruptedException {
        Path output = Files.createTempFile("backdrop-frame-", ".jpg");
        try {
            List<String> command = new ArrayList<>();
            command.add("ffmpeg");
            command.add("-y");
            command.add("-protocol_whitelist");
            command.add(LOCAL_PROTOCOL_WHITELIST);
            command.add("-ss");
            command.add("00:00:01");
            command.add("-i");
            command.add(stagingFile.toAbsolutePath().toString());
            command.add("-frames:v");
            command.add("1");
            command.add("-q:v");
            command.add("2");
            command.add(output.toAbsolutePath().toString());
            VideoProcessExecutor.Result result = processExecutor.execute(command, timeout);
            if (result.succeeded() && Files.isRegularFile(output) && Files.size(output) > 0) {
                return Optional.of(output);
            }
            Files.deleteIfExists(output);
            return Optional.empty();
        } catch (IOException | InterruptedException ex) {
            Files.deleteIfExists(output);
            throw ex;
        }
    }

    private boolean isLocalFfmpegAvailable() {
        Boolean cached = localFfmpegAvailable;
        if (cached != null) {
            return cached;
        }
        boolean available = tryCommand("ffmpeg", "-version");
        localFfmpegAvailable = available;
        return available;
    }

    private boolean tryCommand(String... command) {
        try {
            return processExecutor.execute(List.of(command), COMMAND_CHECK_TIMEOUT).succeeded();
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            return false;
        } catch (IOException ex) {
            return false;
        }
    }
}
