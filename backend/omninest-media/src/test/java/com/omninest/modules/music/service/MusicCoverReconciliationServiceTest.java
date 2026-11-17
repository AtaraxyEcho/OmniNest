package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.service.DerivedAssetStorageService;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 校验封面派生资产对账：只回收超过宽限期且源封面已失效的节点。
 */
class MusicCoverReconciliationServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OTHER_OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID LIVE_COVER_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID DEAD_COVER_ID = UUID.fromString("20000000-0000-0000-0000-000000000002");
    private static final UUID LIVE_THUMBNAIL_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID DEAD_THUMBNAIL_ID = UUID.fromString("30000000-0000-0000-0000-000000000002");

    private static final Instant OLD = Instant.parse("2026-01-01T00:00:00Z");

    private final DerivedAssetStorageService derivedAssetStorageService =
            mock(DerivedAssetStorageService.class);
    private final MusicCoverRetentionService coverRetentionService = mock(MusicCoverRetentionService.class);
    private final MusicCoverReconciliationService service =
            new MusicCoverReconciliationService(derivedAssetStorageService, coverRetentionService);

    @Test
    void thumbnailOfUnreferencedCoverIsDeletedWhileLiveOneIsKept() {
        givenOwners(OWNER_ID);
        givenNodes(OWNER_ID,
                thumbnail(LIVE_THUMBNAIL_ID, LIVE_COVER_ID, OLD),
                thumbnail(DEAD_THUMBNAIL_ID, DEAD_COVER_ID, OLD));
        when(coverRetentionService.filterReferenced(eq(OWNER_ID), anyCollection()))
                .thenReturn(Set.of(LIVE_COVER_ID));

        service.reconcile();

        assertThat(deletedBatch(OWNER_ID)).containsExactly(DEAD_THUMBNAIL_ID);
    }

    @Test
    void unreferencedCoverNodeOlderThanGraceIsDeleted() {
        givenOwners(OWNER_ID);
        givenNodes(OWNER_ID, cover(DEAD_COVER_ID, OLD));
        when(coverRetentionService.filterReferenced(eq(OWNER_ID), anyCollection()))
                .thenReturn(Set.of());

        service.reconcile();

        assertThat(deletedBatch(OWNER_ID)).containsExactly(DEAD_COVER_ID);
    }

    @Test
    void coverNodeInsideTheGraceWindowIsLeftAlone() {
        givenOwners(OWNER_ID);
        givenNodes(OWNER_ID, cover(DEAD_COVER_ID, Instant.now()));

        service.reconcile();

        verify(derivedAssetStorageService, never()).deleteOwnedBatch(eq(OWNER_ID), anyCollection());
    }

    @Test
    void referencedCoverNodeIsKeptTogetherWithItsThumbnail() {
        givenOwners(OWNER_ID);
        givenNodes(OWNER_ID,
                cover(LIVE_COVER_ID, OLD),
                thumbnail(LIVE_THUMBNAIL_ID, LIVE_COVER_ID, OLD));
        when(coverRetentionService.filterReferenced(eq(OWNER_ID), anyCollection()))
                .thenReturn(Set.of(LIVE_COVER_ID));

        service.reconcile();

        verify(derivedAssetStorageService, never()).deleteOwnedBatch(eq(OWNER_ID), anyCollection());
    }

    @Test
    void unparsableResourceSegmentIsIgnored() {
        givenOwners(OWNER_ID);
        givenNodes(OWNER_ID, new DerivedAssetStorageService.DerivedNodeRef(
                LIVE_THUMBNAIL_ID,
                "/.metadata/MUSIC_COVER/not-a-uuid/THUMBNAIL/cover_300.jpg",
                OLD
        ));

        service.reconcile();

        verify(derivedAssetStorageService, never()).deleteOwnedBatch(eq(OWNER_ID), anyCollection());
    }

    @Test
    void oneFailingOwnerDoesNotBlockTheOthers() {
        givenOwners(OWNER_ID, OTHER_OWNER_ID);
        when(derivedAssetStorageService.listDerivedNodeRefs(OWNER_ID, "MUSIC_COVER"))
                .thenThrow(new IllegalStateException("storage unavailable"));
        givenNodes(OTHER_OWNER_ID, thumbnail(DEAD_THUMBNAIL_ID, DEAD_COVER_ID, OLD));
        when(coverRetentionService.filterReferenced(eq(OTHER_OWNER_ID), anyCollection()))
                .thenReturn(Set.of());

        assertThatCode(this::reconcile).doesNotThrowAnyException();
        assertThat(deletedBatch(OTHER_OWNER_ID)).containsExactly(DEAD_THUMBNAIL_ID);
    }

    private void reconcile() {
        service.reconcile();
    }

    private void givenOwners(UUID... ownerIds) {
        when(derivedAssetStorageService.listOwnerIdsByDerivedPathPrefix("MUSIC_COVER"))
                .thenReturn(List.of(ownerIds));
    }

    private void givenNodes(
            UUID ownerId,
            DerivedAssetStorageService.DerivedNodeRef... nodeRefs
    ) {
        when(derivedAssetStorageService.listDerivedNodeRefs(ownerId, "MUSIC_COVER"))
                .thenReturn(List.of(nodeRefs));
    }

    private DerivedAssetStorageService.DerivedNodeRef thumbnail(UUID nodeId, UUID sourceCoverId, Instant createdAt) {
        return new DerivedAssetStorageService.DerivedNodeRef(
                nodeId,
                "/.metadata/MUSIC_COVER/" + sourceCoverId + "/THUMBNAIL/cover_300.jpg",
                createdAt
        );
    }

    private DerivedAssetStorageService.DerivedNodeRef cover(UUID coverFileId, Instant createdAt) {
        // 封面本体的资源标识是来源音频节点，与封面自身无关，判活只看节点自身标识。
        return new DerivedAssetStorageService.DerivedNodeRef(
                coverFileId,
                "/.metadata/MUSIC_COVER/" + LIVE_COVER_ID + "/COVER/cover.jpg",
                createdAt
        );
    }

    private Collection<UUID> deletedBatch(UUID ownerId) {
        ArgumentCaptor<Collection<UUID>> captor = ArgumentCaptor.captor();
        verify(derivedAssetStorageService).deleteOwnedBatch(eq(ownerId), captor.capture());
        return captor.getValue();
    }
}
