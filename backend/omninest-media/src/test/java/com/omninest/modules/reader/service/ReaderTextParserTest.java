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
    void epubChapterCharCountIgnoresStyleAndScriptText() {
        // 清单字数是全书进度的权重与"本章多少字"：把 CSS 与 JS 的文本算进去，
        // 带样式的章会被凭空放大，读者看到的正文长度与进度分母就此脱钩。
        String head = """
                <?xml version="1.0" encoding="UTF-8"?>\
                <html xmlns="http://www.w3.org/1999/xhtml">""";
        String withStyle = head
                + "<head><style>body{margin:0;padding:0;color:#123456}</style><title>章名</title></head>"
                + "<body><p>这是正文</p><style>p{text-indent:2em}</style>"
                + "<script>var hidden = \"这段不该计数\";</script></body></html>";
        String withoutStyle = head
                + "<head><title>章名</title></head>"
                + "<body><p>这是正文</p></body></html>";

        int counted = parser.countXhtmlCharacters(withStyle, "text/a.xhtml");

        assertThat(counted).isEqualTo(parser.countXhtmlCharacters(withoutStyle, "text/b.xhtml"));
        assertThat(counted).isEqualTo("这是正文".length());
    }

    @Test
    void countsTheLastChapterWhenWeighingTheMainSequence() {
        // 末章的区间要以文末收尾：把它记成 0 字时，正文段只按第一章计长度，
        // 文件头部的预览副本会赢下"哪一段是正文"的比较，目录整组指向副本区间。
        String preview = """
                第1章 甲
                预览甲。
                第2章 乙
                预览乙。
                """;
        String mainBody = "正文乙的内容要足够长一些，好让末章明显比整份预览副本大上一圈。".repeat(6);
        String main = "第1章 甲\n正文甲。\n第2章 乙\n" + mainBody + "\n";
        String text = preview + main;
        int mainStart = preview.length();

        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).hasSize(2);
        assertThat(result.chapters().getFirst().sourceStartOffset()).isEqualTo((long) mainStart);
        assertThat(result.chapters().getLast().sourceStartOffset())
                .isEqualTo((long) text.indexOf("第2章 乙", mainStart));
        assertThat(result.chapters().getLast().charCount()).isPositive();
    }

    @Test
    void parsesUtf8TxtIntoStableChapterOffsets() {
        String text = "前言内容\r\n第一章 开始\r\n这是第一章正文\r\n第二章 继续\r\n这是第二章正文";
        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.language()).isEqualTo("UTF-8");
        assertThat(result.chapters()).hasSize(3);
        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::chapterKey)
                .doesNotHaveDuplicates();
        // 身份键按正文起点派生：章节顺位不参与，删掉一个伪标题不会移动后续章的身份。
        assertThat(result.chapters()).allSatisfy(chapter ->
                assertThat(chapter.chapterKey()).isEqualTo("t" + chapter.sourceStartOffset()));
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
     * 清单必须覆盖解码文本的每一个字符：区间首尾相接、从 0 起、到文件末尾止。
     *
     * <p>落在所有区间之外的字符在派生阶段不属于任何一章，读者与进度都取不到，
     * 表现为"整本书尾部无声消失"（实测样本尾部 32,983 字，占全书 1/9）。
     * 尾部预览副本被丢成空洞时同样要补章，宁可让读者看到重复内容，也不把正文丢在清单外。
     */
    @Test
    void chapterIntervalsCoverWholeDecodedTextEvenAfterDroppedTail() {
        String text = "第一章 甲\n正文甲内容\n第二章 乙\n正文乙内容\n第一章 甲\n预告\n第二章 乙\n预告";
        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).isNotEmpty();
        assertThat(result.chapters().getFirst().sourceStartOffset()).isEqualTo(0L);
        assertThat(result.chapters().getLast().sourceEndOffset()).isEqualTo((long) text.length());
        long previousEnd = 0L;
        for (ReaderTextParser.TextChapterDraft chapter : result.chapters()) {
            assertThat(chapter.sourceStartOffset()).isEqualTo(previousEnd);
            assertThat(chapter.sourceEndOffset()).isGreaterThan(previousEnd);
            previousEnd = chapter.sourceEndOffset();
        }
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

    /**
     * 章名序号归一的判据表，与前端 chapter_title_normalizer_test.dart 逐条同值。
     *
     * <p>入库标题由这里归一，客户端要对切片首行施加同一归一才能做偏移校验，
     * 两份实现算出不同结果就会把整本书判成偏移漂移。改判据时两侧都要改。
     */
    @Test
    void normalizesRepeatedChapterNumberTokens() {
        record Case(String raw, int ordinal, String expected) {
        }

        List<Case> cases = List.of(
                new Case("第1章 第1章 天胡开局", 1, "第1章 天胡开局"),
                new Case("第10章 第10章 屯将（下）", 10, "第10章 屯将（下）"),
                new Case("第38章 第1章 吴兴", 38, "第38章 吴兴"),
                new Case("第38章 第1章 吴兴", 42, "第38章 吴兴"),
                new Case("第38章 第1章 吴兴", 1, "第1章 吴兴"),
                new Case("Chapter 3 Chapter 3 The Dawn", 3, "Chapter 3 The Dawn"),
                new Case("第二十三章 第二十三章 甲", 23, "第二十三章 甲"),
                new Case("第23章 第二十三章 甲", 23, "第23章 甲"),
                new Case("第一百二十章 甲", 120, "第一百二十章 甲"),
                new Case("第一千二百三十四章 甲", 1234, "第一千二百三十四章 甲"),
                new Case("第2章 2、小标题", 2, "第2章 小标题"),
                new Case("第1章： 第1章： 天胡开局", 1, "第1章 天胡开局"),
                new Case("第一章 甲", 1, "第一章 甲"),
                new Case("第1章 天胡开局", 1, "第1章 天胡开局"),
                new Case("1、《覆汉》实体书", 2, "1、《覆汉》实体书"),
                new Case("上架感言", 48, "上架感言"),
                new Case("第一卷完。113", 41, "第一卷完。113"),
                new Case("　　第一章 第一章 甲", 1, "　　第一章 第一章 甲"),
                new Case("第5章 复盘第4章的伏笔", 5, "第5章 复盘第4章的伏笔")
        );

        for (Case item : cases) {
            assertThat(ReaderTextParser.normalizeChapterTitle(item.raw(), item.ordinal()))
                    .as("位次 %d 的 %s", item.ordinal(), item.raw())
                    .isEqualTo(item.expected());
            // 入库标题会被客户端哨兵再施加一次归一，不幂等就比对不上。
            assertThat(ReaderTextParser.normalizeChapterTitle(item.expected(), item.ordinal()))
                    .as("归一必须幂等：%s", item.expected())
                    .isEqualTo(item.expected());
        }
    }

    /**
     * 编号附言与卷末标记不再起章：抓取站的"1、《覆汉》…；29"与"第一卷完。113"
     * 曾被当成独立标题，目录里留下十几字的伪章，正文也被从上一章截走。
     */
    @Test
    void doesNotStartChaptersOnNumberedNotesAndVolumeEndMarkers() {
        String text = """
                第1章 开局
                正文一句。
                第一卷完。113
                第2章 续
                1、《覆汉》实体书第一辑要出了；29
                正文二句。
                """;
        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactly("第1章 开局", "第2章 续");

        // 不再起章的那些行仍留在各自上一章的区间里，正文不丢字：
        // 第1章 开局 / 正文一句 / 第一卷完 三行共 20 字，章区间按标题行起点切，
        // 所以本章长度必然大于只含前两行的 11 字。
        assertThat(result.chapters().getFirst().charCount()).isGreaterThan(11);
        assertThat(result.chapters().getLast().charCount()).isGreaterThan(11);
        assertThat(result.chapters().getFirst().sourceEndOffset())
                .isEqualTo(result.chapters().getLast().sourceStartOffset());
        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::chapterKey)
                .containsExactly("t0", "t" + result.chapters().getLast().sourceStartOffset());
    }

    /**
     * 抓取站把开头几章原样复制到文件头尾当预览：副本必须整段丢弃——留在目录里就是
     * 三份同名同号，并进相邻章又会让一章凭空多出一段重复正文。
     */
    @Test
    void dropsScrapedPreviewCopiesWithoutMergingThemIntoNeighbours() {
        String body = """
                第1章 起
                正文甲的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三四五六七八。
                第2章 承
                正文乙的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三四五六七八。
                第3章 转
                正文丙的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三四五六七八。
                第4章 合
                正文丁的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三四五六七八。
                """;
        String text = """
                书名：测试书

                第1章 起
                预览副本一。
                第2章 承
                预览副本二。

                """ + body + """

                第1章 起
                尾部副本一。
                """;

        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactly("正文", "第1章 起", "第2章 承", "第3章 转", "第4章 合", "正文");
        // 区间以全部候选为界：单章"正文"在预览第一行之前就结束，正文第一章又从自己的
        // 标题行重新开始，中间那段副本不属于任何一章——目录与全书进度都不会再看到它。
        // 书尾那份副本按 T10 必须入表：清单不覆盖的字符在派生阶段谁也都取不到，
        // 《廓晋》实测就是尾部 32,983 字无声消失。宁可多一章重复内容，不丢正文。
        assertThat(result.chapters().getFirst().sourceEndOffset())
                .isLessThan(result.chapters().get(1).sourceStartOffset());
        int keptChars = result.chapters().stream()
                .mapToInt(ReaderTextParser.TextChapterDraft::charCount)
                .sum();
        assertThat(keptChars).isLessThan(text.length());
        assertThat(result.chapters()).allSatisfy(chapter ->
                assertThat(chapter.chapterKey()).isEqualTo("t" + chapter.sourceStartOffset()));
    }

    /**
     * 分卷书的第二卷各自从第1章重新编号：卷号不参与序号回退判定，
     * 不同卷的同名同号也不许被判成预览副本删掉。
     */
    @Test
    void keepsRenumberedChaptersOfSecondVolume() {
        String text = """
                第1卷 上游
                第1章 甲
                本章正文甲。
                第2章 乙
                本章正文乙。
                第2卷 下游
                第1章 丙
                本章正文丙。
                第2章 丁
                本章正文丁。
                """;

        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactly("第1卷 上游", "第1章 甲", "第2章 乙",
                        "第2卷 下游", "第1章 丙", "第2章 丁");
    }

    /** 中文数字编号也要能判出序号回退：认不出数值时预览副本切不出段，目录里就留着重复章。 */
    @Test
    void dropsPreviewCopiesNumberedWithChineseNumerals() {
        String body = """
                第一回 灵根育孕
                正文甲的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三四五六七八。
                第二回 悟彻菩提
                正文乙的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三四五六七八。
                第三回 冒死心猿
                正文丙的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三四五六七八。
                """;
        String text = """
                第一回 灵根育孕
                预览甲。
                第二回 悟彻菩提
                预览乙。

                """ + body + "\n";

        ReaderTextParser.ParsedTextBook result = parseText(text, StandardCharsets.UTF_8);

        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactly("第一回 灵根育孕", "第二回 悟彻菩提", "第三回 冒死心猿");
        // 入选的是正文那一组：文件开头的副本区不落在任何一章里，所以首章起点在正文处。
        assertThat(result.chapters().getFirst().sourceStartOffset()).isPositive();
        int keptChars = result.chapters().stream()
                .mapToInt(ReaderTextParser.TextChapterDraft::charCount)
                .sum();
        assertThat(keptChars).isLessThan(text.length());
    }

    /**
     * 抓取站整本形状的合成语料：书名头与分节线、正文头两章的预览副本、正文（章题重复序号、
     * 标题下垫 `----`、段末挂字数计数器）、卷末标记与编号附言、第二卷重新从第1章编号、
     * 书尾再放一份预览副本。
     *
     * <p>判据必须在这**一份**文本上同时成立：每条规则各自通过，不代表整本书的目录是对的
     * （比如副本丢弃的段大小阈值只有在正文真的比预览大得多时才生效）。结构取自
     * 实际抓取的网文 TXT，文字与书名都是编造的。
     */
    @Test
    void parsesScrapedWebNovelShape() {
        StringBuilder text = new StringBuilder();
        List<String> expectedTitles = new ArrayList<>();
        text.append("书名：结构样例\n").append("作者：某人\n")
                .append("=".repeat(48)).append("\n\n");
        expectedTitles.add("正文");

        // 文件头部的预览副本：与正文同名同号，但每章只有两行。
        text.append("第1章 第1章 起\n").append("预览甲。\n\n");
        text.append("第2章 第2章 承\n").append("预览乙。\n\n");

        for (String core : List.of("起", "承", "转", "合")) {
            int number = "起承转合".indexOf(core) + 1;
            text.append("第").append(number).append("章 第").append(number).append("章 ")
                    .append(core).append("\n");
            text.append("-".repeat(24)).append("\n");
            for (int line = 0; line < 30; line++) {
                text.append("正文句子").append("字".repeat(4 + line % 9)).append(line + 1).append("\n");
            }
            text.append("\n");
            expectedTitles.add("第" + number + "章 " + core);
        }

        // 卷末标记与编号附言：留在上一章正文里，不起章。
        text.append("第一卷完。113\n").append("1、《结构样例》实体书要出了；29\n\n");

        // 第二卷重新从第1章编号：卷号不参与序号回退，不同卷的同名同号必须保留。
        text.append("第1卷 下卷\n");
        expectedTitles.add("第1卷 下卷");
        for (String core : List.of("下甲", "下乙")) {
            int number = core.equals("下甲") ? 1 : 2;
            text.append("第").append(number).append("章 ").append(core).append("\n");
            text.append("-".repeat(24)).append("\n");
            for (int line = 0; line < 30; line++) {
                text.append("下卷正文").append("句".repeat(5 + line % 8)).append(line + 1).append("\n");
            }
            text.append("\n");
            expectedTitles.add("第" + number + "章 " + core);
        }

        // 书尾又放一份预览副本：按 T10 尾部区间必须入表，多出来的这一章标题是"正文"。
        text.append("第1章 第1章 起\n").append("尾部预览甲。\n");
        expectedTitles.add("正文");

        ReaderTextParser.ParsedTextBook result = parseText(text.toString(), StandardCharsets.UTF_8);

        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactlyElementsOf(expectedTitles);
        assertThat(result.chapters()).extracting(ReaderTextParser.TextChapterDraft::chapterKey)
                .doesNotHaveDuplicates();
        int keptChars = result.chapters().stream()
                .mapToInt(ReaderTextParser.TextChapterDraft::charCount)
                .sum();
        assertThat(keptChars).isLessThan(text.length());
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
