package com.omninest.modules.file.service;

import com.omninest.common.messaging.DomainEventPublisher;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.event.FileRestoredEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
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
 * <p>只负责源对象校验与缩略图补齐。搜索索引不在这里派发：恢复写入侧已经调用
 * {@code FileIndexSyncService.scheduleAfterCommit} 重投 {@code FILE_INDEX + TEXT_EXTRACTION}，
 * 那是唯一能保住已抽取正文的一条路，索引恢复不允许有第二条更弱的入口。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileRestoreTaskPublisher {
    private final FileNodeRepository fileNodeRepository;
    private final DomainEventPublisher domainEventPublisher;

    /**
     * 在文件恢复事务提交后按文件投递派生资产修复消息。
     *
     * @param event 文件节点恢复事件
    */
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(readOnly = true, propagation = Propagation.REQUIRES_NEW)
    public void publishRestoredFiles(FileNodesRestoredEvent event) {
        List<FileNode> files = fileNodeRepository.findAllById(event.fileNodeIds()).stream()
                .filter(node -> NodeType.FILE.getValue().equals(node.getNodeType()))
                .filter(node -> !node.isDeleted())
                .filter(node -> node.getCurrentObjectId() != null)
                .toList();
        if (files.isEmpty()) {
            return;
        }
        for (FileNode file : files) {
            domainEventPublisher.publishTask(
                    QueueNames.FILE_RESTORE_INDEX_ROUTING_KEY,
                    toFileRestoredEvent(event.ownerUserId(), file)
            );
        }
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
