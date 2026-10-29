package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 子树软删除：按批标记后代并逐批投递索引与删除事件。
 *
 * <p>从文件查询服务中拆出，让删除路径与查询路径各自独立演进；后代只取 ID，
 * 不实体化整棵子树。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
class FileSubtreeSoftDeleter {

    private static final int BATCH_SIZE = 500;

    private final FileNodeRepository fileNodeRepository;
    private final FileIndexSyncService fileIndexSyncService;
    private final ApplicationEventPublisher eventPublisher;
    private final FileNodeLookupSupport lookup;

    /**
     * 软删节点下的全部活动后代。
     *
     * @param ownerUserId 所有者用户 ID
     * @param node 子树根节点
     * @param deletedAt 删除时间
     * @param collectedIds 需要收集被删 ID 时传入可写集合，否则为 null
     */
    @Transactional(rollbackFor = Exception.class)
    void softDeleteDescendants(UUID ownerUserId, FileNode node, Instant deletedAt, List<UUID> collectedIds) {
        while (true) {
            List<UUID> ids = fileNodeRepository.findActiveIdsByPathPrefix(
                    ownerUserId, node.getSpaceType(), lookup.subtreePrefix(node),
                    PageRequest.of(0, BATCH_SIZE)).getContent();
            if (ids.isEmpty()) {
                return;
            }
            fileNodeRepository.softDeleteIds(ownerUserId, ids, deletedAt);
            fileIndexSyncService.scheduleAfterCommit(ownerUserId, ids);
            eventPublisher.publishEvent(new FileNodesSoftDeletedEvent(ownerUserId, List.copyOf(ids), deletedAt));
            if (collectedIds != null) {
                collectedIds.addAll(ids);
            }
        }
    }
}
