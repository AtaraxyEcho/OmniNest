package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.photos.domain.PhotoContentAnalysisRun;
import com.omninest.modules.photos.domain.PhotoContentLabel;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.event.PhotoIndexEvent;
import com.omninest.modules.photos.repository.PhotoContentAnalysisRunRepository;
import com.omninest.modules.photos.repository.PhotoContentLabelRepository;
import com.omninest.modules.photos.repository.PhotoIndexTargetProjection;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import com.omninest.modules.photos.search.PhotoSearchIndexService.PhotoIndexDocument;
import com.omninest.modules.task.service.TaskDispatchService;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.IntStream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
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
    private final PhotoContentAnalysisRunRepository analysisRunRepository =
            Mockito.mock(PhotoContentAnalysisRunRepository.class);
    private final PhotoContentLabelRepository contentLabelRepository =
            Mockito.mock(PhotoContentLabelRepository.class);
    private final PhotoLabelPolicy labelPolicy = new PhotoLabelPolicy();
    private final PhotoSearchIndexService photoSearchIndexService =
            Mockito.mock(PhotoSearchIndexService.class);
    private final FileLifecycleGuard fileLifecycleGuard = Mockito.mock(FileLifecycleGuard.class);
    private final TaskDispatchService taskDispatchService = Mockito.mock(TaskDispatchService.class);
    private final PhotoIndexTaskService service = new PhotoIndexTaskService(
            photoItemRepository,
            photoTagRepository,
            analysisRunRepository,
            contentLabelRepository,
            labelPolicy,
            photoSearchIndexService,
            fileLifecycleGuard,
            taskDispatchService
    );

    @BeforeEach
    void setUp() {
        Mockito.when(analysisRunRepository
                        .findTopByOwnerUserIdAndPhotoIdAndStatusOrderByCreatedAtDesc(
                                Mockito.any(), Mockito.any(), Mockito.anyString()))
                .thenReturn(null);
        Mockito.when(contentLabelRepository.findByOwnerUserIdAndPhotoIdAndRunId(
                        Mockito.any(), Mockito.any(), Mockito.any()))
                .thenReturn(List.of());
    }

    @Test
    void indexLoadsOwnedPhotoTagsAndCurrentAnalysisLabels() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = photo(photoId, ownerUserId, fileNodeId);
        photo.setTitle("Mountain");
        photo.setDescription("Sunrise");
        photo.setOcrText("发票号码 12345");
        PhotoContentAnalysisRun run = run(photoId);
        PhotoTag firstTag = new PhotoTag();
        firstTag.setTag("travel");
        PhotoTag secondTag = new PhotoTag();
        secondTag.setTag("sunrise");
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(photoTagRepository.findByOwnerUserIdAndPhotoId(ownerUserId, photoId))
                .thenReturn(List.of(firstTag, secondTag));
        Mockito.when(fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)).thenReturn(true);
        Mockito.when(analysisRunRepository
                        .findTopByOwnerUserIdAndPhotoIdAndStatusOrderByCreatedAtDesc(
                                ownerUserId, photoId, "SUCCEEDED"))
                .thenReturn(run);
        Mockito.when(contentLabelRepository.findByOwnerUserIdAndPhotoIdAndRunId(
                        ownerUserId, photoId, run.getId()))
                .thenReturn(List.of(
                        label(ownerUserId, photoId, run.getId(), "SUBJECT", "cat"),
                        label(ownerUserId, photoId, run.getId(), "STYLE", "document")
                ));

        boolean indexed = service.index(ownerUserId, photoId);

        assertThat(indexed).isTrue();
        ArgumentCaptor<PhotoIndexDocument> documentCaptor =
                ArgumentCaptor.forClass(PhotoIndexDocument.class);
        Mockito.verify(photoSearchIndexService).indexPhoto(documentCaptor.capture());
        PhotoIndexDocument document = documentCaptor.getValue();
        assertThat(document.photoId()).isEqualTo(photoId);
        assertThat(document.ownerUserId()).isEqualTo(ownerUserId);
        assertThat(document.title()).isEqualTo("Mountain");
        assertThat(document.description()).isEqualTo("Sunrise");
        assertThat(document.tags()).containsExactly("travel", "sunrise");
        assertThat(document.ocrText()).isEqualTo("发票号码 12345");
        assertThat(document.aiLabels()).anyMatch(keywords -> keywords.contains("猫"));
        assertThat(document.aiLabels()).anyMatch(keywords -> keywords.contains("发票"));
    }

    @Test
    void indexRemovesPhotoWhenSourceFileIsPurging() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = photo(photoId, ownerUserId, fileNodeId);
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
        PhotoItem photo = photo(photoId, ownerUserId, fileNodeId);
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
                .indexPhoto(Mockito.any(PhotoIndexDocument.class));
    }

    @Test
    void indexBatchDirectWritesLivingPhotosAndDeletesTrashedOnes() {
        UUID ownerUserId = UUID.randomUUID();
        UUID alivePhotoId = UUID.randomUUID();
        UUID trashedPhotoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem alive = photo(alivePhotoId, ownerUserId, fileNodeId);
        alive.setTitle("猫咪");
        PhotoItem trashed = photo(trashedPhotoId, ownerUserId, UUID.randomUUID());
        trashed.setDeletedAt(Instant.now());
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, alivePhotoId))
                .thenReturn(Optional.of(alive));
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, trashedPhotoId))
                .thenReturn(Optional.of(trashed));
        Mockito.when(fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)).thenReturn(true);
        Mockito.when(photoTagRepository.findByOwnerUserIdAndPhotoId(ownerUserId, alivePhotoId))
                .thenReturn(List.of());

        int indexed = service.indexBatchDirect(
                ownerUserId, List.of(alivePhotoId, trashedPhotoId));

        assertThat(indexed).isEqualTo(1);
        Mockito.verify(photoSearchIndexService).deletePhotos(List.of(trashedPhotoId));
        ArgumentCaptor<List<PhotoIndexDocument>> documentsCaptor = listCaptor();
        Mockito.verify(photoSearchIndexService).indexPhotosBatch(documentsCaptor.capture());
        assertThat(documentsCaptor.getValue()).singleElement()
                .satisfies(document -> assertThat(document.photoId()).isEqualTo(alivePhotoId));
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

    private PhotoItem photo(UUID photoId, UUID ownerUserId, UUID fileNodeId) {
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(fileNodeId);
        photo.setProviderMetadata(new HashMap<>());
        return photo;
    }

    private PhotoContentAnalysisRun run(UUID photoId) {
        PhotoContentAnalysisRun run = new PhotoContentAnalysisRun();
        run.setId(UUID.randomUUID());
        run.setPhotoId(photoId);
        run.setPipelineVersion("vision-v6-lightweight+ppocr-v4-onnx-v1");
        run.setStatus("SUCCEEDED");
        return run;
    }

    private PhotoContentLabel label(
            UUID ownerUserId,
            UUID photoId,
            UUID runId,
            String namespace,
            String code
    ) {
        PhotoContentLabel label = new PhotoContentLabel();
        label.setId(UUID.randomUUID());
        label.setOwnerUserId(ownerUserId);
        label.setPhotoId(photoId);
        label.setRunId(runId);
        label.setNamespace(namespace);
        label.setLabelCode(code);
        label.setConfidence(0.9F);
        label.setSource("test");
        label.setState("AUTO");
        label.setBoxes(new ArrayList<>());
        return label;
    }

    @SuppressWarnings("unchecked")
    private ArgumentCaptor<List<PhotoIndexDocument>> listCaptor() {
        return ArgumentCaptor.forClass(List.class);
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
