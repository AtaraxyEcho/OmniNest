package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.processing.TempStagingPort;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.reader.config.ReaderArchiveLimitsProperties;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * 漫画来源归档本地缓存测试。
 *
 * @author OmniNest
 */
class ReaderComicArchiveCacheTest {

    @TempDir
    Path tempDir;

    @Test
    void secondAcquireReusesStagedArchiveInsteadOfDownloadingAgain() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        byte[] archiveBytes = createZip();
        FileQueryService fileQueryService = mock(FileQueryService.class);
        when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(archiveBytes),
                        "comic.cbz",
                        archiveBytes.length,
                        "application/vnd.comicbook+zip"
                ));
        ReaderComicArchiveCache cache = new ReaderComicArchiveCache(
                fileQueryService,
                new ReaderArchiveSafetyPolicy(new ReaderArchiveLimitsProperties()),
                stagingPort()
        );

        Path first = cache.acquire(ownerUserId, fileNodeId, archiveBytes.length, 0L);
        Path second = cache.acquire(ownerUserId, fileNodeId, archiveBytes.length, 0L);

        assertThat(second).isEqualTo(first);
        assertThat(Files.readAllBytes(first)).isEqualTo(archiveBytes);
        verify(fileQueryService, times(1)).openOwnedFileContent(ownerUserId, fileNodeId);
    }

    @Test
    void acquireRestagesWhenCachedFileDisappeared() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        byte[] archiveBytes = createZip();
        FileQueryService fileQueryService = mock(FileQueryService.class);
        when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(archiveBytes),
                        "comic.cbz",
                        archiveBytes.length,
                        "application/vnd.comicbook+zip"
                ));
        ReaderComicArchiveCache cache = new ReaderComicArchiveCache(
                fileQueryService,
                new ReaderArchiveSafetyPolicy(new ReaderArchiveLimitsProperties()),
                stagingPort()
        );
        Path first = cache.acquire(ownerUserId, fileNodeId, archiveBytes.length, 0L);
        Files.delete(first);

        Path second = cache.acquire(ownerUserId, fileNodeId, archiveBytes.length, 0L);

        assertThat(second).isNotEqualTo(first);
        assertThat(Files.isRegularFile(second)).isTrue();
        verify(fileQueryService, times(2)).openOwnedFileContent(ownerUserId, fileNodeId);
    }

    @Test
    void openFallsBackToGb18030WhenEntryNamesAreNotUtf8() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        byte[] archiveBytes = createZip(
                "页面/1.jpg",
                "image".getBytes(StandardCharsets.UTF_8),
                Charset.forName("GBK")
        );
        FileQueryService fileQueryService = mock(FileQueryService.class);
        when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(archiveBytes),
                        "comic.cbz",
                        archiveBytes.length,
                        "application/vnd.comicbook+zip"
                ));
        ReaderComicArchiveCache cache = new ReaderComicArchiveCache(
                fileQueryService,
                new ReaderArchiveSafetyPolicy(new ReaderArchiveLimitsProperties()),
                stagingPort()
        );

        try (ReaderComicArchiveCache.CachedArchive archive = cache.open(
                ownerUserId, fileNodeId, archiveBytes.length, 0L)) {
            ZipEntry entry = archive.findEntry("页面/1.jpg", 0);
            assertThat(entry).isNotNull();
            try (InputStream input = archive.openEntry(entry)) {
                assertThat(input.readAllBytes()).isEqualTo("image".getBytes(StandardCharsets.UTF_8));
            }
        }
    }

    private TempStagingPort stagingPort() {
        return new TempStagingPort() {
            @Override
            public Path createTempFile(String segment, String prefix, String suffix) {
                Path directory = ensureDirectory(segment);
                try {
                    return Files.createTempFile(directory, prefix, suffix);
                } catch (IOException exception) {
                    throw new UncheckedIOException(exception);
                }
            }

            @Override
            public Path ensureDirectory(String segment) {
                Path directory = tempDir.resolve(segment);
                try {
                    Files.createDirectories(directory);
                    return directory;
                } catch (IOException exception) {
                    throw new UncheckedIOException(exception);
                }
            }

            @Override
            public void deleteQuietly(Path path) {
                if (path == null) {
                    return;
                }
                try {
                    Files.deleteIfExists(path);
                } catch (IOException exception) {
                    throw new UncheckedIOException(exception);
                }
            }
        };
    }

    private byte[] createZip() throws IOException {
        return createZip("pages/1.jpg", "image".getBytes(StandardCharsets.UTF_8), StandardCharsets.UTF_8);
    }

    private byte[] createZip(String entryName, byte[] bytes, Charset charset) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(output, charset)) {
            zip.putNextEntry(new ZipEntry(entryName));
            zip.write(bytes);
            zip.closeEntry();
        }
        return output.toByteArray();
    }
}
