package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FilePurgeOrigin;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoTrashResultDto;
import com.omninest.modules.photos.dto.GroupBy;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoGroupDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoItemDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoListItemDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoTimelineMonthDto;
import com.omninest.modules.photos.repository.PhotoAlbumItemRepository;
import com.omninest.modules.photos.repository.PhotoAlbumRepository;
import com.omninest.modules.photos.repository.PhotoFavoriteRepository;
import com.omninest.modules.photos.repository.PhotoGroupPreviewProjection;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoListItemProjection;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.repository.PhotoTimelinePreviewProjection;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;

/**
 * PhotoLibraryService 单元测试。
 * 覆盖照片列表和搜索功能。
 *
 * @author OmniNest
 */
class PhotoLibraryServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID PHOTO_ID_1 = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID PHOTO_ID_2 = UUID.fromString("20000000-0000-0000-0000-000000000002");
    private static final UUID FILE_NODE_ID_1 = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID_2 = UUID.fromString("30000000-0000-0000-0000-000000000002");
    private static final UUID COVER_FILE_ID_1 = UUID.fromString("50000000-0000-0000-0000-000000000001");
    private static final UUID COVER_FILE_ID_2 = UUID.fromString("50000000-0000-0000-0000-000000000002");

    private PhotoItemRepository photoItemRepository;
    private PhotoFavoriteRepository favoriteRepository;
    private PhotoAlbumRepository albumRepository;
    private PhotoAlbumItemRepository albumItemRepository;
    private PhotoTagRepository photoTagRepository;
    private PhotoSearchIndexService photoSearchIndexService;
    private FileDeletionService fileDeletionService;
    private FileQueryService fileQueryService;
    private ReadThroughCache readThroughCache;
    private MediaSyncEventService syncEventService;
    private PhotoContentAnalysisService contentAnalysisService;
    private PhotoGeoService photoGeoService;

    private PhotoLibraryService service;

    @BeforeEach
    void setUp() {
        photoItemRepository = mock(PhotoItemRepository.class);
        favoriteRepository = mock(PhotoFavoriteRepository.class);
        albumRepository = mock(PhotoAlbumRepository.class);
        albumItemRepository = mock(PhotoAlbumItemRepository.class);
        photoTagRepository = mock(PhotoTagRepository.class);
        photoSearchIndexService = mock(PhotoSearchIndexService.class);
        fileDeletionService = mock(FileDeletionService.class);
        fileQueryService = mock(FileQueryService.class);
        readThroughCache = mock(ReadThroughCache.class);
        syncEventService = mock(MediaSyncEventService.class);
        contentAnalysisService = mock(PhotoContentAnalysisService.class);
        photoGeoService = mock(PhotoGeoService.class);

        service = new PhotoLibraryService(
                photoItemRepository,
                favoriteRepository,
                albumRepository,
                albumItemRepository,
                photoTagRepository,
                photoSearchIndexService,
                fileDeletionService,
                fileQueryService,
                readThroughCache,
                syncEventService,
                contentAnalysisService,
                photoGeoService
        );
    }

    @Test
    void deletePhotoMovesPhotoIntoTrashInsteadOfPurging() {
        PhotoItem photo = photoItem(PHOTO_ID_1, FILE_NODE_ID_1, COVER_FILE_ID_1, "待删除照片");
        photo.setDeletedAt(null);
        when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID_1)).thenReturn(Optional.of(photo));

        service.movePhotoToTrash(OWNER_ID, PHOTO_ID_1);

        assertThat(photo.getDeletedAt()).isNotNull();
        verify(photoItemRepository).save(photo);
        verify(fileDeletionService, Mockito.never()).deletePermanently(
                any(), any(), anyBoolean(), any(), any()
        );
        verify(photoItemRepository, Mockito.never()).delete(photo);
    }

    @Test
    void purgePhotoFromTrashCreatesPermanentPurgeTask() {
        PhotoItem photo = photoItem(PHOTO_ID_1, FILE_NODE_ID_1, COVER_FILE_ID_1, "回收站照片");
        photo.setDeletedAt(Instant.now());
        UUID taskId = UUID.fromString("40000000-0000-0000-0000-000000000002");
        when(photoItemRepository.findTrashedByOwnerUserIdAndId(OWNER_ID, PHOTO_ID_1))
                .thenReturn(Optional.of(photo));
        when(fileDeletionService.deletePermanently(
                eq(OWNER_ID),
                eq(FILE_NODE_ID_1),
                eq(false),
                any(FilePurgeOrigin.class),
                isNull()
        )).thenReturn(taskId);

        UUID result = service.purgePhotoFromTrash(OWNER_ID, PHOTO_ID_1, false);

        assertThat(result).isEqualTo(taskId);
        verify(fileDeletionService).deletePermanently(
                eq(OWNER_ID),
                eq(FILE_NODE_ID_1),
                eq(false),
                any(FilePurgeOrigin.class),
                isNull()
        );
    }

    @Test
    void restorePhotoFromTrashClearsDeletedAt() {
        PhotoItem photo = photoItem(PHOTO_ID_1, FILE_NODE_ID_1, COVER_FILE_ID_1, "回收站照片");
        photo.setDeletedAt(Instant.now());
        when(photoItemRepository.findTrashedByOwnerUserIdAndId(OWNER_ID, PHOTO_ID_1))
                .thenReturn(Optional.of(photo));

        service.restorePhotoFromTrash(OWNER_ID, PHOTO_ID_1);

        assertThat(photo.getDeletedAt()).isNull();
        verify(photoItemRepository).save(photo);
    }

    @Test
    void movePhotosToTrashMarksEachPhotoDeleted() {
        PhotoItem firstPhoto = photoItem(PHOTO_ID_1, FILE_NODE_ID_1, COVER_FILE_ID_1, "第一张照片");
        PhotoItem secondPhoto = photoItem(PHOTO_ID_2, FILE_NODE_ID_2, COVER_FILE_ID_2, "第二张照片");
        when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID_1))
                .thenReturn(Optional.of(firstPhoto));
        when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID_2))
                .thenReturn(Optional.of(secondPhoto));

        List<PhotoTrashResultDto> results = service.movePhotosToTrash(
                OWNER_ID,
                List.of(PHOTO_ID_1, PHOTO_ID_2)
        );

        assertThat(results).hasSize(2);
        assertThat(results.stream().allMatch(PhotoTrashResultDto::success)).isTrue();
        assertThat(firstPhoto.getDeletedAt()).isNotNull();
        assertThat(secondPhoto.getDeletedAt()).isNotNull();
        verify(photoItemRepository, Mockito.times(2)).save(any(PhotoItem.class));
        verify(fileDeletionService, Mockito.never()).deletePermanentlyBatch(
                any(), any(), anyBoolean(), any()
        );
    }

    @Test
    void listPhotos_returnsUserPhotos() {
        // 验证 listPhotos 返回指定用户的照片列表
        PhotoItem photo1 = photoItem(PHOTO_ID_1, FILE_NODE_ID_1, COVER_FILE_ID_1, "风景照片");
        PhotoItem photo2 = photoItem(PHOTO_ID_2, FILE_NODE_ID_2, COVER_FILE_ID_2, "人物照片");

        when(photoItemRepository.findByOwnerUserIdOrderByCreatedAtDesc(OWNER_ID))
                .thenReturn(List.of(photo1, photo2));
        when(favoriteRepository.findPhotoIdsByOwnerUserIdAndPhotoIdIn(
                OWNER_ID, List.of(PHOTO_ID_1, PHOTO_ID_2)))
                .thenReturn(List.of());
        when(photoTagRepository.findByOwnerUserIdAndPhotoIdIn(
                OWNER_ID, List.of(PHOTO_ID_1, PHOTO_ID_2)))
                .thenReturn(List.of());
        when(fileQueryService.createDownloadUrls(eq(OWNER_ID), any()))
                .thenReturn(Map.of(
                        COVER_FILE_ID_1,
                        downloadUrl(COVER_FILE_ID_1, "photo1.jpg", "http://minio/photo1"),
                        COVER_FILE_ID_2,
                        downloadUrl(COVER_FILE_ID_2, "photo2.jpg", "http://minio/photo2")));

        List<PhotoItemDto> result = service.listPhotos(OWNER_ID);

        // 验证返回两张照片
        assertThat(result).hasSize(2);
        assertThat(result).extracting(PhotoItemDto::title).containsExactly("风景照片", "人物照片");

        // 验证非收藏状态
        assertThat(result).allSatisfy(dto -> assertThat(dto.favorite()).isFalse());

        // 验证缩略图 URL 已解析
        assertThat(result).allSatisfy(dto -> assertThat(dto.coverUrl()).isNotBlank());
        assertThat(result).allSatisfy(dto -> assertThat(dto.sourceUrl()).isNull());
    }

    @Test
    void photoDetail_returnsSourceUrlWithoutExpandingListPayload() {
        PhotoItem photo = photoItem(PHOTO_ID_1, FILE_NODE_ID_1, COVER_FILE_ID_1, "详情照片");
        when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID_1))
                .thenReturn(Optional.of(photo));
        when(favoriteRepository.existsByOwnerUserIdAndPhotoId(OWNER_ID, PHOTO_ID_1))
                .thenReturn(false);
        when(photoTagRepository.findByOwnerUserIdAndPhotoId(OWNER_ID, PHOTO_ID_1))
                .thenReturn(List.of());
        when(fileQueryService.createDownloadUrl(OWNER_ID, COVER_FILE_ID_1))
                .thenReturn(downloadUrl(COVER_FILE_ID_1, "photo1-thumb.jpg", "http://minio/photo1-thumb"));
        when(fileQueryService.createDownloadUrl(OWNER_ID, FILE_NODE_ID_1))
                .thenReturn(downloadUrl(FILE_NODE_ID_1, "photo1.jpg", "http://minio/photo1-source"));

        PhotoItemDto result = service.photo(OWNER_ID, PHOTO_ID_1);

        assertThat(result.coverUrl()).isEqualTo("http://minio/photo1-thumb");
        assertThat(result.sourceUrl()).isEqualTo("http://minio/photo1-source");
    }

    @Test
    void searchPhotos_delegatesToLuceneFirst() {
        // 验证搜索优先使用 Lucene 全文索引，有结果时不再回退到 SQL
        PhotoItem photo1 = photoItem(PHOTO_ID_1, FILE_NODE_ID_1, COVER_FILE_ID_1, "日落风景");

        when(photoSearchIndexService.search(OWNER_ID, "sunset", 200))
                .thenReturn(List.of(PHOTO_ID_1));
        when(photoItemRepository.findActiveByOwnerUserIdAndIdIn(OWNER_ID, List.of(PHOTO_ID_1)))
                .thenReturn(List.of(photo1));
        when(favoriteRepository.findPhotoIdsByOwnerUserIdAndPhotoIdIn(OWNER_ID, List.of(PHOTO_ID_1)))
                .thenReturn(List.of());
        when(photoTagRepository.findByOwnerUserIdAndPhotoIdIn(OWNER_ID, List.of(PHOTO_ID_1)))
                .thenReturn(List.of());
        when(fileQueryService.createDownloadUrl(OWNER_ID, COVER_FILE_ID_1))
                .thenReturn(downloadUrl(COVER_FILE_ID_1, "photo1.jpg", "http://minio/photo1"));

        List<PhotoItemDto> result = service.searchPhotos(OWNER_ID, "sunset");

        // 验证 Lucene 搜索被调用
        verify(photoSearchIndexService).search(OWNER_ID, "sunset", 200);

        // 验证 SQL 模糊搜索未被调用（Lucene 已返回结果）
        verify(photoItemRepository, Mockito.never())
                .searchByOwnerUserIdAndKeyword(any(), any(), any(Pageable.class));

        // 验证返回 Lucene 命中的照片
        assertThat(result).hasSize(1);
        assertThat(result.getFirst().id()).isEqualTo(PHOTO_ID_1);
        assertThat(result.getFirst().title()).isEqualTo("日落风景");
    }

    @Test
    void listPhotosPage_returnsBoundedProjectionPage() {
        PhotoListItemProjection projection = photoProjection(PHOTO_ID_1, "分页照片");
        when(photoItemRepository.findListPage(eq(OWNER_ID), any(Pageable.class)))
                .thenAnswer(invocation -> {
                    Pageable pageable = invocation.getArgument(1);
                    return new PageImpl<>(List.of(projection), pageable, 120);
                });
        when(favoriteRepository.findPhotoIdsByOwnerUserIdAndPhotoIdIn(OWNER_ID, List.of(PHOTO_ID_1)))
                .thenReturn(List.of(PHOTO_ID_1));
        when(photoTagRepository.findByOwnerUserIdAndPhotoIdIn(OWNER_ID, List.of(PHOTO_ID_1)))
                .thenReturn(List.of());
        when(fileQueryService.createDownloadUrls(eq(OWNER_ID), any()))
                .thenReturn(Map.of(
                        COVER_FILE_ID_1,
                        new FileDownloadUrlDto(
                                COVER_FILE_ID_1,
                                "photo1.jpg",
                                "http://minio/photo1",
                                Instant.now().plusSeconds(900)
                        )));

        Page<PhotoListItemDto> result = service.listPhotosPage(
                OWNER_ID,
                0,
                50,
                "createdAt,desc",
                null
        );

        assertThat(result.getTotalElements()).isEqualTo(120);
        assertThat(result.getSize()).isEqualTo(50);
        assertThat(result.getContent()).singleElement().satisfies(item -> {
            assertThat(item.id()).isEqualTo(PHOTO_ID_1);
            assertThat(item.title()).isEqualTo("分页照片");
            assertThat(item.favorite()).isTrue();
            assertThat(item.coverUrl()).isEqualTo("http://minio/photo1");
        });
    }

    @Test
    void listPhotosPage_usesSearchQueryOnlyForNonBlankKeyword() {
        when(photoItemRepository.searchListPage(eq(OWNER_ID), eq("sunset"), any(Pageable.class)))
                .thenAnswer(invocation -> new PageImpl<>(List.of(), invocation.getArgument(2), 0));

        service.listPhotosPage(OWNER_ID, 0, 50, "createdAt,desc", "  sunset  ");

        verify(photoItemRepository).searchListPage(eq(OWNER_ID), eq("sunset"), any(Pageable.class));
        verify(photoItemRepository, Mockito.never()).findListPage(any(), any(Pageable.class));
    }

    @Test
    void listFavoritesPage_selectsTypedQueryBranch() {
        when(photoItemRepository.findFavoriteListPage(eq(OWNER_ID), any(Pageable.class)))
                .thenAnswer(invocation -> new PageImpl<>(List.of(), invocation.getArgument(1), 0));
        when(photoItemRepository.searchFavoriteListPage(eq(OWNER_ID), eq("night"), any(Pageable.class)))
                .thenAnswer(invocation -> new PageImpl<>(List.of(), invocation.getArgument(2), 0));

        service.listFavoritesPage(OWNER_ID, 0, 50, "createdAt,desc", null);
        service.listFavoritesPage(OWNER_ID, 0, 50, "createdAt,desc", "night");

        verify(photoItemRepository).findFavoriteListPage(eq(OWNER_ID), any(Pageable.class));
        verify(photoItemRepository).searchFavoriteListPage(eq(OWNER_ID), eq("night"), any(Pageable.class));
    }

    @Test
    void listPhotosPage_rejectsUnknownSortField() {
        assertThatThrownBy(() -> service.listPhotosPage(
                OWNER_ID,
                0,
                50,
                "providerMetadata,asc",
                null
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("照片排序字段不合法");
    }

    @Test
    void timelinePage_groupsBoundedMonthPreviews() {
        PhotoTimelinePreviewProjection mayFirst = timelineProjection(PHOTO_ID_1, 2026, 5, 12);
        PhotoTimelinePreviewProjection maySecond = timelineProjection(PHOTO_ID_2, 2026, 5, 12);
        when(photoItemRepository.findTimelinePreviewPage(eq(OWNER_ID), anyString(), eq(100L), eq(100)))
                .thenReturn(List.of(mayFirst, maySecond));
        when(photoItemRepository.countTimelineMonths(eq(OWNER_ID), anyString())).thenReturn(240L);
        when(favoriteRepository.findPhotoIdsByOwnerUserIdAndPhotoIdIn(
                OWNER_ID,
                List.of(PHOTO_ID_1, PHOTO_ID_2)
        )).thenReturn(List.of());
        when(photoTagRepository.findByOwnerUserIdAndPhotoIdIn(
                OWNER_ID,
                List.of(PHOTO_ID_1, PHOTO_ID_2)
        )).thenReturn(List.of());
        when(fileQueryService.createDownloadUrl(OWNER_ID, COVER_FILE_ID_1))
                .thenReturn(downloadUrl(COVER_FILE_ID_1, "photo1.jpg", "http://minio/photo1"));

        Page<PhotoTimelineMonthDto> result = service.timelinePage(OWNER_ID, 1, 500);

        assertThat(result.getSize()).isEqualTo(100);
        assertThat(result.getTotalElements()).isEqualTo(240);
        assertThat(result.getContent()).singleElement().satisfies(month -> {
            assertThat(month.year()).isEqualTo(2026);
            assertThat(month.month()).isEqualTo(5);
            assertThat(month.photoCount()).isEqualTo(12);
            assertThat(month.previewPhotos()).hasSize(2);
        });
        verify(photoItemRepository).findTimelinePreviewPage(eq(OWNER_ID), anyString(), eq(100L), eq(100));
    }

    @Test
    void groupByPage_usesDatabaseAggregationAndBoundsPageSize() {
        PhotoGroupPreviewProjection projection = groupProjection(PHOTO_ID_1, "jpg", 80);
        when(photoItemRepository.findGroupPreviewPage(
                eq(OWNER_ID),
                eq("FORMAT"),
                anyString(),
                eq(100L),
                eq(100)
        )).thenReturn(List.of(projection));
        when(photoItemRepository.countPhotoGroups(eq(OWNER_ID), eq("FORMAT"), anyString()))
                .thenReturn(205L);
        when(favoriteRepository.findPhotoIdsByOwnerUserIdAndPhotoIdIn(OWNER_ID, List.of(PHOTO_ID_1)))
                .thenReturn(List.of());
        when(photoTagRepository.findByOwnerUserIdAndPhotoIdIn(OWNER_ID, List.of(PHOTO_ID_1)))
                .thenReturn(List.of());
        when(fileQueryService.createDownloadUrl(OWNER_ID, COVER_FILE_ID_1))
                .thenReturn(downloadUrl(COVER_FILE_ID_1, "photo1.jpg", "http://minio/photo1"));

        Page<PhotoGroupDto> result = service.groupByPage(OWNER_ID, GroupBy.FORMAT, 1, 500);

        assertThat(result.getSize()).isEqualTo(100);
        assertThat(result.getTotalElements()).isEqualTo(205);
        assertThat(result.getContent()).singleElement().satisfies(group -> {
            assertThat(group.groupKey()).isEqualTo("jpg");
            assertThat(group.photoCount()).isEqualTo(80);
            assertThat(group.photos()).singleElement().satisfies(photo ->
                    assertThat(photo.id()).isEqualTo(PHOTO_ID_1));
        });
        verify(photoItemRepository).findGroupPreviewPage(
                eq(OWNER_ID),
                eq("FORMAT"),
                anyString(),
                eq(100L),
                eq(100)
        );
    }

    // ── 辅助方法 ──

    private PhotoItem photoItem(UUID id, UUID fileNodeId, UUID coverFileId, String title) {
        PhotoItem photo = new PhotoItem();
        photo.setId(id);
        photo.setOwnerUserId(OWNER_ID);
        photo.setFileNodeId(fileNodeId);
        photo.setCoverFileId(coverFileId);
        photo.setTitle(title);
        photo.setFileSize(1024L);
        photo.setMetadataStatus("MATCHED");
        photo.setProviderMetadata(new HashMap<>());
        photo.setGpsLocation(new HashMap<>());
        photo.setCreatedAt(Instant.parse("2026-05-01T10:00:00Z"));
        photo.setUpdatedAt(Instant.parse("2026-05-01T10:00:00Z"));
        return photo;
    }

    private PhotoListItemProjection photoProjection(UUID id, String title) {
        PhotoListItemProjection projection = mock(PhotoListItemProjection.class);
        when(projection.getId()).thenReturn(id);
        when(projection.getOwnerUserId()).thenReturn(OWNER_ID);
        when(projection.getFileNodeId()).thenReturn(FILE_NODE_ID_1);
        when(projection.getTitle()).thenReturn(title);
        when(projection.getWidth()).thenReturn(1920);
        when(projection.getHeight()).thenReturn(1080);
        when(projection.getFormat()).thenReturn("jpg");
        when(projection.getFileSize()).thenReturn(1024L);
        when(projection.getCoverFileId()).thenReturn(COVER_FILE_ID_1);
        when(projection.getMetadataStatus()).thenReturn("MATCHED");
        when(projection.getCreatedAt()).thenReturn(Instant.parse("2026-05-01T10:00:00Z"));
        return projection;
    }

    private PhotoTimelinePreviewProjection timelineProjection(UUID id, int year, int month, long photoCount) {
        PhotoTimelinePreviewProjection projection = mock(PhotoTimelinePreviewProjection.class);
        when(projection.getId()).thenReturn(id);
        when(projection.getOwnerUserId()).thenReturn(OWNER_ID);
        when(projection.getFileNodeId()).thenReturn(FILE_NODE_ID_1);
        when(projection.getTitle()).thenReturn("时间线照片");
        when(projection.getWidth()).thenReturn(1920);
        when(projection.getHeight()).thenReturn(1080);
        when(projection.getDateTaken()).thenReturn(Instant.parse("2026-05-01T10:00:00Z"));
        when(projection.getFormat()).thenReturn("jpg");
        when(projection.getFileSize()).thenReturn(1024L);
        when(projection.getCoverFileId()).thenReturn(COVER_FILE_ID_1);
        when(projection.getMetadataStatus()).thenReturn("MATCHED");
        when(projection.getCreatedAt()).thenReturn(Instant.parse("2026-05-01T10:00:00Z"));
        when(projection.getYear()).thenReturn(year);
        when(projection.getMonth()).thenReturn(month);
        when(projection.getPhotoCount()).thenReturn(photoCount);
        return projection;
    }

    private PhotoGroupPreviewProjection groupProjection(UUID id, String groupKey, long photoCount) {
        PhotoGroupPreviewProjection projection = mock(PhotoGroupPreviewProjection.class);
        when(projection.getId()).thenReturn(id);
        when(projection.getOwnerUserId()).thenReturn(OWNER_ID);
        when(projection.getFileNodeId()).thenReturn(FILE_NODE_ID_1);
        when(projection.getTitle()).thenReturn("分组照片");
        when(projection.getWidth()).thenReturn(1920);
        when(projection.getHeight()).thenReturn(1080);
        when(projection.getFormat()).thenReturn("jpg");
        when(projection.getFileSize()).thenReturn(1024L);
        when(projection.getCoverFileId()).thenReturn(COVER_FILE_ID_1);
        when(projection.getMetadataStatus()).thenReturn("MATCHED");
        when(projection.getCreatedAt()).thenReturn(Instant.parse("2026-05-01T10:00:00Z"));
        when(projection.getGroupKey()).thenReturn(groupKey);
        when(projection.getPhotoCount()).thenReturn(photoCount);
        return projection;
    }

    private FileDownloadUrlDto downloadUrl(UUID fileId, String fileName, String url) {
        return new FileDownloadUrlDto(fileId, fileName, url, Instant.now().plusSeconds(900));
    }
}
