package com.omninest.modules.video.service;

import org.mockito.Mockito;
import java.util.List;
import java.time.Instant;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.service.DerivedAssetRequest;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.video.domain.ContentAsset;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.ScrapeCandidateDto;
import com.omninest.modules.video.repository.ContentAssetRepository;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;
import org.mockito.ArgumentCaptor;

class ContentAssetServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID VIDEO_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");

    private final ContentAssetRepository contentAssetRepository = mock(ContentAssetRepository.class);
    private final FileQueryService fileQueryService =
            mock(FileQueryService.class);
    private final DerivedAssetStorageService derivedAssetStorageService =
            mock(DerivedAssetStorageService.class);
    private final PlatformTransactionManager transactionManager =
            mock(PlatformTransactionManager.class);
    private final ContentAssetService contentAssetService =
            new ContentAssetService(contentAssetRepository, fileQueryService, derivedAssetStorageService, transactionManager);

    @Test
    void syncPrimaryMovieAssetsStoresLocalFilesAndCreatesContentAssets() {
        UUID movieId = UUID.fromString("60000000-0000-0000-0000-000000000002");
        UUID posterFileId = UUID.fromString("70000000-0000-0000-0000-000000000001");
        UUID backdropFileId = UUID.fromString("80000000-0000-0000-0000-000000000001");
        ScrapeCandidateDto candidate = new ScrapeCandidateDto(
                "TMDB",
                "123",
                "飞驰人生",
                "Pegasus",
                null,
                2024,
                "简介",
                "https://image.tmdb.org/t/p/w500/poster.jpg",
                "https://image.tmdb.org/t/p/w1280/backdrop.jpg",
                null,
                7.5,
                null,
                null, null, null, null, null, null, null, null, null, null, null
        );
        when(contentAssetRepository.findPrimaryAsset(
                any(), any(), any(), any()
        )).thenReturn(Optional.empty());
        when(derivedAssetStorageService.storeRemote(any()))
                .thenAnswer(invocation -> {
                    var request = invocation.getArgument(0, DerivedAssetRequest.class);
                    return "POSTER".equals(request.assetType()) ? posterFileId : backdropFileId;
                });

        var result = contentAssetService.syncPrimaryMovieAssets(movieId, OWNER_ID, candidate);

        assertThat(result.posterFileId()).isEqualTo(posterFileId);
        assertThat(result.backdropFileId()).isEqualTo(backdropFileId);

        ArgumentCaptor<ContentAsset> captor = ArgumentCaptor.forClass(ContentAsset.class);
        verify(contentAssetRepository, Mockito.times(2)).save(captor.capture());
        verify(derivedAssetStorageService, Mockito.times(2)).storeRemote(any());
        assertThat(captor.getAllValues())
                .extracting(ContentAsset::getAssetType)
                .containsExactlyInAnyOrder("POSTER", "BACKDROP");
        assertThat(captor.getAllValues())
                .extracting(ContentAsset::getFileNodeId)
                .containsExactlyInAnyOrder(posterFileId, backdropFileId);
        assertThat(captor.getAllValues())
                .allSatisfy(asset -> {
                    assertThat(asset.getOwnerUserId()).isEqualTo(OWNER_ID);
                    assertThat(asset.getResourceType()).isEqualTo("MOVIE");
                    assertThat(asset.getResourceId()).isEqualTo(movieId);
                    assertThat(asset.isPrimary()).isTrue();
                    assertThat(asset.getProvider()).isEqualTo("TMDB");
                    assertThat(asset.getMetadata()).containsEntry("externalId", "123");
                });
    }

    @Test
    void screenshotDownloadsRespectConfiguredConcurrency() {
        contentAssetService.screenshotDownloadConcurrency = 2;
        when(contentAssetRepository.findByOwnerUserIdAndResourceTypeAndResourceIdAndAssetType(
                OWNER_ID, "VIDEO_ITEM", VIDEO_ID, "SCREENSHOT"))
                .thenReturn(List.of());
        java.util.concurrent.atomic.AtomicInteger active = new java.util.concurrent.atomic.AtomicInteger();
        java.util.concurrent.atomic.AtomicInteger maxActive = new java.util.concurrent.atomic.AtomicInteger();
        when(derivedAssetStorageService.storeRemote(any())).thenAnswer(invocation -> {
            int current = active.incrementAndGet();
            maxActive.accumulateAndGet(current, Math::max);
            try {
                Thread.sleep(30);
            } finally {
                active.decrementAndGet();
            }
            return UUID.randomUUID();
        });
        when(transactionManager.getTransaction(any()))
                .thenReturn(mock(TransactionStatus.class));
        var item = new MediaVideoItem();
        item.setId(VIDEO_ID);
        item.setOwnerUserId(OWNER_ID);

        contentAssetService.syncVideoScreenshots(
                item,
                List.of("https://cdn/1.jpg", "https://cdn/2.jpg", "https://cdn/3.jpg",
                        "https://cdn/4.jpg", "https://cdn/5.jpg", "https://cdn/6.jpg"),
                "TMDB",
                "123"
        );

        assertThat(maxActive.get()).isLessThanOrEqualTo(2);
        verify(contentAssetRepository, Mockito.times(6)).save(any(ContentAsset.class));
    }

    @Test
    void assetUrlPrefersLocalFileOverExternalUrl() {
        UUID posterFileId = UUID.fromString("70000000-0000-0000-0000-000000000001");
        ContentAsset asset = new ContentAsset();
        asset.setId(UUID.fromString("90000000-0000-0000-0000-000000000001"));
        asset.setOwnerUserId(OWNER_ID);
        asset.setResourceType("VIDEO_ITEM");
        asset.setResourceId(VIDEO_ID);
        asset.setAssetType("POSTER");
        asset.setFileNodeId(posterFileId);
        asset.setExternalUrl("https://image.tmdb.org/t/p/w500/poster.jpg");
        asset.setPrimary(true);
        when(contentAssetRepository.listPrimaryAssets(
                eq(OWNER_ID),
                eq("VIDEO_ITEM"),
                any(),
                any()
        )).thenReturn(List.of(asset));
        when(fileQueryService.createDownloadUrl(OWNER_ID, posterFileId))
                .thenReturn(new FileDownloadUrlDto(
                        posterFileId,
                        "poster.jpg",
                        "http://localhost:9000/user-files/poster.jpg",
                        Instant.parse("2026-05-22T12:00:00Z")
                ));

        var assets = contentAssetService.primaryVideoAssets(OWNER_ID, List.of(VIDEO_ID));

        assertThat(assets.get(VIDEO_ID).get("POSTER").url())
                .isEqualTo("http://localhost:9000/user-files/poster.jpg");
    }
}
