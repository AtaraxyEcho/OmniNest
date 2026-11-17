package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.reader.config.ReaderArchiveLimitsProperties;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.Test;

/**
 * Reader 压缩包路径、容量和压缩比限制测试。
 *
 * @author OmniNest
 */
class ReaderArchiveSafetyPolicyTest {

    private final ReaderArchiveLimitsProperties properties = new ReaderArchiveLimitsProperties();
    private final ReaderArchiveSafetyPolicy policy = new ReaderArchiveSafetyPolicy(properties);

    @Test
    void validateZipFileRejectsPathTraversalEntry() throws Exception {
        Path archive = createZip(Map.of("../outside.jpg", new byte[]{1}));
        try (ZipFile zipFile = new ZipFile(archive.toFile())) {
            assertThatThrownBy(() -> policy.validateZipFile(zipFile))
                    .isInstanceOf(BusinessException.class)
                    .hasMessage("压缩包条目路径越界");
        } finally {
            Files.deleteIfExists(archive);
        }
    }

    @Test
    void validateZipFileRejectsEntryCountLimit() throws Exception {
        properties.setMaxEntries(1);
        Path archive = createZip(new LinkedHashMap<>(Map.of(
                "page-1.jpg", new byte[]{1, 2, 3},
                "page-2.jpg", new byte[]{4, 5, 6}
        )));
        try (ZipFile zipFile = new ZipFile(archive.toFile())) {
            assertThatThrownBy(() -> policy.validateZipFile(zipFile))
                    .isInstanceOf(BusinessException.class)
                    .hasMessage("压缩包条目数量超出限制");
        } finally {
            Files.deleteIfExists(archive);
        }
    }

    @Test
    void validateZipFileRejectsTotalUncompressedSizeLimit() throws Exception {
        properties.setMaxTotalUncompressedBytes(5);
        Path archive = createZip(new LinkedHashMap<>(Map.of(
                "page-1.jpg", new byte[]{1, 2, 3},
                "page-2.jpg", new byte[]{4, 5, 6}
        )));
        try (ZipFile zipFile = new ZipFile(archive.toFile())) {
            assertThatThrownBy(() -> policy.validateZipFile(zipFile))
                    .isInstanceOf(BusinessException.class)
                    .hasMessage("压缩包解压后总大小超出限制");
        } finally {
            Files.deleteIfExists(archive);
        }
    }

    @Test
    void validateZipFileRejectsExcessiveCompressionRatio() throws Exception {
        properties.setCompressionRatioCheckThresholdBytes(1);
        properties.setMaxCompressionRatio(2.0);
        Path archive = createZip(Map.of("page.jpg", new byte[4096]));
        try (ZipFile zipFile = new ZipFile(archive.toFile())) {
            assertThatThrownBy(() -> policy.validateZipFile(zipFile))
                    .isInstanceOf(BusinessException.class)
                    .hasMessage("压缩包条目压缩比超出限制");
        } finally {
            Files.deleteIfExists(archive);
        }
    }

    @Test
    void streamingGuardRejectsUnknownEntryThatExceedsOperationLimit() {
        ReaderArchiveSafetyPolicy.ArchiveReadSession session = policy.newReadSession();
        ReaderArchiveSafetyPolicy.EntryReadGuard guard = session.beginEntry(
                new ZipEntry("page.jpg"),
                3
        );

        assertThatThrownBy(() -> guard.recordBytes(4))
                .isInstanceOf(BusinessException.class)
                .hasMessage("压缩包条目大小超出限制");
    }

    @Test
    void copyArchiveRejectsDeclaredFileThatExceedsLimit() throws Exception {
        properties.setMaxArchiveBytes(3);
        Path destination = Files.createTempFile("omninest-reader-archive-copy-test-", ".zip");
        try {
            assertThatThrownBy(() -> policy.copyArchive(
                    new ByteArrayInputStream(new byte[]{1, 2, 3, 4}),
                    destination,
                    4
            ))
                    .isInstanceOf(BusinessException.class)
                    .hasMessage("压缩文件大小超出限制");
        } finally {
            Files.deleteIfExists(destination);
        }
    }

    @Test
    void epubArchiveReadsValidatedSmallEntries() throws Exception {
        Path archive = createZip(Map.of(
                "META-INF/container.xml",
                "<container>ok</container>".getBytes(StandardCharsets.UTF_8)
        ));
        try (EpubArchive epubArchive = new EpubArchive(archive, policy)) {
            assertThat(epubArchive.readSmallText("META-INF/container.xml"))
                    .isEqualTo("<container>ok</container>");
        } finally {
            Files.deleteIfExists(archive);
        }
    }

    private Path createZip(Map<String, byte[]> entries) throws Exception {
        Path archive = Files.createTempFile("omninest-reader-archive-test-", ".zip");
        try (ZipOutputStream output = new ZipOutputStream(Files.newOutputStream(archive))) {
            for (Map.Entry<String, byte[]> entry : entries.entrySet()) {
                output.putNextEntry(new ZipEntry(entry.getKey()));
                output.write(entry.getValue());
                output.closeEntry();
            }
        }
        return archive;
    }
}
