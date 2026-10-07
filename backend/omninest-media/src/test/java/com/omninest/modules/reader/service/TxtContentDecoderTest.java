package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileQueryService;
import java.io.ByteArrayInputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * TXT 解码游标测试。
 *
 * <p>章节清单与按章正文都建立在这套偏移之上，因此这里逐项钉住行终止符计数、
 * BOM 处理与字符数口径，任何一处变化都会让服务端偏移与文本错位。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class TxtContentDecoderTest {

    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID FILE_OBJECT_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");

    @Mock
    private FileQueryService fileQueryService;

    private TxtContentDecoder decoder;

    @BeforeEach
    void setUp() {
        decoder = new TxtContentDecoder(fileQueryService);
    }

    @Test
    void countsEveryLineTerminatorAsOneCharacter() {
        List<TxtContentDecoder.TxtLine> lines = readLines("甲\r\n乙\r丙\n丁", StandardCharsets.UTF_8);

        assertThat(lines).extracting(TxtContentDecoder.TxtLine::offset)
                .containsExactly(0L, 2L, 4L, 6L);
        assertThat(lines).extracting(TxtContentDecoder.TxtLine::text)
                .containsExactly("甲", "乙", "丙", "丁");
        assertThat(totalOffset("甲\r\n乙\r丙\n丁", StandardCharsets.UTF_8)).isEqualTo(7L);
    }

    @Test
    void marksOnlyTheFirstLineAsNotPrecededBySeparator() {
        List<TxtContentDecoder.TxtLine> lines = readLines("甲\n乙\n丙", StandardCharsets.UTF_8);

        assertThat(lines).extracting(TxtContentDecoder.TxtLine::precededBySeparator)
                .containsExactly(false, true, true);
    }

    @Test
    void excludesUtf8BomFromOffsetDomain() {
        String withBom = (char) 0xFEFF + "甲\n乙";
        List<TxtContentDecoder.TxtLine> lines = readLines(withBom, StandardCharsets.UTF_8);

        assertThat(lines).extracting(TxtContentDecoder.TxtLine::text)
                .containsExactly("甲", "乙");
        assertThat(lines).extracting(TxtContentDecoder.TxtLine::offset)
                .containsExactly(0L, 2L);
        assertThat(totalOffset(withBom, StandardCharsets.UTF_8)).isEqualTo(3L);
    }

    /**
     * 末行没有终止符时不得补记分隔符；末行自带终止符时该终止符不属于任何章节，
     * 因为分隔符只在确实读到后继行时才计入。
     */
    @Test
    void doesNotAppendSeparatorForUnterminatedLastLine() {
        assertThat(totalOffset("甲\n乙", StandardCharsets.UTF_8)).isEqualTo(3L);
        assertThat(readLines("甲\n", StandardCharsets.UTF_8))
                .extracting(TxtContentDecoder.TxtLine::text)
                .containsExactly("甲");
        assertThat(totalOffset("甲\n", StandardCharsets.UTF_8)).isEqualTo(1L);
    }

    @Test
    void advancesOffsetsAcrossEmptyLines() {
        List<TxtContentDecoder.TxtLine> lines = readLines("\n\n甲", StandardCharsets.UTF_8);

        assertThat(lines).hasSize(3);
        assertThat(lines).extracting(TxtContentDecoder.TxtLine::offset)
                .containsExactly(0L, 1L, 2L);
        assertThat(lines.get(2).text()).isEqualTo("甲");
        assertThat(totalOffset("\n\n甲", StandardCharsets.UTF_8)).isEqualTo(3L);
    }

    @Test
    void yieldsNoLinesForEmptyContent() {
        assertThat(readLines("", StandardCharsets.UTF_8)).isEmpty();
        assertThat(totalOffset("", StandardCharsets.UTF_8)).isZero();
    }

    @Test
    void detectsGb18030AndCountsCharactersNotBytes() {
        Charset detected = decoder.detectCharset(stubContent("中文字符测试", Charset.forName("GB18030")));

        assertThat(detected).isEqualTo(Charset.forName("GB18030"));
        List<TxtContentDecoder.TxtLine> lines = readLines("中文字符测试", Charset.forName("GB18030"));

        assertThat(lines).hasSize(1);
        assertThat(lines.get(0).text()).isEqualTo("中文字符测试");
        assertThat(totalOffset("中文字符测试", Charset.forName("GB18030"))).isEqualTo(6L);
    }

    @Test
    void keepsMultiSurrogateCharactersAtJavaCharLength() {
        String emoji = "甲😀乙";

        assertThat(totalOffset(emoji, StandardCharsets.UTF_8)).isEqualTo((long) emoji.length());
    }

    private List<TxtContentDecoder.TxtLine> readLines(String text, Charset charset) {
        byte[] bytes = text.getBytes(charset);
        stubContent(text, charset);
        List<TxtContentDecoder.TxtLine> lines = new ArrayList<>();
        try (TxtContentDecoder.TxtLineCursor cursor =
                     decoder.openCursor(fileNode(bytes.length), charset)) {
            TxtContentDecoder.TxtLine line;
            while ((line = cursor.next()) != null) {
                lines.add(line);
            }
        }
        return lines;
    }

    private long totalOffset(String text, Charset charset) {
        byte[] bytes = text.getBytes(charset);
        stubContent(text, charset);
        try (TxtContentDecoder.TxtLineCursor cursor =
                     decoder.openCursor(fileNode(bytes.length), charset)) {
            while (cursor.next() != null) {
                // 逐行推进到文末，offset() 即为整本字符数
            }
            return cursor.offset();
        }
    }

    private FileDescriptor stubContent(String text, Charset charset) {
        return stubContent(text.getBytes(charset));
    }

    private FileDescriptor stubContent(byte[] bytes) {
        when(fileQueryService.openOwnedFileContent(any(), eq(FILE_NODE_ID)))
                .thenAnswer(invocation -> new FileContentStream(
                        new ChunkedInputStream(new ByteArrayInputStream(bytes)),
                        "book.txt",
                        bytes.length,
                        "text/plain"
                ));
        return fileNode(bytes.length);
    }

    private FileDescriptor fileNode(long sizeBytes) {
        Instant now = Instant.now();
        return new FileDescriptor(
                FILE_NODE_ID,
                OWNER_ID,
                null,
                "FILE",
                "book.txt",
                "/book.txt",
                "text/plain",
                sizeBytes,
                FILE_OBJECT_ID,
                "UPLOAD",
                false,
                false,
                SpaceType.PERSONAL,
                UUID.randomUUID(),
                now,
                now
        );
    }

    /**
     * 限制单次读取字节数的输入流，模拟 MinIO 分块流。
     */
    private static final class ChunkedInputStream extends FilterInputStream {

        private static final int MAX_CHUNK_BYTES = 4096;

        ChunkedInputStream(InputStream input) {
            super(input);
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            return super.read(buffer, offset, Math.min(length, MAX_CHUNK_BYTES));
        }
    }
}
