package com.omninest.modules.file.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.FileNode;
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
 * 文件索引同步编排测试。
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
    void syncRedispatchesIndexAndExtractionForEveryActiveNode() {
        UUID ownerUserId = UUID.randomUUID();
        UUID renamedId = UUID.randomUUID();
        UUID restoredId = UUID.randomUUID();
        Mockito.when(fileNodeRepository.findAllById(List.of(renamedId, restoredId))).thenReturn(List.of(
                activeNode(ownerUserId, renamedId, "新标题.pdf"),
                activeNode(ownerUserId, restoredId, "还原的文件.pdf")
        ));

        int processed = service.sync(ownerUserId, List.of(renamedId, restoredId));

        Assertions.assertThat(processed).isEqualTo(2);
        ArgumentCaptor<FileUploadedEvent> captor = ArgumentCaptor.captor();
        Mockito.verify(filePostProcessingTaskService, Mockito.times(2)).enqueueReindex(captor.capture());
        Assertions.assertThat(captor.getAllValues())
                .extracting(FileUploadedEvent::fileNodeId, FileUploadedEvent::fileName)
                .containsExactly(
                        Tuple.tuple(renamedId, "新标题.pdf"),
                        Tuple.tuple(restoredId, "还原的文件.pdf")
                );
        // 只补元数据会让文件按名字搜得到、按内容搜不到，所以同步路径不再自己写索引文档。
        Mockito.verify(fileSearchIndexService, Mockito.never())
                .indexFiles(ArgumentMatchers.eq(ownerUserId), ArgumentMatchers.anyCollection());
    }

    @Test
    void syncRemovesNodesThatAreMissingOrInTrash() {
        UUID ownerUserId = UUID.randomUUID();
        UUID trashedId = UUID.randomUUID();
        UUID purgedId = UUID.randomUUID();
        FileNode trashed = activeNode(ownerUserId, trashedId, "回收站.pdf");
        trashed.setDeleted(true);
        Mockito.when(fileNodeRepository.findAllById(List.of(trashedId, purgedId)))
                .thenReturn(List.of(trashed));

        int processed = service.sync(ownerUserId, List.of(trashedId, purgedId));

        Assertions.assertThat(processed).isEqualTo(2);
        Mockito.verify(fileSearchIndexService).deleteFiles(List.of(trashedId, purgedId), ownerUserId);
        Mockito.verifyNoInteractions(filePostProcessingTaskService);
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
        node.setSizeBytes(2048L);
        node.setCurrentObjectId(UUID.randomUUID());
        node.setDeleted(false);
        return node;
    }
}
