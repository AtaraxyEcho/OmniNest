package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
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
import java.util.Optional;
import java.util.UUID;
import java.util.function.IntConsumer;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 文本书籍解析器测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderTextParserTest {

    private static final UUID FILE_NODE_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_OBJECT_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    @Mock
    private FileMetadataQueryService fileMetadataQueryService;

    @Mock
    private FileQueryService fileQueryService;

    @Mock
    private ReaderEpubArchiveStager epubArchiveStager;

    @Mock
    private ReaderArchiveSafetyPolicy archiveSafetyPolicy;

    private ReaderTextParser parser;

    @BeforeEach
    void setUp() {
        parser = new ReaderTextParser(
                fileMetadataQueryService,
                new TxtContentDecoder(fileQueryService),
                epubArchiveStager,
                archiveSafetyPolicy
        );
    }

    @Test
    void parsesUtf8TxtIntoStableChapterOffsets() {
        String text = "前言内容\r\n第一章 开始\r\n这是第一章正文\r\n第二章 继续\r\n这是第二章正文";
        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.language()).isEqualTo("UTF-8");
        assertThat(result.chapters()).hasSize(3);
        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::chapterKey)
                .containsExactly("chapter_0", "chapter_1", "chapter_2");
        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactly("正文", "第一章 开始", "第二章 继续");
        assertThat(result.chapters()).allSatisfy(chapter ->
                assertThat(chapter.sourceEndOffset()).isGreaterThanOrEqualTo(chapter.sourceStartOffset()));
    }

    /**
     * D-01：章节标题行带全角空格缩进时必须仍能识别，否则整本书落进单章"正文"。
     */
    @Test
    void detectsChapterTitlesIndentedWithIdeographicSpace() {
        String text = """
                　　第一回 灵根育孕
                上苍付与，本为修持。
                　　第二回 悟彻菩提
                祖师笑道，你且看他。
                """;
        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactly("第一回 灵根育孕", "第二回 悟彻菩提");
    }

    /**
     * D-03：正文中出现"3.5 亿元"这类数字片段不得被当成章节标题；
     * 而真正的"1. 楔子"式序号标题仍要识别。
     */
    @Test
    void doesNotSplitChaptersOnNumericProseButKeepsRealNumericHeadings() {
        String text = """
                第一章 起因
                他提到 3.5 亿元的采购，众人沉默。
                1. 楔子
                正文继续。
                """;
        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactly("第一章 起因", "1. 楔子");
    }

    /**
     * N-05 与 D-07：偏移域为"解码后字符、每行终止算 1 字符、去 BOM"，
     * 末行没有终止符时不得多加 1。
     */
    @Test
    void offsetsMatchDecodedCharSequenceWithoutPhantomTrailingLineFeed() {
        String text = "第一章 甲\n正文\n第二章 乙\n正文";
        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).hasSize(2);
        assertThat(result.chapters().get(0).sourceStartOffset()).isEqualTo(0L);
        assertThat(result.chapters().get(0).sourceEndOffset()).isEqualTo(9L);
        assertThat(result.chapters().get(1).sourceStartOffset()).isEqualTo(9L);
        assertThat(result.chapters().get(1).sourceEndOffset()).isEqualTo((long) text.length());
    }

    /**
     * D-12：正文起点跳过标题行本身与其终止符；标题行就是本章唯一内容时退到章节末尾，
     * 表示本章没有正文。首行不是标题行的章节（无标题书名）正文起点为 0。
     */
    @Test
    void bodyStartSkipsTitleLineAndItsTerminator() {
        ReaderTextParser.ParsedTextBook withTitles = parseText(
                "第一章 甲\n正文\n第二章 乙\n正文", StandardCharsets.UTF_8);

        assertThat(withTitles.chapters())
                .extracting(ReaderTextParser.TextChapterDraft::bodyStartOffset)
                .containsExactly(6, 6);

        ReaderTextParser.ParsedTextBook untitledHead = parseText(
                "前言内容\n第一章 甲\n正文", StandardCharsets.UTF_8);

        assertThat(untitledHead.chapters())
                .extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactly("正文", "第一章 甲");
        assertThat(untitledHead.chapters())
                .extracting(ReaderTextParser.TextChapterDraft::bodyStartOffset)
                .containsExactly(0, 6);

        // 标题行就是本章全部内容时，正文起点退到章节末尾（本章正文为空）
        ReaderTextParser.ParsedTextBook titleOnly = parseText(
                "第一章 甲\n第二章 乙", StandardCharsets.UTF_8);

        assertThat(titleOnly.chapters())
                .extracting(ReaderTextParser.TextChapterDraft::bodyStartOffset)
                .containsExactly(6, 5);
        assertThat(titleOnly.chapters())
                .extracting(ReaderTextParser.TextChapterDraft::charCount)
                .containsExactly(6, 5);
    }

    /**
     * CRLF 与 CR 混排时，行终止符统一按 1 个字符计入偏移域。
     */
    @Test
    void treatsEveryLineTerminatorAsSingleCharOffset() {
        String text = "第一章 甲\r\n正文\r第二章 乙\n正文";
        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        // 偏移域：每行终止符一律记 1 字符，与前端把 \r\n 与 \r 规范化为 \n 后的长度一致。
        assertThat(result.chapters().get(0).sourceEndOffset()).isEqualTo(9L);
        assertThat(result.chapters().get(1).sourceStartOffset()).isEqualTo(9L);
        assertThat(result.chapters().get(1).sourceEndOffset()).isEqualTo(17L);
    }

    /**
     * UTF-8 BOM 不进入偏移域，保证与前端"去 BOM 后 substring"的语义一致。
     */
    @Test
    void excludesByteOrderMarkFromOffsets() {
        String text = "﻿第一章 甲\n正文";
        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).hasSize(1);
        assertThat(result.chapters().get(0).title()).isEqualTo("第一章 甲");
        assertThat(result.chapters().get(0).sourceStartOffset()).isEqualTo(0L);
        assertThat(result.chapters().get(0).sourceEndOffset()).isEqualTo(8L);
    }

    /**
     * N-07：畸形超长标题行不得原样入库，必须截断到列宽余量内。
     */
    @Test
    void clampsOverlongChapterTitle() {
        String text = "第一章 " + "字".repeat(900) + "\n正文";
        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).hasSize(1);
        assertThat(result.chapters().get(0).title()).hasSize(200);
    }

    /**
     * GB18030 中文 TXT 必须落到 GB18030 字符集，并仍能识别全角缩进标题。
     */
    @Test
    void detectsGb18030CharsetForNonUtf8ChineseText() {
        String text = "　　第一章 起\n中文正文内容。\n　　第二章 承\n后续正文内容。";
        ReaderTextParser.ParsedTextBook result = parseText(text, Charset.forName("GB18030"));

        assertThat(result.language()).isEqualTo("GB18030");
        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactly("第一章 起", "第二章 承");
    }

    /**
     * D-40：扫描期间必须产生中间进度，且不得越过扫描上限。
     */
    @Test
    void reportsIntermediateScanProgress() {
        StringBuilder builder = new StringBuilder();
        for (int i = 1; i <= 400; i++) {
            builder.append("第").append(i).append("章 标题\n").append("正文内容行，用于拉长文件。").append('\n');
        }
        String text = builder.toString();
        List<Integer> progressValues = new ArrayList<>();
        ReaderTextParser.ParsedTextBook result =
                parseTextCollectingProgress(text, StandardCharsets.UTF_8, progressValues);

        assertThat(result.chapters()).hasSize(400);
        assertThat(progressValues).hasSizeGreaterThan(3);
        assertThat(progressValues).isSorted();
        assertThat(progressValues).allSatisfy(value -> assertThat(value).isBetween(25, 80));
    }

    /**
     * 进度回调是取消检查点：回调抛出后扫描必须中断，不得读完剩余内容。
     */
    @Test
    void abortsScanWhenProgressReporterThrows() {
        String text = "第一章 甲\n正文\n".repeat(300);

        assertThatThrownBy(() -> parseText(text, StandardCharsets.UTF_8, progress -> {
            if (progress > 30) {
                throw new ReaderImportCancelledException();
            }
        })).isInstanceOf(ReaderImportCancelledException.class);
    }

    private ReaderTextParser.ParsedTextBook parseText(String text, Charset charset) {
        return parseText(text, charset, progress -> {
        });
    }

    private ReaderTextParser.ParsedTextBook parseTextCollectingProgress(
            String text, Charset charset, List<Integer> progressValues) {
        return parseText(text, charset, progressValues::add);
    }

    private ReaderTextParser.ParsedTextBook parseText(
            String text, Charset charset, IntConsumer progressReporter) {
        byte[] bytes = text.getBytes(charset);
        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(fileNode(bytes.length)));
        when(fileQueryService.openOwnedFileContent(any(), eq(FILE_NODE_ID)))
                .thenAnswer(invocation -> new FileContentStream(
                        new ChunkedInputStream(new ByteArrayInputStream(bytes)),
                        "book.txt",
                        bytes.length,
                        "text/plain"
                ));
        return parser.parse(FILE_NODE_ID, "TXT", progressReporter);
    }

    /**
     * 限制单次读取字节数的输入流，模拟 MinIO 分块流；
     * 否则整本内容会在一次填充中被读完，扫描进度无法体现中间值。
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

    private FileDescriptor fileNode(long sizeBytes) {
        Instant now = Instant.now();
        return new FileDescriptor(
                FILE_NODE_ID,
                UUID.randomUUID(),
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

}
