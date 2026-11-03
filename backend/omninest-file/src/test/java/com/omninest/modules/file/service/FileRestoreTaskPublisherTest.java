package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.event.FileRestoredEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.task.service.TaskDispatchItem;
import com.omninest.modules.task.service.TaskDispatchService;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;

/**
 * 文件恢复任务发布服务测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class FileRestoreTaskPublisherTest {
    @Mock
    private FileNodeRepository fileNodeRepository;
    @Mock
    private TaskDispatchService taskDispatchService;
    @InjectMocks
    private FileRestoreTaskPublisher publisher;

    @Test
    void transactionalEventListenerIsAcceptedDuringContextInitialization() {
        try (AnnotationConfigApplicationContext context = new AnnotationConfigApplicationContext()) {
            context.registerBean(FileNodeRepository.class, () -> fileNodeRepository);
            context.registerBean(TaskDispatchService.class, () -> taskDispatchService);
            context.register(FileRestoreTaskPublisher.class);

            context.refresh();

            assertThat(context.getBean(FileRestoreTaskPublisher.class)).isNotNull();
        }
    }

    @Test
    void restoredFilesAreWrittenToOutboxInOneBatch() {
        UUID ownerUserId = UUID.randomUUID();
        FileNode first = fileNode(ownerUserId, "photo.jpg");
        FileNode second = fileNode(ownerUserId, "clip.mp4");
        when(fileNodeRepository.findAllById(List.of(first.getId(), second.getId())))
                .thenReturn(List.of(first, second));

        publisher.publishRestoredFiles(
                new FileNodesRestoredEvent(ownerUserId, List.of(first.getId(), second.getId()), Instant.now())
        );

        verify(taskDispatchService, times(1)).enqueueAll(
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.FILE_RESTORE_INDEX_ROUTING_KEY),
                argThat(items -> items.size() == 2 && matches(items.get(0), first, ownerUserId)
                        && matches(items.get(1), second, ownerUserId))
        );
    }

    private boolean matches(TaskDispatchItem item, FileNode file, UUID ownerUserId) {
        return file.getId().equals(item.taskId())
                && item.payload() instanceof FileRestoredEvent restoredEvent
                && file.getId().equals(restoredEvent.fileNodeId())
                && ownerUserId.equals(restoredEvent.ownerUserId());
    }

    private FileNode fileNode(UUID ownerUserId, String name) {
        FileNode node = new FileNode();
        node.setId(UUID.randomUUID());
        node.setOwnerUserId(ownerUserId);
        node.setNodeType(NodeType.FILE.getValue());
        node.setName(name);
        node.setCurrentObjectId(UUID.randomUUID());
        return node;
    }
}
