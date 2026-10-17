package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.search.service.FileSearchIndexService;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * 文件恢复后的搜索索引重建监听。
 *
 * <p>必须在恢复事务提交后执行：Lucene 写入不受数据库事务约束，提交前写索引会让回滚的事务留下
 * 指向未恢复节点的幽灵文档。{@code @TransactionalEventListener} 在事务外发布的事件上不会触发，
 * 而该事件的唯一两个发布点（{@code FileQueryService.restoreNode} 与 {@code batchRestoreNodes}）
 * 都在 {@code @Transactional} 方法内，与同事件的 {@code FileRestoreTaskPublisher} 前提一致。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileIndexEventListener {
    private final FileSearchIndexService fileSearchIndexService;
    private final FileNodeRepository fileNodeRepository;

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(readOnly = true, propagation = Propagation.REQUIRES_NEW)
    public void handleFileNodesRestored(FileNodesRestoredEvent event) {
        if (event.fileNodeIds() == null || event.fileNodeIds().isEmpty()) {
            return;
        }
        List<FileNode> nodes = fileNodeRepository.findAllById(event.fileNodeIds());
        List<FileSearchIndexService.IndexDocumentInput> inputs = nodes.stream()
                .filter(node -> !node.isDeleted())
                .map(node -> new FileSearchIndexService.IndexDocumentInput(
                        node.getId(),
                        node.getName(),
                        null,
                        node.getSpaceType().getValue()
                ))
                .toList();
        if (!inputs.isEmpty()) {
            fileSearchIndexService.indexFiles(event.ownerUserId(), inputs);
        }
        log.info("文件恢复后批量重新索引: count={}", inputs.size());
    }
}
