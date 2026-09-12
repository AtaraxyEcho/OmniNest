package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.service.ResourceShareLinkService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.domain.PhotoAlbum;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoAlbumDetailDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoItemDto;
import com.omninest.modules.photos.repository.PhotoAlbumItemRepository;
import com.omninest.modules.photos.repository.PhotoAlbumRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;

@ExtendWith(MockitoExtension.class)
class PhotoAlbumServiceTest {

    private static final UUID OWNER = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ALBUM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID PHOTO_1 = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID PHOTO_2 = UUID.fromString("30000000-0000-0000-0000-000000000002");

    @Mock
    private PhotoAlbumRepository albumRepository;
    @Mock
    private PhotoAlbumItemRepository albumItemRepository;
    @Mock
    private PhotoItemRepository photoItemRepository;
    @Mock
    private PhotoLibraryService libraryService;
    @Mock
    private ResourceShareLinkService resourceShareLinkService;
    @Mock
    private MediaSyncEventService syncEventService;

    @InjectMocks
    private PhotoAlbumService service;

    private PhotoAlbum album() {
        PhotoAlbum album = new PhotoAlbum();
        album.setId(ALBUM_ID);
        album.setOwnerUserId(OWNER);
        album.setName("Trip");
        album.setPhotoCount(2);
        return album;
    }

    private PhotoItemDto photoDto(UUID id) {
        PhotoItem item = new PhotoItem();
        item.setId(id);
        item.setFileNodeId(id);
        item.setTitle("t");
        item.setFormat("JPEG");
        item.setFileSize(1L);
        item.setMetadataStatus("READY");
        return PhotoItemDto.fromEntity(item, null, false, List.of());
    }

    @Test
    void albumDetail_returnsOnlyFirstPageOfPhotos() {
        when(albumRepository.findByOwnerUserIdAndId(OWNER, ALBUM_ID))
                .thenReturn(Optional.of(album()));
        when(albumItemRepository.findPhotoIdsByAlbumId(eq(ALBUM_ID), any(PageRequest.class)))
                .thenReturn(List.of(PHOTO_1));
        when(libraryService.listPhotosByIds(OWNER, List.of(PHOTO_1)))
                .thenReturn(List.of(photoDto(PHOTO_1)));

        PhotoAlbumDetailDto detail = service.albumDetail(OWNER, ALBUM_ID);

        assertThat(detail.photos()).hasSize(1);
        assertThat(detail.album().photoCount()).isEqualTo(2);
    }

    @Test
    void albumPhotosPage_preservesAlbumOrderAndTotal() {
        when(albumRepository.findByOwnerUserIdAndId(OWNER, ALBUM_ID))
                .thenReturn(Optional.of(album()));
        when(albumItemRepository.countByAlbumId(ALBUM_ID)).thenReturn(2L);
        when(albumItemRepository.findPhotoIdsByAlbumId(eq(ALBUM_ID), any(PageRequest.class)))
                .thenReturn(List.of(PHOTO_1, PHOTO_2));
        when(libraryService.listPhotosByIds(OWNER, List.of(PHOTO_1, PHOTO_2)))
                .thenReturn(List.of(photoDto(PHOTO_2), photoDto(PHOTO_1)));

        Page<PhotoItemDto> page = service.albumPhotosPage(OWNER, ALBUM_ID, 0, 50);

        assertThat(page.getTotalElements()).isEqualTo(2);
        assertThat(page.getContent()).extracting(PhotoItemDto::id)
                .containsExactly(PHOTO_1, PHOTO_2);
    }
}
