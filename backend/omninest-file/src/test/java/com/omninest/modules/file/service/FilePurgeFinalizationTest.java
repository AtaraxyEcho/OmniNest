package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FileVersion;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.event.FilePurgeRequestedEvent;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.FilePurgeEntryRepository;
import com.omninest.modules.file.repository.FileVersionRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.search.service.FileSearchIndexService;
import com.omninest.modules.task.service.TaskRecordService;
import jakarta.persistence.EntityManager;
import java.util.Collection;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;

/**
 * 永久删除最终清理阶段的对象行与配额测试。
 *
 * @author OmniNest
 */
class FilePurgeFinalizationTest {

    private static final UUID TASK_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID ROOT_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID NODE_ONE = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID NODE_TWO = UUID.fromString("40000000-0000-0000-0000-000000000002");
    private static final UUID OBJECT_A = UUID.fromString("50000000-0000-0000-0000-000000000001");
    private static final UUID OBJECT_B = UUID.fromString("50000000-0000-0000-0000-000000000002");

    private final FileNodeRepository fileNodeRepository = mock(FileNodeRepository.class);
    private final FileObjectRepository fileObjectRepository = mock(FileObjectRepository.class);
    private final FileVersionRepository fileVersionRepository = mock(FileVersionRepository.class);
    private final FilePurgeEntryRepository purgeEntryRepository = mock(FilePurgeEntryRepository.class);
    private final StorageQuotaService storageQuotaService = mock(StorageQuotaService.class);
    private final FileSearchIndexService fileSearchIndexService = mock(FileSearchIndexService.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final EntityManager entityManager = mock(EntityManager.class);
    private final FilePurgeStateService service = new FilePurgeStateService(
            fileNodeRepository,
            fileObjectRepository,
            fileVersionRepository,
            purgeEntryRepository,
            mock(FileNodePermissionRepository.class),
            List.of(),
            storageQuotaService,
            fileSearchIndexService,
            mock(ApplicationEventPublisher.class),
            mock(ReadThroughCache.class),
            taskRecordService,
            entityManager
    );

    @Test
    @DisplayName("多批次任务在全部批次结束后才删对象行，后续批次仍能按对象大小释放配额")
    void finalizeDefersObjectRowDeletionUntilAllBatches() {
        FileNode first = personalFile(NODE_ONE, OBJECT_A, 100L);
        FileNode second = personalFile(NODE_TWO, OBJECT_A, 100L);
        FileObject objectA = fileObject(OBJECT_A, 100L);
        FileObject objectB = fileObject(OBJECT_B, 50L);
        FileVersion version = new FileVersion();
        version.setFileNodeId(NODE_TWO);
        version.setObjectId(OBJECT_B);

        when(fileNodeRepository.findByPurgeTaskIdOrderById(eq(TASK_ID), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(first)))
                .thenReturn(new PageImpl<>(List.of(second)))
                .thenReturn(new PageImpl<>(List.of()));
        when(fileVersionRepository.findByFileNodeIdIn(List.of(NODE_ONE))).thenReturn(List.of());
        when(fileVersionRepository.findByFileNodeIdIn(List.of(NODE_TWO))).thenReturn(List.of(version));
        when(purgeEntryRepository.countByTaskId(TASK_ID)).thenReturn(2L);

        Set<UUID> deletedRows = new HashSet<>();
        when(fileObjectRepository.findAllById(any())).thenAnswer(invocation -> {
            Collection<UUID> ids = invocation.getArgument(0);
            return List.of(objectA, objectB).stream()
                    .filter(object -> ids.contains(object.getId()) && !deletedRows.contains(object.getId()))
                    .toList();
        });
        doAnswer(invocation -> {
            Iterable<FileObject> objects = invocation.getArgument(0);
            objects.forEach(object -> deletedRows.add(object.getId()));
            return null;
        }).when(fileObjectRepository).deleteAllInBatch(any());

        service.finalizePurge(new FilePurgeRequestedEvent(TASK_ID, OWNER_ID, ROOT_ID));

        ArgumentCaptor<Map<String, Object>> metadata = ArgumentCaptor.forClass(Map.class);
        verify(taskRecordService).markCompleted(eq(TASK_ID), metadata.capture());
        // 首批若提前删掉 OBJECT_A 行，第二批只能释放 100 字节；延迟删行后应为 100 + 100 + 50
        assertThat(metadata.getValue())
                .containsEntry("releasedBytes", 250L)
                .containsEntry("deletedObjectRowCount", 2);
        verify(fileObjectRepository).deleteAllInBatch(List.of(objectA, objectB));
    }

    @Test
    @DisplayName("仍被未进入删除任务的节点引用时不得删除对象行")
    void finalizeKeepsObjectsStillReferencedByUnpurgedNodes() {
        FileNode node = personalFile(NODE_ONE, OBJECT_A, 100L);
        FileObject objectA = fileObject(OBJECT_A, 100L);
        when(fileNodeRepository.findByPurgeTaskIdOrderById(eq(TASK_ID), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(node)))
                .thenReturn(new PageImpl<>(List.of()));
        when(fileVersionRepository.findByFileNodeIdIn(List.of(NODE_ONE))).thenReturn(List.of());
        when(fileObjectRepository.findAllById(any())).thenReturn(List.of(objectA));
        when(fileNodeRepository.findCurrentObjectIdsInUse(anyCollection())).thenReturn(List.of(OBJECT_A));
        when(purgeEntryRepository.countByTaskId(TASK_ID)).thenReturn(1L);

        service.finalizePurge(new FilePurgeRequestedEvent(TASK_ID, OWNER_ID, ROOT_ID));

        verify(fileObjectRepository, never()).deleteAllInBatch(any());
    }

    private FileNode personalFile(UUID nodeId, UUID objectId, long sizeBytes) {
        FileNode node = new FileNode();
        node.setId(nodeId);
        node.setOwnerUserId(OWNER_ID);
        node.setSpaceType(SpaceType.PERSONAL);
        node.setNodeType(NodeType.FILE.getValue());
        node.setCurrentObjectId(objectId);
        node.setSizeBytes(sizeBytes);
        return node;
    }

    private FileObject fileObject(UUID objectId, long sizeBytes) {
        FileObject object = new FileObject();
        object.setId(objectId);
        object.setBucketName("test-bucket");
        object.setObjectKey("objects/" + objectId);
        object.setSizeBytes(sizeBytes);
        return object;
    }
}
