package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.service.FileContentAccessService;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.modules.video.domain.ContentAsset;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.ContentAssetRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class MediaContentAccessServiceTest {
    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID MOVIE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");

    private final MediaVideoItemRepository videoItemRepository = mock(MediaVideoItemRepository.class);
    private final MediaTvSeriesRepository seriesRepository = mock(MediaTvSeriesRepository.class);
    private final MediaLibraryAccessService libraryAccessService = mock(MediaLibraryAccessService.class);
    private final FileContentAccessService fileContentAccessService = mock(FileContentAccessService.class);
    private final MediaPlaybackTokenService tokenService = mock(MediaPlaybackTokenService.class);
    private final ContentAssetRepository contentAssetRepository = mock(ContentAssetRepository.class);
    private final MediaContentAccessService service = new MediaContentAccessService(
            videoItemRepository,
            seriesRepository,
            libraryAccessService,
            fileContentAccessService,
            tokenService,
            contentAssetRepository
    );

    @Test
    void revokedLibraryAccessBlocksAssetEvenWhenTokenStillExists() {
        MediaVideoItem item = item();
        when(tokenService.requireGrant("token", ITEM_ID)).thenReturn(new MediaPlaybackTokenService.MediaGrant(
                USER_ID,
                "VIDEO_ITEM",
                ITEM_ID,
                Instant.now().plusSeconds(60)
        ));
        when(videoItemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(libraryAccessService.requireRead(USER_ID, SOURCE_ID))
                .thenThrow(new BusinessException(ErrorCode.FORBIDDEN, "授权已撤销"));

        assertThatThrownBy(() -> service.openVideoAsset("token", ITEM_ID, FILE_ID))
                .isInstanceOf(BusinessException.class);
        verify(fileContentAccessService, never()).openAuthorizedMediaStream(any(), any());
    }

    @Test
    void videoTokenCannotReadUnrelatedAsset() {
        MediaVideoItem item = item();
        ContentAsset asset = new ContentAsset();
        asset.setResourceType(ResourceType.MOVIE.getValue());
        asset.setResourceId(UUID.randomUUID());
        when(tokenService.requireGrant("token", ITEM_ID)).thenReturn(new MediaPlaybackTokenService.MediaGrant(
                USER_ID,
                "VIDEO_ITEM",
                ITEM_ID,
                Instant.now().plusSeconds(60)
        ));
        when(videoItemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(contentAssetRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID)).thenReturn(List.of(asset));

        assertThatThrownBy(() -> service.openVideoAsset("token", ITEM_ID, FILE_ID))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
    }

    @Test
    void personalMediaStillRejectsAUserWhoIsNotTheOwner() {
        MediaVideoItem item = item();
        item.setLibrarySourceId(null);
        when(videoItemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));

        assertThatThrownBy(() -> service.requireReadableVideo(USER_ID, ITEM_ID))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.MEDIA_NOT_FOUND));

        verify(libraryAccessService).requireReadPermission(USER_ID);
        verify(libraryAccessService, never()).requireRead(any(), any());
    }

    @Test
    void webmFamilyMatroskaServedAsVideoWebm() {
        MediaVideoItem item = item();
        item.setOwnerUserId(USER_ID);
        item.setLibrarySourceId(null);
        item.setContainerFormat("matroska,webm");
        item.setVideoCodec("av1");
        item.setAudioCodec("opus");
        when(tokenService.requireGrant("token", ITEM_ID)).thenReturn(new MediaPlaybackTokenService.MediaGrant(
                USER_ID,
                "VIDEO_ITEM",
                ITEM_ID,
                Instant.now().plusSeconds(60)
        ));
        when(videoItemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(fileContentAccessService.openAuthorizedMediaResource(FILE_ID, com.omninest.modules.file.domain.MediaContentPurpose.MEDIA_PLAYBACK))
                .thenReturn(new com.omninest.modules.file.dto.FileContentResource(
                        new org.springframework.core.io.ByteArrayResource(new byte[0]),
                        "night.webm",
                        1L,
                        "video/x-matroska"
                ));

        var content = service.openPlaybackContent("token", ITEM_ID);

        assertThat(content.mimeType()).isEqualTo("video/webm");
    }

    private MediaVideoItem item() {
        MediaVideoItem item = new MediaVideoItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setMovieId(MOVIE_ID);
        item.setLibrarySourceId(SOURCE_ID);
        item.setFileNodeId(FILE_ID);
        return item;
    }
}
