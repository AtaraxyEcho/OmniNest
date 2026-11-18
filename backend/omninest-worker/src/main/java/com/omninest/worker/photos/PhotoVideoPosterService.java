package com.omninest.worker.photos;

import com.omninest.common.processing.TempStagingPort;
import com.omninest.modules.file.service.FileProbeSourceService;
import com.omninest.modules.file.service.MediaProbeSourceStager;
import com.omninest.modules.photos.service.PhotoThumbnailService;
import com.omninest.modules.video.service.VideoFfmpegRuntime;
import com.omninest.modules.video.service.VideoProcessExecutor;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 从 Photos 视频文件中提取一帧作为网格封面。
 *
 * <p>输入复用文件模块的有界探测暂存，避免为生成一张封面把大型视频完整复制到临时卷。</p>
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoVideoPosterService {

    private static final Duration FRAME_TIMEOUT = Duration.ofSeconds(45);
    private static final Duration PROBE_TIMEOUT = Duration.ofSeconds(15);
    private static final Pattern DIMENSIONS = Pattern.compile("^(\\d{1,5})x(\\d{1,5})$");
    private static final Set<String> VIDEO_EXTENSIONS = Set.of(
            "mp4", "mkv", "webm", "mov", "m4v", "avi", "flv", "wmv", "ts", "m2ts");

    private final FileProbeSourceService fileProbeSourceService;
    private final PhotoThumbnailService photoThumbnailService;
    private final VideoFfmpegRuntime ffmpegRuntime;
    private final VideoProcessExecutor processExecutor;
    private final TempStagingPort tempStagingPort;

    public static boolean supportsVideoFileName(String fileName) {
        if (fileName == null) {
            return false;
        }
        int dot = fileName.lastIndexOf('.');
        return dot >= 0 && VIDEO_EXTENSIONS.contains(
                fileName.substring(dot + 1).toLowerCase(Locale.ROOT));
    }

    /** 提取封面并写入 Photos 使用的标准派生缩略图槽位。 */
    public VideoPoster generateAndStore(UUID ownerUserId, UUID fileNodeId) {
        if (ffmpegRuntime.isDisabled()) {
            return null;
        }
        Optional<MediaProbeSourceStager.StagedSource> staged =
                fileProbeSourceService.stageOwned(ownerUserId, fileNodeId);
        if (staged.isEmpty()) {
            return null;
        }
        Path poster = null;
        try (var source = staged.get()) {
            Dimensions dimensions = probeDimensions(source.path());
            poster = tempStagingPort.createTempFile(
                    "photo-video-poster", "omninest-photo-video-poster-", ".jpg");
            if (!extractFrame(source.path(), poster, "00:00:01.000")
                    && !extractFrame(source.path(), poster, "00:00:00.000")) {
                log.info("视频封面帧不可用: fileNodeId={}", fileNodeId);
                return null;
            }
            UUID coverFileId = photoThumbnailService.generateAndStoreFile(
                    ownerUserId, fileNodeId, poster, "video-poster.jpg");
            return coverFileId == null
                    ? null
                    : new VideoPoster(coverFileId,
                            dimensions == null ? null : dimensions.width(),
                            dimensions == null ? null : dimensions.height());
        } catch (IOException | InterruptedException exception) {
            if (exception instanceof InterruptedException) {
                Thread.currentThread().interrupt();
            }
            log.warn("视频封面提取失败: fileNodeId={}, errorType={}",
                    fileNodeId, exception.getClass().getSimpleName());
            return null;
        } finally {
            tempStagingPort.deleteQuietly(poster);
        }
    }

    private Dimensions probeDimensions(Path source) {
        List<String> command = List.of(
                "ffprobe",
                "-v", "error",
                "-protocol_whitelist", "file,crypto,data",
                "-select_streams", "v:0",
                "-show_entries", "stream=width,height",
                "-of", "csv=s=x:p=0",
                source.toAbsolutePath().toString()
        );
        try {
            VideoProcessExecutor.Result result = processExecutor.execute(command, PROBE_TIMEOUT);
            if (!result.succeeded()) {
                return null;
            }
            var matcher = DIMENSIONS.matcher(result.output().trim());
            if (!matcher.matches()) {
                return null;
            }
            int width = Integer.parseInt(matcher.group(1));
            int height = Integer.parseInt(matcher.group(2));
            return width > 0 && height > 0 ? new Dimensions(width, height) : null;
        } catch (IOException exception) {
            return null;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return null;
        }
    }

    private boolean extractFrame(Path source, Path poster, String timestamp)
            throws IOException, InterruptedException {
        List<String> args = List.of(
                "-ss", timestamp,
                "-frames:v", "1",
                "-vf", "scale=1024:1024:force_original_aspect_ratio=decrease",
                "-q:v", "3",
                poster.toAbsolutePath().toString()
        );
        VideoProcessExecutor.Result result = processExecutor.execute(
                ffmpegRuntime.localCommand(source.toAbsolutePath().toString(), args),
                FRAME_TIMEOUT
        );
        return result.succeeded() && Files.isRegularFile(poster) && Files.size(poster) > 0;
    }

    public record VideoPoster(UUID coverFileId, Integer width, Integer height) {
    }

    private record Dimensions(int width, int height) {
    }
}
