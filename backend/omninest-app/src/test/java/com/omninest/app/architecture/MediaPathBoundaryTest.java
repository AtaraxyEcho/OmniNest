package com.omninest.app.architecture;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 限制 omninest-media 业务代码直接依赖 {@code java.nio.file.Path}。
 *
 * <p>白名单仅允许暂存/派生处理/Lucene 索引/路径安全校验类；其余业务服务
 * 必须通过 File 内容接口或 {@code TempStagingPort} 访问临时文件。</p>
 *
 * @author OmniNest
 */
class MediaPathBoundaryTest {

    private static final Pattern PATH_IMPORT = Pattern.compile(
            "^import java\\.nio\\.file\\.(Path|Files);",
            Pattern.MULTILINE
    );

    /** 允许直接使用 Path/Files 的暂存、派生处理、索引与路径安全类。 */
    private static final Set<String> ALLOWED_PATH_SOURCES = Set.of(
            "omninest-media/src/main/java/com/omninest/modules/music/service/MusicCoverThumbnailService.java",
            "omninest-media/src/main/java/com/omninest/modules/music/service/MusicAdminService.java",
            "omninest-media/src/main/java/com/omninest/modules/video/service/VideoTranscodeService.java",
            "omninest-media/src/main/java/com/omninest/modules/video/service/TranscodeExecutionService.java",
            "omninest-media/src/main/java/com/omninest/modules/video/service/VideoProbeService.java",
            "omninest-media/src/main/java/com/omninest/modules/video/service/MoviePlaybackService.java",
            "omninest-media/src/main/java/com/omninest/modules/video/service/VideoLibrarySourceService.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoInputGuard.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoSourceFileService.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoThumbnailService.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoEditService.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoRawPreviewService.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoAdminService.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoBatchService.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoAiService.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoMotionVideoService.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoMotionTrailerScanner.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/service/GeonamesImportService.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/search/PhotoSearchIndexService.java",
            "omninest-media/src/main/java/com/omninest/modules/reader/service/ReaderImportService.java",
            "omninest-media/src/main/java/com/omninest/modules/reader/service/ReaderItemService.java",
            "omninest-media/src/main/java/com/omninest/modules/reader/service/ReaderEpubArchiveStager.java",
            "omninest-media/src/main/java/com/omninest/modules/reader/service/ReaderArchiveSafetyPolicy.java",
            "omninest-media/src/main/java/com/omninest/modules/reader/service/ReaderFileDetector.java",
            "omninest-media/src/main/java/com/omninest/modules/reader/service/EpubArchive.java",
            "omninest-media/src/main/java/com/omninest/modules/backdrop/service/BackdropAssetService.java",
            "omninest-media/src/main/java/com/omninest/modules/backdrop/service/BackdropVideoThumbnailExtractor.java"
    );

    @Test
    void mediaProductionSourcesOnlyImportPathInAllowlist() throws IOException {
        Path root = findBackendRoot();
        Path mediaRoot = root.resolve("omninest-media/src/main/java");
        assertTrue(Files.isDirectory(mediaRoot), "omninest-media 主源码目录不存在");
        Set<String> violations = new HashSet<>();
        try (Stream<Path> files = Files.walk(mediaRoot)) {
            files.filter(path -> path.toString().endsWith(".java"))
                    .forEach(path -> {
                        String relative = normalize(root.relativize(path));
                        try {
                            String source = Files.readString(path);
                            if (PATH_IMPORT.matcher(source).find() && !ALLOWED_PATH_SOURCES.contains(relative)) {
                                violations.add(relative);
                            }
                        } catch (IOException exception) {
                            throw new IllegalStateException("读取源码失败: " + relative, exception);
                        }
                    });
        }
        assertEquals(Set.of(), violations, "omninest-media 禁止业务类直接 import java.nio.file.Path/Files");
    }

    @Test
    void allowlistEntriesStillExist() throws IOException {
        Path root = findBackendRoot();
        List<String> missing = ALLOWED_PATH_SOURCES.stream()
                .filter(entry -> !Files.isRegularFile(root.resolve(entry)))
                .toList();
        assertEquals(List.of(), missing, "Path 白名单条目必须对应仍存在的源文件");
    }

    private Path findBackendRoot() {
        Path current = Path.of("").toAbsolutePath();
        while (current != null) {
            if (Files.isDirectory(current.resolve("omninest-media"))
                    && Files.isRegularFile(current.resolve("pom.xml"))) {
                return current;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("未找到 backend 根目录");
    }

    private String normalize(Path path) {
        return path.toString().replace('\\', '/');
    }
}
