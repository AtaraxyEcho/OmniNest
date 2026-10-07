package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.processing.TempStagingPort;
import com.omninest.common.ratelimit.RateLimitService;
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
import java.time.Duration;
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
 * 因此上一章以换行结尾、最后一行没有终止符的末章没有。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderTxtChapterTextServiceTest {

    private static final UUID ITEM_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("60000000-0000-0000-0000-000000000002");
    private static final UUID FILE_NODE_ID = UUID.fromString("60000000-0000-0000-0000-000000000003");
    private static final UUID OLD_CHAPTER_NODE_ID = UUID.fromString("60000000-0000-0000-0000-000000000004");

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
    private RateLimitService rateLimitService;

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
                rateLimitService
        );
    }

    @Test
    void writesEachChapterWithTheLineTerminatorOwnedByTheEarlierChapter() throws IOException {
        String text = "第一章 甲\n正文\n第二章 乙\n正文";
        List<String> stored = new ArrayList<>();
        prepare(text, List.of(chapter(0, 0L, 9L), chapter(1, 9L, 17L)), 3, stored);

        service.materialize(ITEM_ID, FILE_NODE_ID, progress -> {
        });

        // 上一章末尾带上属于它的终止符，末章没有终止符
        assertThat(stored).containsExactly("第一章 甲\n正文\n", "第二章 乙\n正文");
        verify(tempStagingPort, times(2)).deleteQuietly(any(Path.class));
    }

    @Test
    void namesDerivedAssetByManifestVersion() throws IOException {
        List<String> stored = new ArrayList<>();
        prepare("第一章 甲\n正文", List.of(chapter(0, 0L, 8L)), 7, stored);

        service.materialize(ITEM_ID, FILE_NODE_ID, progress -> {
        });

        verify(derivedAssetStorageService).store(
                eq(OWNER_ID), eq("READER_ITEM"), eq(ITEM_ID), eq("TEXT_CHAPTER"),
                eq("v7_chapter_0.txt"), eq("text/plain"), any(Path.class));
    }

    @Test
    void replacesPreviousVersionAssetAfterStoringTheNewOne() throws IOException {
        List<String> stored = new ArrayList<>();
        ReaderTextChapter existing = chapter(0, 0L, 8L);
        existing.setContentFileNodeId(OLD_CHAPTER_NODE_ID);
        prepare("第一章 甲\n正文", List.of(existing), 8, stored);
        when(derivedAssetStorageService.deleteDerivedFileNode(OLD_CHAPTER_NODE_ID)).thenReturn(true);

        service.materialize(ITEM_ID, FILE_NODE_ID, progress -> {
        });

        verify(derivedAssetStorageService).deleteDerivedFileNode(OLD_CHAPTER_NODE_ID);
        verify(chapterRepository).save(existing);
        assertThat(existing.getContentFileNodeId()).isNotNull();
    }

    @Test
    void failsLoudlyWhenManifestOffsetsDoNotMatchTheSource() {
        ReaderTextChapter tooShort = chapter(0, 0L, 7L);
        prepareWithoutStore("第一章 甲\n正文", List.of(tooShort), 1);

        assertThatThrownBy(() -> service.materialize(ITEM_ID, FILE_NODE_ID, progress -> {
        }))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("TXT 章节正文与清单偏移不一致");
    }

    @Test
    void failsLoudlyWhenManifestDoesNotCoverSourceTail() {
        ReaderTextChapter missingTail = chapter(0, 0L, 5L);
        prepareWithoutStore("第一章 甲\n正文", List.of(missingTail), 1);

        assertThatThrownBy(() -> service.materialize(ITEM_ID, FILE_NODE_ID, progress -> {
        }))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("TXT 章节清单未覆盖源文件末尾内容");
    }

    @Test
    void skipsNonTxtItemsWithoutTouchingStorage() {
        ReaderItem item = textItem("EPUB", 4);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));

        service.materialize(ITEM_ID, FILE_NODE_ID, progress -> {
        });

        verify(chapterRepository, never()).findByReaderItemIdOrderByChapterIndex(any());
        verify(derivedAssetStorageService, never()).store(
                any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
    }

    @Test
    void reportsBodyProgressWithinScanRange() throws IOException {
        List<String> stored = new ArrayList<>();
        List<Integer> progressValues = new ArrayList<>();
        prepare("第一章 甲\n正文\n第二章 乙\n正文\n第三章 丙\n正文", List.of(
                chapter(0, 0L, 9L), chapter(1, 9L, 18L), chapter(2, 18L, 26L)), 2, stored);

        service.materialize(ITEM_ID, FILE_NODE_ID, progressValues::add);

        assertThat(progressValues).isNotEmpty();
        assertThat(progressValues).allSatisfy(value -> assertThat(value).isBetween(80, 95));
        assertThat(progressValues.getLast()).isEqualTo(95);
    }

    @Test
    void returnsChapterBodyWithoutTheTitleLine() {
        byte[] body = "第一章 甲\n正文".getBytes(StandardCharsets.UTF_8);
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(true);
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(textItem("TXT", 3)));
        ReaderTextChapter chapter = chapter(0, 0L, 8L);
        chapter.setBodyStartOffset(6);
        chapter.setContentFileNodeId(OLD_CHAPTER_NODE_ID);
        when(chapterRepository.findByReaderItemIdAndChapterIndex(ITEM_ID, 0)).thenReturn(Optional.of(chapter));
        when(fileQueryService.openOwnedFileContent(OWNER_ID, OLD_CHAPTER_NODE_ID))
                .thenReturn(new FileContentStream(
                        new ByteArrayInputStream(body), "v3_chapter_0.txt", body.length, "text/plain"));

        ReaderTxtChapterTextService.ChapterTextDto dto = service.readChapterText(OWNER_ID, ITEM_ID, 0);

        assertThat(dto.text()).isEqualTo("正文");
        assertThat(dto.charCount()).isEqualTo(2);
        assertThat(dto.bodyStartOffset()).isEqualTo(6);
        assertThat(dto.chapterIndex()).isZero();
    }

    @Test
    void clampsBodyStartWhenManifestIsAheadOfTheAsset() {
        byte[] body = "第一章 甲".getBytes(StandardCharsets.UTF_8);
        ReaderTextChapter chapter = chapter(0, 0L, 5L);
        chapter.setBodyStartOffset(6);
        chapter.setContentFileNodeId(OLD_CHAPTER_NODE_ID);
        stubChapterAssetRead(chapter, body);

        ReaderTxtChapterTextService.ChapterTextDto dto = service.readChapterText(OWNER_ID, ITEM_ID, 0);

        assertThat(dto.text()).isEmpty();
        assertThat(dto.bodyStartOffset()).isEqualTo(5);
    }

    @Test
    void reportsUnavailableWhenChapterAssetWasNeverDerived() {
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(true);
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(textItem("TXT", 3)));
        when(chapterRepository.findByReaderItemIdAndChapterIndex(ITEM_ID, 1))
                .thenReturn(Optional.of(chapter(1, 9L, 17L)));

        assertThatThrownBy(() -> service.readChapterText(OWNER_ID, ITEM_ID, 1))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.CHAPTER_TEXT_UNAVAILABLE));
    }

    @Test
    void rejectsNonTxtItemsAndForeignItemsOnRead() {
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(true);
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(textItem("EPUB", 3)));

        assertThatThrownBy(() -> service.readChapterText(OWNER_ID, ITEM_ID, 0))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("当前条目不是 TXT 书籍");

        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.readChapterText(OWNER_ID, ITEM_ID, 0))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("阅读条目不存在或无权访问");
    }

    @Test
    void refusesReadWhenRateLimitIsExhausted() {
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(false);

        assertThatThrownBy(() -> service.readChapterText(OWNER_ID, ITEM_ID, 0))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("正文请求过于频繁");
        verify(itemRepository, never()).findByIdAndOwnerUserId(any(), any());
    }

    @Test
    void refusesOversizedChapterAssetBeforeBufferingIt() {
        byte[] body = "第一章 甲\n正文".getBytes(StandardCharsets.UTF_8);
        processingLimits.setMaxReaderChapterTextBytes(8L);
        ReaderTextChapter chapter = chapter(0, 0L, 8L);
        chapter.setContentFileNodeId(OLD_CHAPTER_NODE_ID);
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

        service.materialize(ITEM_ID, FILE_NODE_ID, progress -> {
        });

        verify(derivedAssetStorageService, never()).store(
                any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
        assertThat(chapter.getContentFileNodeId()).isNull();
        verify(chapterRepository).save(chapter);
        verify(tempStagingPort).deleteQuietly(any(Path.class));
    }

    private void stubChapterAssetRead(ReaderTextChapter chapter, byte[] body) {
        when(rateLimitService.tryAcquire(anyString(), anyInt(), any(Duration.class))).thenReturn(true);
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(textItem("TXT", 3)));
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
        when(fileQueryService.openOwnedFileContent(any(), eq(FILE_NODE_ID)))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(bytes), "book.txt", bytes.length, "text/plain"));
        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(fileNode(bytes.length)));
        when(chapterRepository.findByReaderItemIdOrderByChapterIndex(ITEM_ID)).thenReturn(chapters);
        when(tempStagingPort.createTempFile(anyString(), anyString(), anyString()))
                .thenAnswer(invocation -> Files.createTempFile(tempDir, "chapter-", ".txt"));
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
