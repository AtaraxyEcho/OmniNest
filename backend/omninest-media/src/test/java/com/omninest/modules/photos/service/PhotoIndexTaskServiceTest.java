package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.event.PhotoIndexEvent;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import com.omninest.modules.task.service.TaskDispatchService;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
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
}
