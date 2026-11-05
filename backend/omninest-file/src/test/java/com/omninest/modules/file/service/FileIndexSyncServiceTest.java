package com.omninest.modules.file.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.event.FileIndexSyncEvent;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.search.service.FileSearchIndexService;
import com.omninest.modules.task.service.TaskDispatchService;
import java.util.List;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.assertj.core.groups.Tuple;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;

/**
 * 正文索引迁移编排测试。
 *
 * <p>索引以内容对象为键，只有「目标目录里还没有这份正文」的节点才会被重新投递解析。</p>
 *
 * @author OmniNest
 */
class FileIndexSyncServiceTest {

    private final FileNodeRepository fileNodeRepository = Mockito.mock(FileNodeRepository.class);
    private final FileSearchIndexService fileSearchIndexService = Mockito.mock(FileSearchIndexService.class);
    private final FilePostProcessingTaskService filePostProcessingTaskService = Mockito.mock(
            FilePostProcessingTaskService.class
    );
    private final TaskDispatchService taskDispatchService = Mockito.mock(TaskDispatchService.class);
    private final FileIndexSyncService service = new FileIndexSyncService(
            fileNodeRepository,
            fileSearchIndexService,
            filePostProcessingTaskService,
            taskDispatchService
    );

    @Test
    void scheduleAfterCommitDispatchesThroughOutboxInsteadOfWritingIndex() {
        UUID ownerUserId = UUID.randomUUID();
        UUID firstId = UUID.randomUUID();
        UUID secondId = UUID.randomUUID();

        service.scheduleAfterCommit(ownerUserId, List.of(firstId, secondId));

        Mockito.verify(taskDispatchService).enqueue(
                ArgumentMatchers.eq(firstId),
                ArgumentMatchers.eq(QueueNames.TASK_EXCHANGE),
                ArgumentMatchers.eq(QueueNames.FILE_INDEX_SYNC_ROUTING_KEY),
                ArgumentMatchers.eq(new FileIndexSyncEvent(ownerUserId, List.of(firstId, secondId)))
        );
        Mockito.verifyNoInteractions(fileSearchIndexService, filePostProcessingTaskService);
    }

    @Test
    void scheduleAfterCommitIgnoresEmptyRequest() {
        service.scheduleAfterCommit(UUID.randomUUID(), List.of());
        service.scheduleAfterCommit(UUID.randomUUID(), null);

        Mockito.verifyNoInteractions(taskDispatchService, fileSearchIndexService);
    }

    @Test
    void syncRedispatchesExtractionOnlyForObjectsMissingFromTheTargetDirectory() {
        UUID ownerUserId = UUID.randomUUID();
        UUID missingId = UUID.randomUUID();
        UUID alreadyIndexedId = UUID.randomUUID();
        FileNode missing = activeNode(ownerUserId, missingId, "未索引的共享文件.pdf");
        FileNode alreadyIndexed = activeNode(ownerUserId, alreadyIndexedId, "已索引的副本.pdf");
        Mockito.when(fileNodeRepository.findAllById(List.of(missingId, alreadyIndexedId)))
                .thenReturn(List.of(missing, alreadyIndexed));
        Mockito.when(fileSearchIndexService.hasObjectContent(
                        ownerUserId, SpaceType.PERSONAL.getValue(), missing.getCurrentObjectId()))
                .thenReturn(false);
        Mockito.when(fileSearchIndexService.hasObjectContent(
                        ownerUserId, SpaceType.PERSONAL.getValue(), alreadyIndexed.getCurrentObjectId()))
                .thenReturn(true);

        int processed = service.sync(ownerUserId, List.of(missingId, alreadyIndexedId));

        Assertions.assertThat(processed).isEqualTo(1);
        ArgumentCaptor<FileUploadedEvent> captor = ArgumentCaptor.captor();
        Mockito.verify(filePostProcessingTaskService).enqueueReindex(captor.capture());
        Assertions.assertThat(captor.getAllValues())
                .extracting(FileUploadedEvent::fileNodeId, FileUploadedEvent::fileName)
                .containsExactly(Tuple.tuple(missingId, "未索引的共享文件.pdf"));
    }

    @Test
    void syncSkipsTrashedAndMissingNodesWithoutTouchingTheIndex() {
        UUID ownerUserId = UUID.randomUUID();
        UUID trashedId = UUID.randomUUID();
        UUID purgedId = UUID.randomUUID();
        FileNode trashed = activeNode(ownerUserId, trashedId, "回收站.pdf");
        trashed.setDeleted(true);
        Mockito.when(fileNodeRepository.findAllById(List.of(trashedId, purgedId)))
                .thenReturn(List.of(trashed));

        int processed = service.sync(ownerUserId, List.of(trashedId, purgedId));

        // 软删除由数据库在检索时过滤，索引里的正文不会露出，也不需要清理。
        Assertions.assertThat(processed).isZero();
        Mockito.verifyNoInteractions(filePostProcessingTaskService);
        Mockito.verifyNoInteractions(fileSearchIndexService);
    }

    @Test
    void syncSkipsFolderNodesWithoutAbortingTheBatch() {
        UUID ownerUserId = UUID.randomUUID();
        UUID folderId = UUID.randomUUID();
        UUID fileId = UUID.randomUUID();
        FileNode folder = activeNode(ownerUserId, folderId, "子目录");
        folder.setNodeType(NodeType.FOLDER.getValue());
        folder.setCurrentObjectId(null);
        FileNode file = activeNode(ownerUserId, fileId, "目录下的文件.pdf");
        Mockito.when(fileNodeRepository.findAllById(List.of(folderId, fileId))).thenReturn(List.of(
                folder,
                file
        ));
        Mockito.when(fileSearchIndexService.hasObjectContent(
                        ownerUserId, SpaceType.PERSONAL.getValue(), file.getCurrentObjectId()))
                .thenReturn(false);

        int processed = service.sync(ownerUserId, List.of(folderId, fileId));

        Assertions.assertThat(processed).isEqualTo(1);
        ArgumentCaptor<FileUploadedEvent> captor = ArgumentCaptor.captor();
        Mockito.verify(filePostProcessingTaskService).enqueueReindex(captor.capture());
        Assertions.assertThat(captor.getValue().fileNodeId()).isEqualTo(fileId);
    }

    @Test
    void syncWithoutNodesDoesNothing() {
        Assertions.assertThat(service.sync(UUID.randomUUID(), List.of())).isZero();

        Mockito.verifyNoInteractions(fileNodeRepository, fileSearchIndexService, filePostProcessingTaskService);
    }

    private FileNode activeNode(UUID ownerUserId, UUID fileNodeId, String name) {
        FileNode node = new FileNode();
        node.setId(fileNodeId);
        node.setOwnerUserId(ownerUserId);
        node.setSpaceType(SpaceType.PERSONAL);
        node.setName(name);
        node.setMimeType("application/pdf");
        node.setNodeType(NodeType.FILE.getValue());
        node.setSizeBytes(2048L);
        node.setCurrentObjectId(UUID.randomUUID());
        node.setDeleted(false);
        return node;
    }
}
