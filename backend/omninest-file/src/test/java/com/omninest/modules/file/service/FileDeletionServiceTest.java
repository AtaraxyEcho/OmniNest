package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.concurrency.DistributedLock;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.event.FilePurgeRequestedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Page;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.SimpleTransactionStatus;

/**
 * 文件永久删除任务创建服务测试。
 *
 * @author OmniNest
 */
class FileDeletionServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SECOND_FILE_NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000002");

    private final FileNodeRepository fileNodeRepository = mock(FileNodeRepository.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final DistributedLock distributedLock = mock(DistributedLock.class);
    private final PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
    private final FilePurgeParticipant participant = mock(FilePurgeParticipant.class);
    private final FileDeletionService fileDeletionService = new FileDeletionService(
            fileNodeRepository,
            fileQueryService,
            taskRecordService,
            taskDispatchService,
            distributedLock,
            transactionManager,
            List.of(participant)
    );

    @BeforeEach
    void setUp() {
        when(distributedLock.newToken()).thenReturn("lock-token");
        when(distributedLock.tryLock(eq("lock:file-lifecycle:" + FILE_NODE_ID), eq("lock-token"), any(Duration.class)))
                .thenReturn(true);
        when(distributedLock.unlock("lock:file-lifecycle:" + FILE_NODE_ID, "lock-token")).thenReturn(true);
        when(transactionManager.getTransaction(any(TransactionDefinition.class)))
                .thenReturn(new SimpleTransactionStatus());
        when(taskRecordService.findActiveResourceTask(
                eq(OWNER_ID),
                eq("FILE_PURGE"),
                eq("FILE_NODE"),
                eq(FILE_NODE_ID),
                any()
        )).thenReturn(Optional.empty());
        when(participant.findBusinessReferences(any(PurgeContext.class))).thenReturn(List.of());
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithOrderById(
                any(),
                any(),
                any(),
                any()
        )).thenReturn(Page.empty());
        when(fileNodeRepository.findIdsByPurgeTaskId(any(), any())).thenReturn(Page.empty());
    }

    @Test
    void deletePermanentlyCreatesDurableTaskInsteadOfDeletingObjectSynchronously() {
        FileNode root = deletedRoot();
        when(fileNodeRepository.findOwnedForUpdate(FILE_NODE_ID, OWNER_ID)).thenReturn(Optional.of(root));
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID,
                SpaceType.PERSONAL,
                "/movie.mkv/"
        )).thenReturn(List.of());

        UUID taskId = fileDeletionService.deletePermanently(OWNER_ID, FILE_NODE_ID);

        assertThat(taskId).isNotNull();
        assertThat(root.getPurgeState()).isEqualTo(FilePurgeState.QUEUED);
        assertThat(root.getPurgeTaskId()).isEqualTo(taskId);
        verify(taskRecordService).createQueuedTask(
                eq(taskId),
                eq(OWNER_ID),
                eq("FILE_PURGE"),
                eq(QueueNames.FILE_PURGE_ROUTING_KEY),
                eq("PLANNING"),
                eq("FILE_NODE"),
                eq(FILE_NODE_ID),
                anyMap()
        );
        verify(taskDispatchService).enqueue(
                eq(taskId),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.FILE_PURGE_ROUTING_KEY),
                any(FilePurgeRequestedEvent.class)
        );
        verify(distributedLock).unlock("lock:file-lifecycle:" + FILE_NODE_ID, "lock-token");
    }

    @Test
    void deletePermanentlyRejectsUnconfirmedBusinessReferences() {
        FileNode root = deletedRoot();
        UUID readerItemId = UUID.fromString("30000000-0000-0000-0000-000000000001");
        when(fileNodeRepository.findOwnedForUpdate(FILE_NODE_ID, OWNER_ID)).thenReturn(Optional.of(root));
        when(participant.findBusinessReferences(any(PurgeContext.class))).thenReturn(List.of(
                new FileBusinessReference("READER", "READER_ITEM", readerItemId, FILE_NODE_ID)
        ));

        assertThatThrownBy(() -> fileDeletionService.deletePermanently(
                OWNER_ID,
                FILE_NODE_ID,
                false,
                null,
                root.getVersion()
        )).isInstanceOfSatisfying(BusinessException.class, exception -> {
            assertThat(exception.errorCode()).isEqualTo(ErrorCode.RESOURCE_IN_USE);
            assertThat(exception.details()).containsKey("impact");
        });
    }

    @Test
    void deletePermanentlyExcludesTheRequestingBusinessResourceFromImpact() {
        FileNode root = deletedRoot();
        UUID readerItemId = UUID.fromString("30000000-0000-0000-0000-000000000001");
        when(fileNodeRepository.findOwnedForUpdate(FILE_NODE_ID, OWNER_ID)).thenReturn(Optional.of(root));
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID,
                SpaceType.PERSONAL,
                "/movie.mkv/"
        )).thenReturn(List.of());
        when(participant.findBusinessReferences(any(PurgeContext.class))).thenReturn(List.of(
                new FileBusinessReference("READER", "READER_ITEM", readerItemId, FILE_NODE_ID)
        ));

        UUID taskId = fileDeletionService.deletePermanently(
                OWNER_ID,
                FILE_NODE_ID,
                false,
                new FilePurgeOrigin("READER", readerItemId),
                root.getVersion()
        );

        assertThat(taskId).isNotNull();
    }

    @Test
    void deletePermanentlyBatchCreatesOneTaskForAllRoots() {
        FileNode firstRoot = deletedRoot(FILE_NODE_ID, "/first.jpg");
        FileNode secondRoot = deletedRoot(SECOND_FILE_NODE_ID, "/second.jpg");
        when(distributedLock.tryLock(
                eq("lock:file-lifecycle:" + SECOND_FILE_NODE_ID),
                eq("lock-token"),
                any(Duration.class)
        )).thenReturn(true);
        when(distributedLock.unlock(
                "lock:file-lifecycle:" + SECOND_FILE_NODE_ID,
                "lock-token"
        )).thenReturn(true);
        when(fileNodeRepository.findOwnedForUpdate(FILE_NODE_ID, OWNER_ID)).thenReturn(Optional.of(firstRoot));
        when(fileNodeRepository.findOwnedForUpdate(SECOND_FILE_NODE_ID, OWNER_ID)).thenReturn(Optional.of(secondRoot));
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID,
                SpaceType.PERSONAL,
                "/first.jpg/"
        )).thenReturn(List.of());
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID,
                SpaceType.PERSONAL,
                "/second.jpg/"
        )).thenReturn(List.of());

        UUID taskId = fileDeletionService.deletePermanentlyBatch(
                OWNER_ID,
                List.of(SECOND_FILE_NODE_ID, FILE_NODE_ID),
                false,
                List.of()
        );

        assertThat(firstRoot.getPurgeTaskId()).isEqualTo(taskId);
        assertThat(secondRoot.getPurgeTaskId()).isEqualTo(taskId);
        verify(taskRecordService).createQueuedTask(
                eq(taskId),
                eq(OWNER_ID),
                eq("FILE_PURGE"),
                eq(QueueNames.FILE_PURGE_ROUTING_KEY),
                eq("PLANNING"),
                eq("FILE_NODE"),
                eq(FILE_NODE_ID),
                anyMap()
        );
        verify(taskDispatchService).enqueue(
                eq(taskId),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.FILE_PURGE_ROUTING_KEY),
                any(FilePurgeRequestedEvent.class)
        );
        verify(distributedLock).unlock("lock:file-lifecycle:" + FILE_NODE_ID, "lock-token");
        verify(distributedLock).unlock("lock:file-lifecycle:" + SECOND_FILE_NODE_ID, "lock-token");
    }

    @Test
    void deletePermanentlyEscapesWildcardCharactersInThePurgeSubtreePrefix() {
        // 前缀是真实目录名，消费方是"把后代挂到本次 taskId"的批量更新：
        // /100%_done/ 不转义就会同时匹配兄弟目录，那些文件被同一任务认领后物理清除。
        FileNode root = deletedRoot(FILE_NODE_ID, "/100%_done");
        when(fileNodeRepository.findOwnedForUpdate(FILE_NODE_ID, OWNER_ID)).thenReturn(Optional.of(root));

        fileDeletionService.deletePermanently(OWNER_ID, FILE_NODE_ID);

        verify(fileNodeRepository).assignDeletedDescendantsToPurge(
                eq(OWNER_ID),
                eq(SpaceType.PERSONAL),
                eq("/100\\%\\_done/"),
                any(),
                eq(FilePurgeState.QUEUED),
                any()
        );
    }

    private FileNode deletedRoot() {
        return deletedRoot(FILE_NODE_ID, "/movie.mkv");
    }

    private FileNode deletedRoot(UUID fileNodeId, String normalizedPath) {
        FileNode node = new FileNode();
        node.setId(fileNodeId);
        node.setOwnerUserId(OWNER_ID);
        node.setNormalizedPath(normalizedPath);
        node.setDeleted(true);
        node.setPurgeState(FilePurgeState.NONE);
        return node;
    }
}
