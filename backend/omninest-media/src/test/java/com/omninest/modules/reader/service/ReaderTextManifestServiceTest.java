package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderTextChapter;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderTextChapterRepository;
import com.omninest.modules.reader.service.ReaderTextParser.ParsedTextBook;
import com.omninest.modules.reader.service.ReaderTextParser.TextChapterDraft;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 文本书籍章节清单服务测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderTextManifestServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    @Mock
    private ReaderItemRepository itemRepository;

    @Mock
    private ReaderTextChapterRepository chapterRepository;

    @Mock
    private TaskRecordService taskRecordService;

    @Mock
    private MediaSyncEventService syncEventService;

    @Mock
    private ReaderCoverExtractionService coverExtractionService;

    private ReaderTextManifestService service;

    @BeforeEach
    void setUp() {
        service = new ReaderTextManifestService(
                itemRepository, chapterRepository, taskRecordService, syncEventService, coverExtractionService);
    }

    @Test
    void replacesManifestAndMarksItemReady() {
        ReaderItem item = textItem();
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        ParsedTextBook parsed = new ParsedTextBook(
                "解析标题",
                "解析作者",
                "zh-CN",
                List.of(new TextChapterDraft(0, "chapter_0", "第一章", "text/1.xhtml", null, null, 120, 0, null)),
                null
        );

        service.replaceManifest(ITEM_ID, parsed);

        verify(chapterRepository).deleteByReaderItemId(ITEM_ID);
        ArgumentCaptor<List<ReaderTextChapter>> chapters = ArgumentCaptor.captor();
        verify(chapterRepository).saveAll(chapters.capture());
        assertThat(chapters.getValue()).singleElement().satisfies(chapter -> {
            assertThat(chapter.getChapterKey()).isEqualTo("chapter_0");
            assertThat(chapter.getContentPath()).isEqualTo("text/1.xhtml");
        });
        assertThat(item.getImportStatus()).isEqualTo("READY");
        assertThat(item.getTitle()).isEqualTo("解析标题");
        assertThat(item.getParsedAt()).isNotNull();
        // 文本清单版本是每章正文派生资产的缓存键，reparse 必须推进它
        assertThat(item.getManifestVersion()).isEqualTo(1);
        verify(itemRepository).save(item);
    }

    @Test
    void reparseAdvancesManifestVersionFromCurrentValue() {
        ReaderItem item = textItem();
        item.setManifestVersion(7);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        ParsedTextBook parsed = new ParsedTextBook(
                null,
                null,
                "UTF-8",
                List.of(new TextChapterDraft(0, "chapter_0", "正文", null, 0L, 18L, 18, 0, 0)),
                null
        );

        service.replaceManifest(ITEM_ID, parsed);

        assertThat(item.getManifestVersion()).isEqualTo(8);
    }

    @Test
    void returnsPersistedManifestInChapterOrder() {
        ReaderItem item = textItem();
        ReaderTextChapter chapter = new ReaderTextChapter();
        chapter.setReaderItemId(ITEM_ID);
        chapter.setChapterIndex(0);
        chapter.setChapterKey("chapter_0");
        chapter.setTitle("正文");
        chapter.setCharCount(18);
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        when(chapterRepository.findByReaderItemIdOrderByChapterIndex(ITEM_ID)).thenReturn(List.of(chapter));

        ReaderTextManifestService.TextManifestDto manifest = service.getManifest(OWNER_ID, ITEM_ID);

        assertThat(manifest.importStatus()).isEqualTo("PARSING");
        assertThat(manifest.chapters()).singleElement().satisfies(result ->
                assertThat(result.chapterKey()).isEqualTo("chapter_0"));
        assertThat(manifest.parseTask()).isNull();
    }

    @Test
    void manifestIncludesLatestParseTaskProgress() {
        ReaderItem item = textItem();
        ReaderTextChapter chapter = new ReaderTextChapter();
        chapter.setReaderItemId(ITEM_ID);
        chapter.setChapterIndex(0);
        chapter.setChapterKey("chapter_0");
        chapter.setTitle("正文");
        chapter.setCharCount(18);
        TaskRecord task = new TaskRecord();
        task.setId(UUID.fromString("40000000-0000-0000-0000-000000000001"));
        task.setStatus("RUNNING");
        task.setPhase("PARSING_METADATA");
        task.setProgress(60);
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        when(chapterRepository.findByReaderItemIdOrderByChapterIndex(ITEM_ID)).thenReturn(List.of(chapter));
        when(taskRecordService.findLatestTaskByPayload(OWNER_ID, "READER_PARSE", "itemId", ITEM_ID))
                .thenReturn(Optional.of(task));

        ReaderTextManifestService.TextManifestDto manifest = service.getManifest(OWNER_ID, ITEM_ID);

        assertThat(manifest.parseTask()).isNotNull();
        assertThat(manifest.parseTask().status()).isEqualTo("RUNNING");
        assertThat(manifest.parseTask().progress()).isEqualTo(60);
    }

    private ReaderItem textItem() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(UUID.randomUUID());
        item.setItemType("EPUB");
        item.setContentKind("TEXT");
        item.setTitle("原始标题");
        item.setImportStatus("PARSING");
        return item;
    }
}
