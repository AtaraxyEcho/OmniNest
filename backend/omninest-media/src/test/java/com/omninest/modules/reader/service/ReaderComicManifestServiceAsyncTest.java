package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderSourceStatus;
import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.repository.ReaderCatalogNodeRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 漫画异步清单任务测试，验证兼容入口不在请求线程同步解析文件。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderComicManifestServiceAsyncTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    @Mock
    private ReaderItemRepository itemRepository;
    @Mock
    private ReaderItemSourceRepository sourceRepository;
    @Mock
    private ReaderCatalogNodeRepository catalogRepository;
    @Mock
    private ReaderPageRepository pageRepository;
    @Mock
    private FileMetadataQueryService fileMetadataQueryService;
    @Mock
    private ReaderComicArchiveParser archiveParser;
    @Mock
    private ComicManifestBuilder manifestBuilder;
    @Mock
    private ComicPageAssetService pageAssetService;
    @Mock
    private ReaderArchiveSafetyPolicy archiveSafetyPolicy;
    @Mock
    private ReaderEpubArchiveStager epubArchiveStager;
    @Mock
    private TaskDispatchService taskDispatchService;
    @Mock
    private TaskRecordService taskRecordService;
    @Mock
    private MediaSyncEventService syncEventService;
    @Mock
    private ReaderCoverExtractionService coverExtractionService;

    @InjectMocks
    private ReaderComicManifestService service;

    @Test
    void enqueueManifestParseCreatesPendingSourceAndPublishesTask() {
        ReaderItem item = comicItem();
        FileDescriptor fileNode = new FileDescriptor(
                FILE_NODE_ID,
                OWNER_ID,
                null,
                "FILE",
                "作品 第001-010话.cbz",
                "/作品 第001-010话.cbz",
                "application/vnd.comicbook+zip",
                0,
                null,
                "UPLOAD",
                false,
                false,
                SpaceType.PERSONAL,
                OWNER_ID,
                null,
                null
        );

        when(itemRepository.findByIdForUpdate(ITEM_ID)).thenReturn(Optional.of(item));
        when(sourceRepository.findByReaderItemIdAndFileNodeId(ITEM_ID, FILE_NODE_ID))
                .thenReturn(Optional.empty());
        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(fileNode));
        when(sourceRepository.save(any(ReaderItemSource.class))).thenAnswer(invocation -> {
            ReaderItemSource source = invocation.getArgument(0);
            source.setId(UUID.fromString("40000000-0000-0000-0000-000000000001"));
            return source;
        });
        when(itemRepository.save(item)).thenReturn(item);

        service.enqueueManifestParse(item);

        ArgumentCaptor<ReaderItemSource> sourceCaptor = ArgumentCaptor.forClass(ReaderItemSource.class);
        verify(sourceRepository).save(sourceCaptor.capture());
        ReaderItemSource savedSource = sourceCaptor.getValue();
        assertThat(savedSource.getStatus()).isEqualTo(ReaderSourceStatus.PENDING);
        assertThat(savedSource.getChapterStart()).isEqualTo(1);
        assertThat(savedSource.getChapterEnd()).isEqualTo(10);
        assertThat(item.getImportStatus()).isEqualTo("PARSING");
        verify(taskRecordService).createQueuedTask(
                any(),
                eq(OWNER_ID),
                eq("COMIC_PARSE"),
                eq(QueueNames.COMIC_PARSE_ROUTING_KEY),
                eq("QUEUED"),
                eq("FILE_NODE"),
                eq(FILE_NODE_ID),
                any()
        );

        ArgumentCaptor<UUID> dispatchTaskIdCaptor = ArgumentCaptor.forClass(UUID.class);
        ArgumentCaptor<ComicParseTaskEvent> eventCaptor = ArgumentCaptor.forClass(ComicParseTaskEvent.class);
        verify(taskDispatchService).enqueue(
                dispatchTaskIdCaptor.capture(),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.COMIC_PARSE_ROUTING_KEY),
                eventCaptor.capture());
        ComicParseTaskEvent event = eventCaptor.getValue();
        assertThat(event.taskId()).isEqualTo(dispatchTaskIdCaptor.getValue());
        assertThat(event.ownerUserId()).isEqualTo(OWNER_ID);
        assertThat(event.itemId()).isEqualTo(ITEM_ID);
        assertThat(event.sourceId()).isEqualTo(savedSource.getId());
    }

    @Test
    void enqueueManifestReparseResetsReadySourceAndPublishesTask() {
        ReaderItem item = comicItem();
        ReaderItemSource source = comicSource(ReaderSourceStatus.READY);

        when(itemRepository.findByIdForUpdate(ITEM_ID)).thenReturn(Optional.of(item));
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of(source));
        when(sourceRepository.save(source)).thenReturn(source);
        when(itemRepository.save(item)).thenReturn(item);

        service.enqueueManifestReparse(ITEM_ID);

        assertThat(source.getStatus()).isEqualTo(ReaderSourceStatus.PENDING);
        assertThat(source.getErrorCode()).isNull();
        assertThat(source.getErrorMessage()).isNull();
        assertThat(item.getImportStatus()).isEqualTo("PARSING");
        verify(taskRecordService).createQueuedTask(
                any(),
                eq(OWNER_ID),
                eq("COMIC_PARSE"),
                eq(QueueNames.COMIC_PARSE_ROUTING_KEY),
                eq("QUEUED"),
                eq("FILE_NODE"),
                eq(FILE_NODE_ID),
                any()
        );
        verify(taskDispatchService).enqueue(
                any(UUID.class),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.COMIC_PARSE_ROUTING_KEY),
                any(ComicParseTaskEvent.class)
        );
    }

    @Test
    void enqueueManifestReparseDoesNotDuplicateRunningTask() {
        ReaderItem item = comicItem();
        ReaderItemSource source = comicSource(ReaderSourceStatus.PARSING);

        when(itemRepository.findByIdForUpdate(ITEM_ID)).thenReturn(Optional.of(item));
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of(source));
        when(itemRepository.save(item)).thenReturn(item);

        service.enqueueManifestReparse(ITEM_ID);

        assertThat(source.getStatus()).isEqualTo(ReaderSourceStatus.PARSING);
        assertThat(item.getImportStatus()).isEqualTo("PARSING");
        verify(sourceRepository, never()).save(source);
        verify(taskRecordService, never()).createQueuedTask(any(), any(), any(), any(), any());
        verify(taskDispatchService, never()).enqueue(any(), any(), any(), any());
    }

    @Test
    void markSourceFailedUpdatesSourceAndAggregatedItemStatus() {
        ReaderItem item = comicItem();
        ReaderItemSource source = comicSource(ReaderSourceStatus.PARSING);
        when(sourceRepository.findById(source.getId())).thenReturn(Optional.of(source));
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of(source));
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));

        service.markSourceFailed(ITEM_ID, source.getId(), "COMIC_PARSE_FAILED", "解析失败");

        assertThat(source.getStatus()).isEqualTo(ReaderSourceStatus.FAILED);
        assertThat(source.getErrorCode()).isEqualTo("COMIC_PARSE_FAILED");
        assertThat(item.getImportStatus()).isEqualTo("FAILED");
        assertThat(item.getParseErrorMessage()).isEqualTo("解析失败");
        verify(sourceRepository).save(source);
        verify(itemRepository).save(item);
    }

    @Test
    void deleteSourceRejectsRemovingTheLastSource() {
        ReaderItem item = comicItem();
        ReaderItemSource source = comicSource(ReaderSourceStatus.READY);
        when(itemRepository.findByIdForUpdate(ITEM_ID)).thenReturn(Optional.of(item));
        when(sourceRepository.findById(source.getId())).thenReturn(Optional.of(source));
        when(sourceRepository.countByReaderItemId(ITEM_ID)).thenReturn(1L);

        assertThatThrownBy(() -> service.deleteSource(ITEM_ID, source.getId()))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("至少需要保留一个来源");

        verify(sourceRepository, never()).delete(source);
        verify(pageRepository, never()).deleteBySourceId(source.getId());
    }

    private ReaderItem comicItem() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(FILE_NODE_ID);
        item.setContentHash("hash");
        item.setItemType("CBZ");
        item.setContentKind("COMIC");
        item.setTitle("作品");
        return item;
    }

    private ReaderItemSource comicSource(ReaderSourceStatus status) {
        ReaderItemSource source = new ReaderItemSource();
        source.setId(UUID.fromString("40000000-0000-0000-0000-000000000001"));
        source.setReaderItemId(ITEM_ID);
        source.setFileNodeId(FILE_NODE_ID);
        source.setContentHash("hash");
        source.setFileFormat("CBZ");
        source.setSourceName("作品 第001-010话.cbz");
        source.setStatus(status);
        source.setErrorCode("OLD_ERROR");
        source.setErrorMessage("old error");
        return source;
    }
}
