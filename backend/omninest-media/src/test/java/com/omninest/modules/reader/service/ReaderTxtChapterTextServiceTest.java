package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.processing.TempStagingPort;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderTextChapter;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderTextChapterRepository;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.stubbing.Answer;

/**
 * TXT 每章正文派生测试。
 *
 * <p>核心约束是派生文件必须与清单偏移逐章对齐：行终止符计入偏移且归属于前方内容所在章节，
 * 因此上一章以换行结尾、最后一行没有终止符的末章没有。清单区间允许留出空洞（被丢弃的预览
 * 副本不属于任何一章），所以另有用例钉住空洞被跳过、起点必须落在行首、区间不许回退重叠。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderTxtChapterTextServiceTest {

    private static final UUID ITEM_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("60000000-0000-0000-0000-000000000002");
    private static final UUID FILE_NODE_ID = UUID.fromString("60000000-0000-0000-0000-000000000003");
    private static final UUID OLD_CHAPTER_NODE_ID = UUID.fromString("60000000-0000-0000-0000-000000000004");
    private static final UUID OTHER_OLD_CHAPTER_NODE_ID = UUID.fromString("60000000-0000-0000-0000-000000000005");

    @Mock
    private ReaderItemRepository itemRepository;

    @Mock
    private ReaderTextChapterRepository chapterRepository;

    @Mock
    private FileMetadataQueryService fileMetadataQueryService;

    @Mock
    private FileQueryService fileQueryService;

    @Mock
    private DerivedAssetStorageService derivedAssetStorageService;

    @Mock
    private TempStagingPort tempStagingPort;

    @Mock
    private ReaderEpubArchiveStager epubArchiveStager;

    @Mock
    private ReaderArchiveSafetyPolicy archiveSafetyPolicy;

    @Mock
    private ReaderItemService readerItemService;

    @TempDir
    Path tempDir;

    private final MediaProcessingLimitsProperties processingLimits = new MediaProcessingLimitsProperties();

    private ReaderTxtChapterTextService service;

    @BeforeEach
    void setUp() {
        service = new ReaderTxtChapterTextService(
                itemRepository,
                chapterRepository,
                fileMetadataQueryService,
                fileQueryService,
                new TxtContentDecoder(fileQueryService),
                derivedAssetStorageService,
                tempStagingPort,
                processingLimits,
                readerItemService
        );
    }

    @Test
    void writesEachChapterWithTheLineTerminatorOwnedByTheEarlierChapter() {
        String text = "第一章 甲\n正文\n第二章 乙\n正文";
        List<String> stored = new ArrayList<>();
        prepare(text, List.of(chapter(0, 0L, 9L), chapter(1, 9L, 17L)), 3, stored);

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        });

        // 上一章末尾带上属于它的终止符，末章没有终止符
        assertThat(stored).containsExactly("第一章 甲\n正文\n", "第二章 乙\n正文");
        verify(tempStagingPort, times(2)).deleteQuietly(any(Path.class));
    }

    @Test
    void namesDerivedAssetByManifestVersion() {
        List<String> stored = new ArrayList<>();
        prepare("第一章 甲\n正文", List.of(chapter(0, 0L, 8L)), 7, stored);

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        });

        verify(derivedAssetStorageService).store(
                eq(OWNER_ID), eq("READER_ITEM"), eq(ITEM_ID), eq("TEXT_CHAPTER"),
                eq("v7_chapter_0.txt"), eq("text/plain"), any(Path.class));
    }

    @Test
    void sweepsObsoleteAssetsOnlyAfterEveryChapterIsStored() {
        List<String> stored = new ArrayList<>();
        prepare("第一章 甲\n正文\n第二章 乙\n正文",
                List.of(chapter(0, 0L, 9L), chapter(1, 9L, 17L)), 8, stored);

        service.materialize(ITEM_ID, FILE_NODE_ID,
                List.of(OLD_CHAPTER_NODE_ID, OTHER_OLD_CHAPTER_NODE_ID), progress -> {
                });

        assertThat(stored).hasSize(2);
        verify(derivedAssetStorageService).deleteDerivedFileNode(OLD_CHAPTER_NODE_ID);
        verify(derivedAssetStorageService).deleteDerivedFileNode(OTHER_OLD_CHAPTER_NODE_ID);
    }

    @Test
    void keepsOldAssetsWhenMaterializationFails() {
        ReaderTextChapter broken = chapter(0, 0L, 7L);
        prepareWithoutStore("第一章 甲\n正文", List.of(broken), 8);

        assertThatThrownBy(() -> service.materialize(ITEM_ID, FILE_NODE_ID,
                List.of(OLD_CHAPTER_NODE_ID), progress -> {
                }))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("TXT 章节正文与清单偏移不一致");

        verify(derivedAssetStorageService, never()).deleteDerivedFileNode(any());
    }

    @Test
    void skipsZeroByteChaptersWithoutFailingTheTask() {
        ReaderTextChapter empty = chapter(0, 0L, 0L);
        prepareWithoutStore("", List.of(empty), 1);

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        });

        verify(derivedAssetStorageService, never()).store(
                any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
        assertThat(empty.getContentFileNodeId()).isNull();
    }

    @Test
    void failsLoudlyWhenManifestOffsetsDoNotMatchTheSource() {
        ReaderTextChapter tooShort = chapter(0, 0L, 7L);
        prepareWithoutStore("第一章 甲\n正文", List.of(tooShort), 1);

        assertThatThrownBy(() -> service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        }))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("TXT 章节正文与清单偏移不一致");
    }

    /**
     * 抓取站放在文末的预览副本不属于任何一章，清单因此不覆盖文件末尾：跳读并记日志即可，
     * 不能把已经对齐的正文章节一起判失败（廓晋.txt 的形状）。
     */
    @Test
    void skipsUncoveredTailAndStillDerivesEveryChapter() {
        String text = "第一章 甲\n正文\n第二章 乙\n正文\n第一章 甲\n尾部副本";
        List<String> stored = new ArrayList<>();
        prepare(text, List.of(chapter(0, 0L, 9L), chapter(1, 9L, 18L)), 1, stored);

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        });

        assertThat(stored).containsExactly("第一章 甲\n正文\n", "第二章 乙\n正文\n");
        assertThat(String.join("", stored)).doesNotContain("尾部副本");
        verify(derivedAssetStorageService, times(2)).store(
                any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
    }

    /**
     * 正文开头的副本被丢弃后，两章之间留下空洞：空洞里的字符与行终止符都不许并进相邻章，
     * 每章写入量仍必须正好等于清单区间。
     */
    @Test
    void skipsInteriorGapWithoutMergingCopiesIntoNeighbours() {
        String text = "书名：测试\n第一章 甲\n副本\n第二章 乙\n正文甲\n第三章 丙\n正文乙";
        List<String> stored = new ArrayList<>();
        prepare(text, List.of(chapter(0, 0L, 6L), chapter(1, 15L, 25L), chapter(2, 25L, 34L)), 1, stored);

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        });

        assertThat(stored).containsExactly("书名：测试\n", "第二章 乙\n正文甲\n", "第三章 丙\n正文乙");
    }

    /** 起点落进空洞是合法的；落进某行中间就不是同一份源文件，必须显式失败。 */
    @Test
    void failsLoudlyWhenChapterStartFallsInsideALine() {
        prepare("书名：测试\n第一章 甲\n副本\n第二章 乙\n正文甲",
                List.of(chapter(0, 0L, 6L), chapter(1, 16L, 24L)), 1, new ArrayList<>());

        assertThatThrownBy(() -> service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        }))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("TXT 章节起点不在行边界");
    }

    /** 区间可以变宽不能回退：起点早于上一章终点意味着同一行会被写进两章。 */
    @Test
    void failsLoudlyWhenManifestSpansOverlap() {
        prepare("第一章 甲\n正文\n第二章 乙\n正文",
                List.of(chapter(0, 0L, 9L), chapter(1, 5L, 17L)), 1, new ArrayList<>());

        assertThatThrownBy(() -> service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        }))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("TXT 章节区间顺序异常");
    }

    /**
     * 首章起点晚于 0 是合法形状：抓取站放在文件开头的预览副本被整段丢弃后，游标必须跳到清单起点，
     * 而不是从第 0 字符开始把副本写进第一章。
     */
    @Test
    void skipsTheFileHeadWhenTheFirstChapterStartsAfterIt() {
        List<String> stored = new ArrayList<>();
        prepare("书名：测试\n第一章 甲\n正文", List.of(chapter(0, 6L, 14L)), 1, stored);

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        });

        assertThat(stored).singleElement().satisfies(body -> {
            assertThat(body).hasSize(8);
            assertThat(body).doesNotContain("书名");
            assertThat(body).startsWith("第一章 甲");
        });
    }

    /**
     * 解析→派生的接线回归（副本从第 0 字符起）：真实解析器给出的首章起点在文件中间，
     * 派生写入器过去会在这里直接判"章节区间顺序异常"，整本书导入失败。
     */
    @Test
    void derivesChaptersWhenTheDroppedPreviewCopyStartsAtTheFileHead() {
        String body = """
                第一回 灵根育孕
                正文甲的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三四五六七八。
                第二回 悟彻菩提
                正文乙的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三四五六七八。
                """;
        String text = """
                第一回 灵根育孕
                预览甲。
                第二回 悟彻菩提
                预览乙。

                """ + body + "\n";
        List<ReaderTextChapter> manifest = new ArrayList<>();
        List<String> stored = new ArrayList<>();
        prepare(text, manifest, 1, stored);

        ReaderTextParser parser = new ReaderTextParser(
                fileMetadataQueryService,
                new TxtContentDecoder(fileQueryService),
                epubArchiveStager,
                archiveSafetyPolicy
        );
        ReaderTextParser.ParsedTextBook parsed = parser.parse(FILE_NODE_ID, "TXT", progress -> {
        });
        manifest.clear();
        parsed.chapters().forEach(draft -> manifest.add(derivedChapter(draft)));

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        });

        assertThat(manifest).isNotEmpty();
        assertThat(manifest.getFirst().getSourceStartOffset()).isPositive();
        assertThat(stored).hasSize(manifest.size());
        for (int index = 0; index < manifest.size(); index++) {
            ReaderTextChapter chapter = manifest.get(index);
            assertThat(stored.get(index))
                    .as("第 %s 章派生长度必须等于清单区间", chapter.getChapterIndex())
                    .hasSize((int) (chapter.getSourceEndOffset() - chapter.getSourceStartOffset()));
        }
        assertThat(stored).allSatisfy(chapter -> assertThat(chapter).doesNotContain("预览甲", "预览乙"));
        assertThat(stored.getFirst()).startsWith("第一回 灵根育孕");
    }

    /**
     * 解析→派生的接线回归：真实解析器丢掉头部与尾部预览副本后留下的清单，必须能被派生写入器
     * 一路写完。两条链各自单测都绿着时，这个矛盾也会整本书导入失败。
     */
    @Test
    void derivesEveryChapterFromTheManifestTheRealParserProduces() {
        String text = """
                书名：测试书
                作者：测试者

                第1章 甲
                预览正文一。
                第2章 乙
                预览正文二。

                第1章 甲
                正文一的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三。
                第2章 乙
                正文二的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三。
                第3章 丙
                正文三的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三。
                第4章 丁
                正文四的内容要足够长一些，好让正文这一段明显比预览副本大上一圈一二三。
                第1章 甲
                尾部副本一。

                ════════════════
                想看更多？复制下面的链接即可。
                """;
        List<ReaderTextChapter> manifest = new ArrayList<>();
        List<String> stored = new ArrayList<>();
        prepare(text, manifest, 1, stored);

        ReaderTextParser parser = new ReaderTextParser(
                fileMetadataQueryService,
                new TxtContentDecoder(fileQueryService),
                epubArchiveStager,
                archiveSafetyPolicy
        );
        ReaderTextParser.ParsedTextBook parsed = parser.parse(FILE_NODE_ID, "TXT", progress -> {
        });
        parsed.chapters().forEach(draft -> manifest.add(derivedChapter(draft)));

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        });

        assertThat(parsed.chapters()).extracting(ReaderTextParser.TextChapterDraft::title)
                .containsExactly("正文", "第1章 甲", "第2章 乙", "第3章 丙", "第4章 丁", "正文");
        // T10：尾部区间必须入表。清单之外的字符在派生阶段不属于任何一章，读者与进度
        // 都取不到，《廓晋》实测就是尾部 32,983 字（全书 1/9）无声消失。
        assertThat(stored).hasSize(manifest.size());
        for (int index = 0; index < manifest.size(); index++) {
            ReaderTextChapter chapter = manifest.get(index);
            assertThat(stored.get(index))
                    .as("第 %s 章派生长度必须等于清单区间", chapter.getChapterIndex())
                    .hasSize((int) (chapter.getSourceEndOffset() - chapter.getSourceStartOffset()));
        }
        // 文件头部的预览副本仍不落在任何一章里；书尾那份连同推广段按 T10 收进尾章，
        // 读者多看到一次重复内容，胜过正文永远取不到。
        assertThat(stored.getFirst()).doesNotContain("预览正文");
        assertThat(String.join("\n", stored.subList(1, stored.size() - 1)))
                .doesNotContain("预览正文", "尾部副本", "想看更多");
        assertThat(stored.getLast()).contains("尾部副本", "想看更多");
        assertThat(stored.get(1)).startsWith("第1章 甲");
    }

    @Test
    void skipsNonTxtItemsWithoutTouchingStorage() {
        ReaderItem item = textItem("EPUB", 4);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        });

        verify(chapterRepository, never()).findByReaderItemIdOrderByChapterIndex(any());
        verify(derivedAssetStorageService, never()).store(
                any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
    }

    @Test
    void reportsBodyProgressWithinScanRange() {
        List<String> stored = new ArrayList<>();
        List<Integer> progressValues = new ArrayList<>();
        prepare("第一章 甲\n正文\n第二章 乙\n正文\n第三章 丙\n正文", List.of(
                chapter(0, 0L, 9L), chapter(1, 9L, 18L), chapter(2, 18L, 26L)), 2, stored);

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progressValues::add);

        assertThat(progressValues).isNotEmpty();
        assertThat(progressValues).allSatisfy(value -> assertThat(value).isBetween(80, 95));
        assertThat(progressValues.getLast()).isEqualTo(95);
    }

    @Test
    void returnsChapterBodyWithoutTheTitleLine() {
        byte[] body = "第一章 甲\n正文".getBytes(StandardCharsets.UTF_8);
        ReaderTextChapter chapter = chapter(0, 0L, 8L);
        chapter.setBodyStartOffset(6);
        stubChapterAssetRead(chapter, body);

        ReaderTxtChapterTextService.ChapterTextDto dto = service.readChapterText(OWNER_ID, ITEM_ID, 0);

        assertThat(dto.text()).isEqualTo("正文");
        assertThat(dto.charCount()).isEqualTo(2);
        assertThat(dto.bodyStartOffset()).isEqualTo(6);
    }

    @Test
    void reportsEmptyBodyWithoutRewritingTheOffset() {
        byte[] body = "第一章 甲".getBytes(StandardCharsets.UTF_8);
        ReaderTextChapter chapter = chapter(0, 0L, 5L);
        // 清单超前于派生文件：起点夹紧到文件末尾，正文为空但不改写偏移，
        // 否则客户端会把一致的状态误判成陈旧清单
        chapter.setBodyStartOffset(6);
        stubChapterAssetRead(chapter, body);

        ReaderTxtChapterTextService.ChapterTextDto dto = service.readChapterText(OWNER_ID, ITEM_ID, 0);

        assertThat(dto.text()).isEmpty();
        assertThat(dto.charCount()).isZero();
        assertThat(dto.bodyStartOffset()).isEqualTo(5);
    }

    @Test
    void reportsUnavailableWhenChapterAssetWasNeverDerived() {
        when(readerItemService.requireItem(OWNER_ID, ITEM_ID)).thenReturn(textItem("TXT", 3));
        when(chapterRepository.findByReaderItemIdAndChapterIndex(ITEM_ID, 1))
                .thenReturn(Optional.of(chapter(1, 9L, 17L)));

        assertThatThrownBy(() -> service.readChapterText(OWNER_ID, ITEM_ID, 1))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.CHAPTER_TEXT_UNAVAILABLE));
    }

    @Test
    void reportsUnavailableWhenDerivedNodeWasPurgedBeforeTheManifest() {
        ReaderTextChapter chapter = chapter(0, 0L, 8L);
        chapter.setContentFileNodeId(OLD_CHAPTER_NODE_ID);
        when(readerItemService.requireItem(OWNER_ID, ITEM_ID)).thenReturn(textItem("TXT", 3));
        when(chapterRepository.findByReaderItemIdAndChapterIndex(ITEM_ID, 0)).thenReturn(Optional.of(chapter));
        when(fileQueryService.openOwnedFileContent(OWNER_ID, OLD_CHAPTER_NODE_ID))
                .thenThrow(new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));

        assertThatThrownBy(() -> service.readChapterText(OWNER_ID, ITEM_ID, 0))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.CHAPTER_TEXT_UNAVAILABLE));
    }

    @Test
    void rejectsNonTxtItemsAndForeignItemsOnRead() {
        when(readerItemService.requireItem(OWNER_ID, ITEM_ID)).thenReturn(textItem("EPUB", 3));

        assertThatThrownBy(() -> service.readChapterText(OWNER_ID, ITEM_ID, 0))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("当前条目不是 TXT 书籍");

        when(readerItemService.requireItem(OWNER_ID, ITEM_ID))
                .thenThrow(new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在"));
        assertThatThrownBy(() -> service.readChapterText(OWNER_ID, ITEM_ID, 0))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.BOOK_NOT_FOUND));
    }

    @Test
    void readsSharedItemChapterAssetWithTheOwnerThatDerivedIt() {
        // 共享成员请求正文：鉴权看请求者，派生文件必须按条目所有者开流，否则会 404 到不存在的节点
        UUID requesterId = UUID.fromString("60000000-0000-0000-0000-000000000009");
        byte[] body = "第一章 甲\n正文".getBytes(StandardCharsets.UTF_8);
        ReaderTextChapter chapter = chapter(0, 0L, 8L);
        chapter.setContentFileNodeId(OLD_CHAPTER_NODE_ID);
        chapter.setBodyStartOffset(6);
        when(readerItemService.requireItem(requesterId, ITEM_ID)).thenReturn(textItem("TXT", 3));
        when(chapterRepository.findByReaderItemIdAndChapterIndex(ITEM_ID, 0)).thenReturn(Optional.of(chapter));
        when(fileQueryService.openOwnedFileContent(OWNER_ID, OLD_CHAPTER_NODE_ID))
                .thenReturn(new FileContentStream(
                        new ByteArrayInputStream(body), "v3_chapter_0.txt", body.length, "text/plain"));

        ReaderTxtChapterTextService.ChapterTextDto dto = service.readChapterText(requesterId, ITEM_ID, 0);

        assertThat(dto.text()).isEqualTo("正文");
        verify(fileQueryService).openOwnedFileContent(OWNER_ID, OLD_CHAPTER_NODE_ID);
    }

    @Test
    void refusesOversizedChapterAssetBeforeBufferingIt() {
        byte[] body = "第一章 甲\n正文".getBytes(StandardCharsets.UTF_8);
        processingLimits.setMaxReaderChapterTextBytes(8L);
        ReaderTextChapter chapter = chapter(0, 0L, 8L);
        stubChapterAssetRead(chapter, body);

        assertThatThrownBy(() -> service.readChapterText(OWNER_ID, ITEM_ID, 0))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("本章正文超过单章返回上限");
    }

    @Test
    void skipsDerivingChaptersAboveThePerChapterLimit() {
        ReaderTextChapter chapter = chapter(0, 0L, 8L);
        prepareWithoutStore("第一章 甲\n正文", List.of(chapter), 1);
        processingLimits.setMaxReaderChapterTextBytes(8L);

        service.materialize(ITEM_ID, FILE_NODE_ID, List.of(), progress -> {
        });

        verify(derivedAssetStorageService, never()).store(
                any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
        assertThat(chapter.getContentFileNodeId()).isNull();
        verify(tempStagingPort).deleteQuietly(any(Path.class));
    }

    @Test
    void dropsTheAssetButKeepsOldOnesWhenTheManifestWasRebuilt() {
        ReaderTextChapter chapter = chapter(0, 0L, 8L);
        prepare("第一章 甲\n正文", List.of(chapter), 1, new ArrayList<>());
        when(chapterRepository.updateContentFileNode(any(), any(), anyLong())).thenReturn(0);

        assertThatThrownBy(() -> service.materialize(ITEM_ID, FILE_NODE_ID,
                List.of(OLD_CHAPTER_NODE_ID), progress -> {
                }))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("TXT 章节清单已被并发重建");

        // 只回收刚写出的孤儿对象；旧版本正文留给重试，不能顺手删掉
        verify(derivedAssetStorageService).deleteDerivedFileNode(any());
        verify(derivedAssetStorageService, never()).deleteDerivedFileNode(OLD_CHAPTER_NODE_ID);
    }

    private void stubChapterAssetRead(ReaderTextChapter chapter, byte[] body) {
        chapter.setContentFileNodeId(OLD_CHAPTER_NODE_ID);
        when(readerItemService.requireItem(OWNER_ID, ITEM_ID)).thenReturn(textItem("TXT", 3));
        when(chapterRepository.findByReaderItemIdAndChapterIndex(ITEM_ID, chapter.getChapterIndex()))
                .thenReturn(Optional.of(chapter));
        when(fileQueryService.openOwnedFileContent(OWNER_ID, chapter.getContentFileNodeId()))
                .thenReturn(new FileContentStream(
                        new ByteArrayInputStream(body), "v3_chapter_0.txt", body.length, "text/plain"));
    }

    private void prepare(String text, List<ReaderTextChapter> chapters, int manifestVersion, List<String> captured) {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        stubSource(bytes, chapters);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(textItem("TXT", manifestVersion)));
        when(chapterRepository.updateContentFileNode(any(), any(), anyLong())).thenReturn(1);
        when(derivedAssetStorageService.store(
                eq(OWNER_ID), eq("READER_ITEM"), eq(ITEM_ID), eq("TEXT_CHAPTER"),
                anyString(), eq("text/plain"), any(Path.class)))
                .thenAnswer(captureContent(captured));
    }

    private void prepareWithoutStore(String text, List<ReaderTextChapter> chapters, int manifestVersion) {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        stubSource(bytes, chapters);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(textItem("TXT", manifestVersion)));
    }

    private void stubSource(byte[] bytes, List<ReaderTextChapter> chapters) {
        stubSourceContent(bytes, chapters);
        when(tempStagingPort.createTempFile(anyString(), anyString(), anyString()))
                .thenAnswer(invocation -> Files.createTempFile(tempDir, "chapter-", ".txt"));
        // 与生产一致地真正删除，避免测试目录里留下未回收的临时文件
        doAnswer(invocation -> Files.deleteIfExists(invocation.getArgument(0)))
                .when(tempStagingPort).deleteQuietly(any(Path.class));
    }

    private void stubSourceContent(byte[] bytes, List<ReaderTextChapter> chapters) {
        when(fileQueryService.openOwnedFileContent(any(), eq(FILE_NODE_ID)))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(bytes), "book.txt", bytes.length, "text/plain"));
        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(fileNode(bytes.length)));
        when(chapterRepository.findByReaderItemIdOrderByChapterIndex(ITEM_ID)).thenReturn(chapters);
    }

    private Answer<UUID> captureContent(List<String> captured) {
        return invocation -> {
            Path source = invocation.getArgument(6);
            captured.add(Files.readString(source, StandardCharsets.UTF_8));
            return UUID.randomUUID();
        };
    }

    private ReaderTextChapter chapter(int index, long start, long end) {
        ReaderTextChapter chapter = new ReaderTextChapter();
        chapter.setId(UUID.randomUUID());
        chapter.setReaderItemId(ITEM_ID);
        chapter.setChapterIndex(index);
        chapter.setChapterKey("chapter_" + index);
        chapter.setTitle("第" + (index + 1) + "章");
        chapter.setSourceStartOffset(start);
        chapter.setSourceEndOffset(end);
        chapter.setCharCount((int) (end - start));
        chapter.setLevel(0);
        chapter.setBodyStartOffset(0);
        return chapter;
    }

    /**
     * 把解析草稿还原成清单行，等价于 {@code ReaderTextManifestService.toEntity} 的写入结果，
     * 供解析→派生接线用例使用。
     */
    private ReaderTextChapter derivedChapter(ReaderTextParser.TextChapterDraft draft) {
        ReaderTextChapter chapter = new ReaderTextChapter();
        chapter.setId(UUID.randomUUID());
        chapter.setReaderItemId(ITEM_ID);
        chapter.setChapterIndex(draft.chapterIndex());
        chapter.setChapterKey(draft.chapterKey());
        chapter.setTitle(draft.title());
        chapter.setContentPath(draft.contentPath());
        chapter.setSourceStartOffset(draft.sourceStartOffset());
        chapter.setSourceEndOffset(draft.sourceEndOffset());
        chapter.setCharCount(draft.charCount());
        chapter.setLevel(draft.level());
        chapter.setBodyStartOffset(draft.bodyStartOffset());
        return chapter;
    }

    private ReaderItem textItem(String itemType, int manifestVersion) {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(FILE_NODE_ID);
        item.setItemType(itemType);
        item.setContentKind("TEXT");
        item.setTitle("测试书");
        item.setManifestVersion(manifestVersion);
        return item;
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
                UUID.randomUUID(),
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
