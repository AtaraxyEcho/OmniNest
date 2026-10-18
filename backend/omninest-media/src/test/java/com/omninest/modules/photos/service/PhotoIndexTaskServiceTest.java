package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 照片搜索索引任务服务测试。
 *
 * @author OmniNest
 */
class PhotoIndexTaskServiceTest {
    private final PhotoItemRepository photoItemRepository = Mockito.mock(PhotoItemRepository.class);
    private final PhotoTagRepository photoTagRepository = Mockito.mock(PhotoTagRepository.class);
    private final PhotoSearchIndexService photoSearchIndexService = Mockito.mock(PhotoSearchIndexService.class);
    private final FileLifecycleGuard fileLifecycleGuard = Mockito.mock(FileLifecycleGuard.class);
    private final PhotoIndexTaskService service = new PhotoIndexTaskService(
            photoItemRepository,
            photoTagRepository,
            photoSearchIndexService,
            fileLifecycleGuard
    );

    @AfterEach
    void clearSynchronization() {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.clearSynchronization();
        }
    }

    @Test
    void indexLoadsOwnedPhotoAndTags() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(fileNodeId);
        photo.setTitle("Mountain");
        photo.setDescription("Sunrise");
        PhotoTag firstTag = new PhotoTag();
        firstTag.setTag("travel");
        PhotoTag secondTag = new PhotoTag();
        secondTag.setTag("sunrise");
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(photoTagRepository.findByOwnerUserIdAndPhotoId(ownerUserId, photoId))
                .thenReturn(List.of(firstTag, secondTag));
        Mockito.when(fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)).thenReturn(true);

        boolean indexed = service.index(ownerUserId, photoId);

        assertThat(indexed).isTrue();
        Mockito.verify(photoSearchIndexService).indexPhoto(
                photoId,
                ownerUserId,
                "Mountain",
                "Sunrise",
                List.of("travel", "sunrise")
        );
    }

    @Test
    void indexReturnsFalseWhenSourceFileIsPurging() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(fileNodeId);
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)).thenReturn(false);

        boolean indexed = service.index(ownerUserId, photoId);

        assertThat(indexed).isFalse();
        Mockito.verifyNoInteractions(photoTagRepository, photoSearchIndexService);
    }

    @Test
    void indexReturnsFalseWhenOwnedPhotoDoesNotExist() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.empty());

        boolean indexed = service.index(ownerUserId, photoId);

        assertThat(indexed).isFalse();
        Mockito.verifyNoInteractions(photoTagRepository, photoSearchIndexService);
    }

    @Test
    void scheduleIndexAfterCommitWaitsForCommitWhenTransactionActive() {
        IndexFixture fixture = stubIndexablePhoto();

        TransactionSynchronizationManager.initSynchronization();
        service.scheduleIndexAfterCommit(fixture.ownerUserId(), fixture.photoId());

        verify(photoSearchIndexService, never()).indexPhoto(
                Mockito.any(),
                Mockito.any(),
                Mockito.any(),
                Mockito.any(),
                anyList()
        );
        List<TransactionSynchronization> synchronizations =
                TransactionSynchronizationManager.getSynchronizations();
        assertThat(synchronizations).hasSize(1);
        synchronizations.getFirst().afterCommit();

        verify(photoSearchIndexService).indexPhoto(
                fixture.photoId(),
                fixture.ownerUserId(),
                "海边日落",
                null,
                List.of("海边")
        );
    }

    @Test
    void scheduleIndexAfterCommitRunsImmediatelyWithoutTransaction() {
        IndexFixture fixture = stubIndexablePhoto();

        service.scheduleIndexAfterCommit(fixture.ownerUserId(), fixture.photoId());

        verify(photoSearchIndexService).indexPhoto(
                fixture.photoId(),
                fixture.ownerUserId(),
                "海边日落",
                null,
                List.of("海边")
        );
    }

    @Test
    void scheduleIndexAfterCommitSwallowsIndexFailures() {
        IndexFixture fixture = stubIndexablePhoto();
        doThrow(new IllegalStateException("索引目录不可用"))
                .when(photoSearchIndexService)
                .indexPhoto(
                        eq(fixture.photoId()),
                        eq(fixture.ownerUserId()),
                        Mockito.any(),
                        Mockito.any(),
                        anyList()
                );

        // 标签写入已经成功，索引失败只记日志，由批量 PHOTO_INDEX 任务兜底修复。
        assertThatCode(() -> service.scheduleIndexAfterCommit(
                fixture.ownerUserId(),
                fixture.photoId()
        )).doesNotThrowAnyException();
    }

    private IndexFixture stubIndexablePhoto() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(fileNodeId);
        photo.setTitle("海边日落");
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)).thenReturn(true);
        PhotoTag tag = new PhotoTag();
        tag.setTag("海边");
        Mockito.when(photoTagRepository.findByOwnerUserIdAndPhotoId(ownerUserId, photoId))
                .thenReturn(List.of(tag));
        return new IndexFixture(ownerUserId, photoId);
    }

    private record IndexFixture(UUID ownerUserId, UUID photoId) {
    }
}
