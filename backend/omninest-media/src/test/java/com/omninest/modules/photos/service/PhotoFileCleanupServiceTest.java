package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.service.PurgeContext;
import com.omninest.modules.file.service.ResourceShareLinkService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.domain.PhotoAlbum;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.repository.PhotoAlbumItemRepository;
import com.omninest.modules.photos.repository.PhotoAlbumRepository;
import com.omninest.modules.photos.repository.PhotoContentAnalysisRunRepository;
import com.omninest.modules.photos.repository.PhotoContentLabelRepository;
import com.omninest.modules.photos.repository.PhotoEditVersionRepository;
import com.omninest.modules.photos.repository.PhotoFavoriteRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 照片文件关联数据清理服务测试。
 *
 * @author OmniNest
 */
class PhotoFileCleanupServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID PHOTO_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID ALBUM_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID COVER_FILE_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");

    private final PhotoItemRepository itemRepository = Mockito.mock(PhotoItemRepository.class);
    private final PhotoAlbumItemRepository albumItemRepository = Mockito.mock(PhotoAlbumItemRepository.class);
    private final PhotoFavoriteRepository favoriteRepository = Mockito.mock(PhotoFavoriteRepository.class);
    private final PhotoAlbumRepository albumRepository = Mockito.mock(PhotoAlbumRepository.class);
    private final PhotoTagRepository tagRepository = Mockito.mock(PhotoTagRepository.class);
    private final PhotoEditVersionRepository editVersionRepository =
            Mockito.mock(PhotoEditVersionRepository.class);
    private final PhotoContentLabelRepository contentLabelRepository =
            Mockito.mock(PhotoContentLabelRepository.class);
    private final PhotoContentAnalysisRunRepository contentAnalysisRunRepository =
            Mockito.mock(PhotoContentAnalysisRunRepository.class);
    private final PhotoSearchIndexService photoSearchIndexService = Mockito.mock(PhotoSearchIndexService.class);
    private final MediaSyncEventService syncEventService = Mockito.mock(MediaSyncEventService.class);
    private final ReadThroughCache readThroughCache = Mockito.mock(ReadThroughCache.class);
    private final ResourceShareLinkService resourceShareLinkService =
            Mockito.mock(ResourceShareLinkService.class);
    private final PhotoFileCleanupService service = new PhotoFileCleanupService(
            itemRepository,
            albumItemRepository,
            favoriteRepository,
            albumRepository,
            tagRepository,
            editVersionRepository,
            contentLabelRepository,
            contentAnalysisRunRepository,
            photoSearchIndexService,
            syncEventService,
            readThroughCache,
            resourceShareLinkService
    );

    @Test
    void hardDeleteRemovesPhotoRowsAndRefreshesAlbumCount() {
        PhotoItem photo = new PhotoItem();
        photo.setId(PHOTO_ID);
        photo.setOwnerUserId(OWNER_ID);
        photo.setFileNodeId(FILE_NODE_ID);
        photo.setCoverFileId(COVER_FILE_ID);
        photo.setVersion(3L);
        PhotoItem coverReference = new PhotoItem();
        coverReference.setCoverFileId(FILE_NODE_ID);
        PhotoItem editedReference = new PhotoItem();
        editedReference.setActiveFileId(FILE_NODE_ID);
        PhotoItem motionReference = new PhotoItem();
        motionReference.setMotionVideoFileNodeId(FILE_NODE_ID);
        PhotoAlbum album = new PhotoAlbum();
        album.setId(ALBUM_ID);
        PhotoAlbum albumCoverReference = new PhotoAlbum();
        albumCoverReference.setId(UUID.randomUUID());
        albumCoverReference.setCoverFileId(FILE_NODE_ID);
        Mockito.when(itemRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(photo));
        Mockito.when(albumItemRepository.findAlbumIdsByPhotoIdIn(List.of(PHOTO_ID)))
                .thenReturn(List.of(ALBUM_ID));
        Mockito.when(albumRepository.findAllByIdInAndOwnerUserId(List.of(ALBUM_ID), OWNER_ID))
                .thenReturn(List.of(album));
        Mockito.when(albumItemRepository.countActivePhotosByAlbumIds(List.of(ALBUM_ID)))
                .thenReturn(List.<Object[]>of(new Object[]{ALBUM_ID, 2L}));
        Mockito.when(itemRepository.findByCoverFileIdIn(Set.of(FILE_NODE_ID)))
                .thenReturn(List.of(coverReference));
        Mockito.when(itemRepository.findByActiveFileIdIn(Set.of(FILE_NODE_ID)))
                .thenReturn(List.of(editedReference));
        Mockito.when(itemRepository.findByMotionVideoFileNodeIdIn(Set.of(FILE_NODE_ID)))
                .thenReturn(List.of(motionReference));
        Mockito.when(albumRepository.findByCoverFileIdIn(Set.of(FILE_NODE_ID)))
                .thenReturn(List.of(albumCoverReference));

        service.finalizePurge(purgeContext());

        Mockito.verify(tagRepository).deleteByOwnerUserIdAndPhotoIdIn(OWNER_ID, List.of(PHOTO_ID));
        Mockito.verify(editVersionRepository).deleteByPhotoIdIn(List.of(PHOTO_ID));
        // 永久删除必须同步清掉分析标签与运行记录，避免孤儿行继续参与关系/统计查询。
        Mockito.verify(contentLabelRepository).deleteByPhotoIdIn(List.of(PHOTO_ID));
        Mockito.verify(contentAnalysisRunRepository).deleteByPhotoIdIn(List.of(PHOTO_ID));
        Mockito.verify(albumItemRepository).deleteByPhotoIdIn(List.of(PHOTO_ID));
        Mockito.verify(favoriteRepository).deleteByPhotoIdIn(List.of(PHOTO_ID));
        Mockito.verify(photoSearchIndexService).deletePhotos(List.of(PHOTO_ID));
        Mockito.verify(resourceShareLinkService).revokeAllByResourceIds(List.of(PHOTO_ID));
        Mockito.verify(readThroughCache).invalidate("omninest:dashboard:photo:" + OWNER_ID);
        Mockito.verify(itemRepository).deleteAllInBatch(List.of(photo));
        Mockito.verify(albumRepository).saveAll(List.of(album));
        org.assertj.core.api.Assertions.assertThat(coverReference.getCoverFileId()).isNull();
        org.assertj.core.api.Assertions.assertThat(editedReference.getActiveFileId()).isNull();
        org.assertj.core.api.Assertions.assertThat(motionReference.getMotionVideoFileNodeId()).isNull();
        org.assertj.core.api.Assertions.assertThat(albumCoverReference.getCoverFileId()).isNull();
        Mockito.verify(syncEventService).record(
                OWNER_ID,
                SyncScope.PHOTOS,
                "PHOTO_ITEM",
                PHOTO_ID.toString(),
                SyncAction.DELETED,
                3L,
                Map.of()
        );
        assertThat(album.getPhotoCount()).isEqualTo(2);
        assertThat(coverReference.getCoverFileId()).isNull();
    }

    @Test
    void softDeletePreservesPhotoMetadata() {
        service.handleFileNodesSoftDeleted(new FileNodesSoftDeletedEvent(
                OWNER_ID,
                List.of(FILE_NODE_ID),
                Instant.now()
        ));

        Mockito.verify(itemRepository, Mockito.never()).deleteAllInBatch(Mockito.anyList());
        Mockito.verifyNoInteractions(
                tagRepository,
                editVersionRepository,
                contentLabelRepository,
                contentAnalysisRunRepository
        );
    }

    @Test
    void visibilityChangeInvalidatesAffectedPhotoOwner() {
        PhotoItem photo = new PhotoItem();
        photo.setOwnerUserId(OWNER_ID);
        Mockito.when(itemRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID)))
                .thenReturn(List.of(photo));

        service.invalidateFileVisibility(List.of(FILE_NODE_ID));

        Mockito.verify(syncEventService).invalidate(
                OWNER_ID,
                SyncScope.PHOTOS,
                "PHOTO_LIBRARY",
                Map.of("reason", "FILE_VISIBILITY_CHANGED")
        );
    }

    private PurgeContext purgeContext() {
        return new PurgeContext(UUID.randomUUID(), OWNER_ID, FILE_NODE_ID, List.of(FILE_NODE_ID));
    }
}
