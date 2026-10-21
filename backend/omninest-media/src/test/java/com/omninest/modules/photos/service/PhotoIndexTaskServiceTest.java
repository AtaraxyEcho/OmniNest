package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.event.PhotoIndexEvent;
import com.omninest.modules.photos.repository.PhotoIndexTargetProjection;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import com.omninest.modules.task.service.TaskDispatchService;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.mockito.Mockito;

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
    private final TaskDispatchService taskDispatchService = Mockito.mock(TaskDispatchService.class);
    private final PhotoIndexTaskService service = new PhotoIndexTaskService(
            photoItemRepository,
            photoTagRepository,
            photoSearchIndexService,
            fileLifecycleGuard,
            taskDispatchService
    );

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
    void indexRemovesPhotoWhenSourceFileIsPurging() {
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
        Mockito.verify(photoSearchIndexService).deletePhoto(photoId);
        Mockito.verifyNoInteractions(photoTagRepository);
    }

    @Test
    void indexRemovesPhotoAlreadyInTrash() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(fileNodeId);
        photo.setDeletedAt(Instant.now());
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));

        boolean indexed = service.index(ownerUserId, photoId);

        assertThat(indexed).isFalse();
        Mockito.verify(photoSearchIndexService).deletePhoto(photoId);
        Mockito.verify(fileLifecycleGuard, Mockito.never()).isOwnedProcessable(ownerUserId, fileNodeId);
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
    void scheduleIndexAfterCommitDispatchesEventInsteadOfWritingIndex() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();

        service.scheduleIndexAfterCommit(ownerUserId, photoId);

        // API 进程不得持有同一索引目录的 IndexWriter：请求必须交给单写进程消费。
        Mockito.verify(taskDispatchService).enqueue(
                eq(photoId),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.PHOTO_INDEX_ROUTING_KEY),
                eq(new PhotoIndexEvent(photoId, ownerUserId))
        );
        Mockito.verifyNoInteractions(photoItemRepository, photoTagRepository, photoSearchIndexService);
    }

    @Test
    void indexSkipsTagLoadWhenPhotoMissing() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.empty());

        assertThat(service.index(ownerUserId, photoId)).isFalse();

        Mockito.verify(photoSearchIndexService, Mockito.never())
                .indexPhoto(eq(photoId), eq(ownerUserId), Mockito.any(), Mockito.any(), anyList());
    }

    @Test
    void rebuildAllDropsWholeIndexBeforeRedispatching() {
        UUID firstOwner = UUID.randomUUID();
        UUID secondOwner = UUID.randomUUID();
        UUID firstPhoto = UUID.randomUUID();
        UUID secondPhoto = UUID.randomUUID();
        Mockito.when(photoItemRepository.countIndexablePhotos()).thenReturn(2L);
        Mockito.when(photoItemRepository.findIndexablePhotosAfterId(
                        eq(new UUID(0L, 0L)), Mockito.any()))
                .thenReturn(List.of(
                        new PhotoIndexTarget(firstPhoto, firstOwner),
                        new PhotoIndexTarget(secondPhoto, secondOwner)
                ));

        int dispatched = service.rebuildAll();

        assertThat(dispatched).isEqualTo(2);
        // 索引字段口径变更后旧文档不会再被新查询命中，整卷丢弃必须发生在任何重投之前，
        // 否则重投写入的文档会被随后的 deleteAll 一并清掉，表现为重建完仍然搜不到。
        InOrder inOrder = Mockito.inOrder(photoSearchIndexService, taskDispatchService);
        inOrder.verify(photoSearchIndexService).clearAll();
        inOrder.verify(taskDispatchService).enqueue(
                eq(firstPhoto),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.PHOTO_INDEX_ROUTING_KEY),
                eq(new PhotoIndexEvent(firstPhoto, firstOwner))
        );
        inOrder.verify(taskDispatchService).enqueue(
                eq(secondPhoto),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.PHOTO_INDEX_ROUTING_KEY),
                eq(new PhotoIndexEvent(secondPhoto, secondOwner))
        );
    }

    @Test
    void rebuildAllAdvancesCursorByLastPhotoId() {
        int fullBatch = 500;
        List<PhotoIndexTargetProjection> firstPage = IntStream.range(0, fullBatch)
                .<PhotoIndexTargetProjection>mapToObj(index -> new PhotoIndexTarget(
                        new UUID(1L, index), new UUID(2L, index)))
                .toList();
        PhotoIndexTargetProjection lastOfFirstPage = firstPage.getLast();
        PhotoIndexTargetProjection tailPhoto = new PhotoIndexTarget(new UUID(3L, 0L), new UUID(4L, 0L));
        Mockito.when(photoItemRepository.countIndexablePhotos()).thenReturn((long) fullBatch + 1);
        Mockito.when(photoItemRepository.findIndexablePhotosAfterId(
                        eq(new UUID(0L, 0L)), Mockito.any()))
                .thenReturn(firstPage);
        Mockito.when(photoItemRepository.findIndexablePhotosAfterId(
                        eq(lastOfFirstPage.getId()), Mockito.any()))
                .thenReturn(List.of(tailPhoto));

        int dispatched = service.rebuildAll();

        assertThat(dispatched).isEqualTo(fullBatch + 1);
        Mockito.verify(photoItemRepository).findIndexablePhotosAfterId(eq(lastOfFirstPage.getId()), Mockito.any());
    }

    /**
     * 重建候选投影的测试实现。
     */
    private record PhotoIndexTarget(UUID id, UUID ownerUserId) implements PhotoIndexTargetProjection {

        @Override
        public UUID getId() {
            return id;
        }

        @Override
        public UUID getOwnerUserId() {
            return ownerUserId;
        }
    }
}
