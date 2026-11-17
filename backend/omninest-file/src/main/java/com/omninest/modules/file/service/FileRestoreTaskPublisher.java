package com.omninest.modules.file.service;

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
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * 文件恢复后的派生资产修复任务发布服务。
 *
 * <p>只负责源对象校验与缩略图补齐。文件名检索以数据库为实时真值，恢复后无需
 * 重建任何索引，因此这里不派发额外的后处理任务。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileRestoreTaskPublisher {
    private final FileNodeRepository fileNodeRepository;
    private final TaskDispatchService taskDispatchService;

    /**
     * 在文件恢复事务提交后按文件写入派生资产修复投递记录。
     *
     * <p>千级文件恢复不能逐条同步发 Broker：网络 I/O 会占满整段事务，且中途断连后
     * 后半批消息永久丢失。投递记录随恢复事务之后的 Outbox 事务批量落库，由
     * {@code TaskOutboxDispatcher} 统一发布与重试。</p>
     *
     * @param event 文件节点恢复事件
     */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public void publishRestoredFiles(FileNodesRestoredEvent event) {
        List<FileNode> files = fileNodeRepository.findAllById(event.fileNodeIds()).stream()
                .filter(node -> NodeType.FILE.getValue().equals(node.getNodeType()))
                .filter(node -> !node.isDeleted())
                .filter(node -> node.getCurrentObjectId() != null)
                .toList();
        if (files.isEmpty()) {
            return;
        }
        List<TaskDispatchItem> dispatches = files.stream()
                .map(file -> new TaskDispatchItem(
                        file.getId(),
                        toFileRestoredEvent(event.ownerUserId(), file)))
                .toList();
        // 恢复队列没有任务台账，投递行的 task_id 以文件节点 ID 作为关联键，
        // 与 PHOTO_INDEX 全站重建的既有口径一致。
        taskDispatchService.enqueueAll(
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_RESTORE_INDEX_ROUTING_KEY,
                dispatches);
    }

    private FileRestoredEvent toFileRestoredEvent(UUID ownerUserId, FileNode file) {
        return new FileRestoredEvent(
                file.getId(),
                ownerUserId,
                file.getName(),
                Instant.now()
        );
    }
}
