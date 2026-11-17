package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.reader.config.ReaderArchiveLimitsProperties;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.Test;

/**
 * 漫画 ZIP 归档解析测试。
 *
 * @author OmniNest
 */
class ReaderComicArchiveParserTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    @Test
    void parseEntriesFallsBackToGb18030ForNonUtf8EntryNames() throws Exception {
        byte[] archiveBytes = createZip("页面/1.jpg", "image".getBytes(StandardCharsets.UTF_8),
                Charset.forName("GBK"));
        FileQueryService fileQueryService = mock(FileQueryService.class);
        when(fileQueryService.openOwnedFileContent(OWNER_ID, FILE_NODE_ID))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(archiveBytes),
                        "comic.cbz",
                        archiveBytes.length,
                        "application/vnd.comicbook+zip"
                ));
        ReaderComicArchiveParser parser = new ReaderComicArchiveParser(
                fileQueryService,
                new ReaderArchiveSafetyPolicy(new ReaderArchiveLimitsProperties())
        );

        List<ReaderComicArchiveParser.ImageEntry> entries = parser.parseEntries(fileDescriptor(archiveBytes.length));

        assertThat(entries).singleElement().satisfies(entry -> {
            assertThat(entry.name()).isEqualTo("页面/1.jpg");
            assertThat(entry.entryIndex()).isZero();
        });
    }

    @Test
    void extractCoverFallsBackToGb18030ForNonUtf8EntryNames() throws Exception {
        byte[] imageBytes = "image".getBytes(StandardCharsets.UTF_8);
        byte[] archiveBytes = createZip("封面.jpg", imageBytes, Charset.forName("GBK"));
        FileQueryService fileQueryService = mock(FileQueryService.class);
        when(fileQueryService.openOwnedFileContent(OWNER_ID, FILE_NODE_ID))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(archiveBytes),
                        "comic.cbz",
                        archiveBytes.length,
                        "application/vnd.comicbook+zip"
                ));
        ReaderComicArchiveParser parser = new ReaderComicArchiveParser(
                fileQueryService,
                new ReaderArchiveSafetyPolicy(new ReaderArchiveLimitsProperties())
        );
        FileDescriptor descriptor = fileDescriptor(archiveBytes.length);
        ReaderComicArchiveParser.ImageEntry cover =
                new ReaderComicArchiveParser.ImageEntry("封面.jpg", imageBytes.length, 0, 0, 0);

        byte[] extracted = parser.extractCover(descriptor, cover).content();

        assertThat(extracted).isEqualTo(imageBytes);
    }

    private FileDescriptor fileDescriptor(long sizeBytes) {
        return new FileDescriptor(
                FILE_NODE_ID,
                OWNER_ID,
                null,
                "FILE",
                "comic.cbz",
                "/comic.cbz",
                "application/vnd.comicbook+zip",
                sizeBytes,
                null,
                "UPLOAD",
                false,
                false,
                SpaceType.PERSONAL,
                OWNER_ID,
                Instant.EPOCH,
                Instant.EPOCH
        );
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
