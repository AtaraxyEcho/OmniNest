package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.PurgeContributionWriter;
import com.omninest.modules.file.service.PurgeContext;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPageAsset;
import com.omninest.modules.reader.repository.ReaderAnnotationRepository;
import com.omninest.modules.reader.repository.ReaderBookmarkRepository;
import com.omninest.modules.reader.repository.ReaderBookshelfRepository;
import com.omninest.modules.reader.repository.ReaderCatalogNodeRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderNoteRepository;
import com.omninest.modules.reader.repository.ReaderPageAssetRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import com.omninest.modules.reader.repository.ReaderReadingSessionRepository;
import com.omninest.modules.reader.repository.ReaderTextChapterRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 阅读文件关联数据清理服务测试。
 *
 * @author OmniNest
 */
class ReaderFileCleanupServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SECOND_FILE_NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000009");
    private static final UUID ITEM_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID OTHER_OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID PURGED_SOURCE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID SURVIVING_SOURCE_ID = UUID.fromString("40000000-0000-0000-0000-000000000002");
    private static final UUID PURGED_PAGE_ASSET_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");

    private final ReaderItemRepository itemRepository = Mockito.mock(ReaderItemRepository.class);
    private final ReaderProgressRepository progressRepository = Mockito.mock(ReaderProgressRepository.class);
    private final ReaderItemSourceRepository itemSourceRepository = Mockito.mock(ReaderItemSourceRepository.class);
    private final ReaderPageAssetRepository pageAssetRepository = Mockito.mock(ReaderPageAssetRepository.class);
    private final ReaderPageRepository pageRepository = Mockito.mock(ReaderPageRepository.class);
    private final ReaderCatalogNodeRepository catalogRepository = Mockito.mock(ReaderCatalogNodeRepository.class);
    private final ReaderTextChapterRepository textChapterRepository = Mockito.mock(ReaderTextChapterRepository.class);
    private final ReaderBookmarkRepository bookmarkRepository = Mockito.mock(ReaderBookmarkRepository.class);
    private final ReaderAnnotationRepository annotationRepository = Mockito.mock(ReaderAnnotationRepository.class);
    private final ReaderNoteRepository noteRepository = Mockito.mock(ReaderNoteRepository.class);
    private final ReaderBookshelfRepository bookshelfRepository = Mockito.mock(ReaderBookshelfRepository.class);
    private final ReaderReadingSessionRepository readingSessionRepository =
            Mockito.mock(ReaderReadingSessionRepository.class);
    private final MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
    private final ReaderComicManifestService comicManifestService = Mockito.mock(ReaderComicManifestService.class);
    private final FileMetadataQueryService fileMetadataQueryService = Mockito.mock(FileMetadataQueryService.class);
    private final ReaderFileCleanupService service = new ReaderFileCleanupService(
            itemRepository,
            itemSourceRepository,
            pageAssetRepository,
            pageRepository,
            catalogRepository,
            textChapterRepository,
            progressRepository,
            bookmarkRepository,
            annotationRepository,
            noteRepository,
            bookshelfRepository,
            readingSessionRepository,
            syncEventService,
            comicManifestService,
            fileMetadataQueryService
    );

    @Test
    void hardDeleteRemovesEveryMemberRowsOnTheItem() {
        ReaderItem item = item();
        when(itemRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(item));
        when(itemRepository.findAllById(Set.of(ITEM_ID)))
                .thenReturn(List.of(item));

        service.finalizePurge(purgeContext());

        // 共享条目的进度、书架、书签、批注与笔记属于空间里的每个人：只删条目所有者那一份，
        // 其他成员的行会永远留在库里（条目已经不在了，再也无人按 (owner, item) 去清）。
        verify(progressRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(bookshelfRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(bookmarkRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(annotationRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(noteRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(progressRepository, never()).deleteByOwnerUserIdAndReaderItemIdIn(Mockito.eq(OWNER_ID), anyList());
        verify(bookshelfRepository, never()).deleteByOwnerUserIdAndReaderItemIdIn(Mockito.eq(OWNER_ID), anyList());
        verify(bookmarkRepository, never()).deleteByOwnerUserIdAndReaderItemIdIn(Mockito.eq(OWNER_ID), anyList());
        verify(annotationRepository, never()).deleteByOwnerUserIdAndReaderItemIdIn(Mockito.eq(OWNER_ID), anyList());
        verify(noteRepository, never()).deleteByOwnerUserIdAndReaderItemIdIn(Mockito.eq(OWNER_ID), anyList());
        verify(readingSessionRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(pageAssetRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(pageRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(catalogRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(itemSourceRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(textChapterRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(itemRepository).deleteAllInBatch(List.of(item));
        // 彻底删除不经过软删除事件，必须主动推送条目删除与阅读库失效。
        verify(syncEventService).record(
                OWNER_ID,
                SyncScope.READER,
                "READER_ITEM",
                ITEM_ID.toString(),
                SyncAction.DELETED,
                item.getVersion(),
                Map.of()
        );
        verify(syncEventService).invalidate(
                OWNER_ID,
                SyncScope.READER,
                "READER_LIBRARY",
                Map.of("reason", "PURGED")
        );
    }

    @Test
    void softDeletePreservesReaderRows() {
        service.handleFileNodesSoftDeleted(new FileNodesSoftDeletedEvent(
                OWNER_ID,
                List.of(FILE_NODE_ID),
                Instant.now()
        ));

        Mockito.verifyNoInteractions(progressRepository, bookshelfRepository, bookmarkRepository);
        Mockito.verifyNoInteractions(annotationRepository, noteRepository, readingSessionRepository);
    }

    @Test
    void visibilityChangeInvalidatesAffectedReaderOwner() {
        ReaderItem item = item();
        when(itemRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(item));
        when(itemRepository.findAllById(Set.of(ITEM_ID)))
                .thenReturn(List.of(item));

        service.invalidateFileVisibility(List.of(FILE_NODE_ID));

        Mockito.verify(syncEventService).invalidate(
                OWNER_ID,
                SyncScope.READER,
                "READER_LIBRARY",
                Map.of("reason", "FILE_VISIBILITY_CHANGED")
        );
    }

    @Test
    void hardDeleteRemovesCrossOwnerItemReferencedThroughItsOnlySource() {
        ReaderItem item = item();
        item.setOwnerUserId(OTHER_OWNER_ID);
        item.setFileNodeId(SECOND_FILE_NODE_ID);
        ReaderItemSource source = source(PURGED_SOURCE_ID, FILE_NODE_ID, 1);
        when(itemSourceRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(source));
        when(itemRepository.findAllById(Set.of(ITEM_ID)))
                .thenReturn(List.of(item));

        service.finalizePurge(purgeContext());

        verify(progressRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(pageAssetRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(pageRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(catalogRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(itemSourceRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(textChapterRepository).deleteByReaderItemIdIn(List.of(ITEM_ID));
        verify(itemRepository).deleteAllInBatch(List.of(item));
    }

    @Test
    void purgeOfOneVolumeKeepsTheWorkAndMigratesThePrimaryFile() {
        ReaderItem item = comicItem();
        ReaderItemSource purged = source(PURGED_SOURCE_ID, FILE_NODE_ID, 1);
        ReaderItemSource surviving = source(SURVIVING_SOURCE_ID, SECOND_FILE_NODE_ID, 2);
        when(itemRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(item));
        when(itemRepository.findAllById(Set.of(ITEM_ID)))
                .thenReturn(List.of(item));
        when(itemSourceRepository.findByReaderItemIdIn(List.of(ITEM_ID)))
                .thenReturn(List.of(purged, surviving));

        service.finalizePurge(purgeContext());

        verify(pageAssetRepository).deleteBySourceId(PURGED_SOURCE_ID);
        verify(pageRepository).deleteBySourceId(PURGED_SOURCE_ID);
        verify(itemSourceRepository).delete(purged);
        assertThat(item.getFileNodeId()).isEqualTo(SECOND_FILE_NODE_ID);
        assertThat(item.getContentHash()).isEqualTo("hash-2");
        verify(itemRepository).save(item);
        verify(comicManifestService).rebuildComicManifest(ITEM_ID);
        verify(comicManifestService).refreshItemImportStatus(ITEM_ID);
        verify(itemRepository, never()).deleteAllInBatch(anyList());
        verify(progressRepository, never()).deleteByReaderItemIdIn(anyList());
        verify(itemSourceRepository, never()).deleteByReaderItemIdIn(anyList());
    }

    @Test
    void contributeKeepsSurvivingVolumesOutOfThePurgeSet() {
        ReaderItem item = comicItem();
        ReaderItemSource purged = source(PURGED_SOURCE_ID, FILE_NODE_ID, 1);
        ReaderItemSource surviving = source(SURVIVING_SOURCE_ID, SECOND_FILE_NODE_ID, 2);
        ReaderPageAsset purgedAsset = new ReaderPageAsset();
        purgedAsset.setFileNodeId(PURGED_PAGE_ASSET_ID);
        PurgeContributionWriter writer = mock(PurgeContributionWriter.class);
        when(itemRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(item));
        when(itemRepository.findAllById(Set.of(ITEM_ID)))
                .thenReturn(List.of(item));
        when(itemSourceRepository.findByReaderItemIdIn(List.of(ITEM_ID)))
                .thenReturn(List.of(purged, surviving));
        when(pageAssetRepository.findBySourceIdIn(List.of(PURGED_SOURCE_ID)))
                .thenReturn(List.of(purgedAsset));

        service.contribute(purgeContext(), writer);

        ArgumentCaptor<List<UUID>> contributed = ArgumentCaptor.forClass(List.class);
        verify(writer, Mockito.atLeastOnce()).addFileNodeIds(contributed.capture());
        List<List<UUID>> batches = contributed.getAllValues();
        assertThat(batches).anySatisfy(batch -> assertThat(batch).containsExactly(PURGED_PAGE_ASSET_ID));
        assertThat(batches).noneSatisfy(batch -> assertThat(batch).contains(SECOND_FILE_NODE_ID));
        assertThat(batches).noneSatisfy(batch -> assertThat(batch).contains(item.getCoverFileId()));
        verify(pageAssetRepository, never()).findByReaderItemIdIn(anyList());
    }

    private ReaderItem item() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(FILE_NODE_ID);
        return item;
    }

    private ReaderItem comicItem() {
        ReaderItem item = item();
        item.setContentKind("COMIC");
        item.setCoverFileId(UUID.fromString("60000000-0000-0000-0000-000000000001"));
        return item;
    }

    private ReaderItemSource source(UUID sourceId, UUID fileNodeId, int volumeNo) {
        ReaderItemSource source = new ReaderItemSource();
        source.setId(sourceId);
        source.setReaderItemId(ITEM_ID);
        source.setFileNodeId(fileNodeId);
        source.setContentHash("hash-" + volumeNo);
        source.setVolumeNo(volumeNo);
        source.setSourceSortKey(String.format("%04d", volumeNo));
        return source;
    }

    private PurgeContext purgeContext() {
        return new PurgeContext(UUID.randomUUID(), OWNER_ID, FILE_NODE_ID, List.of(FILE_NODE_ID));
    }
}
