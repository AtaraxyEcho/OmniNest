package com.omninest.modules.file.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.event.FileIndexSyncEvent;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.search.service.FileSearchIndexService;
import com.omninest.modules.task.service.TaskDispatchService;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 文件正文索引迁移服务：把「内容对象还没出现在目标索引目录」的节点重新投递正文提取。
 *
 * <p>正文以不可变的 {@code fileObjectId} 为键、按用户目录物理隔离，因此重命名、移动目录、
 * 复制、软删除与回收站还原都不再需要任何索引投递——节点标识与文件名都以数据库为实时真值。
 * 只剩两种场景需要把内容搬到另一个目录：</p>
 * <ul>
 *   <li><b>跨空间移动</b>：正文原本在个人目录（或共享目录），迁到另一侧后成员检索不到；</li>
 *   <li><b>转存他人共享文件</b>：内容对象属于对方，本人的目录里还没有这份正文。</li>
 * </ul>
 *
 * <p>正文列 {@code Store.NO} 不可回读，跨目录复制只能重新解析源文件，所以这条路径保留
 * Outbox + Worker 单写进程：请求进程直接写会与 Worker 抢 {@code write.lock}，抢锁失败
 * 被吞掉后表现为索引静默丢失。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileIndexSyncService {
    private final FileNodeRepository fileNodeRepository;
    private final FileSearchIndexService fileSearchIndexService;
    private final FilePostProcessingTaskService filePostProcessingTaskService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 请求把指定节点的正文迁移进它当前所属空间的索引目录。
     *
     * <p>投递与业务写库同事务、提交后发布；是否需要真正解析由消费侧按索引现状决定。</p>
     *
     * @param ownerUserId 索引归属用户 ID
     * @param fileNodeIds 需要同步的文件节点 ID
     */
    public void scheduleAfterCommit(UUID ownerUserId, List<UUID> fileNodeIds) {
        if (ownerUserId == null || fileNodeIds == null || fileNodeIds.isEmpty()) {
            return;
        }
        taskDispatchService.enqueue(
                fileNodeIds.getFirst(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_INDEX_SYNC_ROUTING_KEY,
                new FileIndexSyncEvent(ownerUserId, List.copyOf(fileNodeIds))
        );
    }

    /**
     * 按索引现状决定是否为节点重投正文提取。
     *
     * <p>仅由 Worker 侧消费调用。目标目录里已有该对象的正文时直接跳过，因此同一空间内的
     * 复制、改名与还原不会触发任何 Tika 解析。</p>
     *
     * @param ownerUserId 索引归属用户 ID
     * @param fileNodeIds 需要同步的文件节点 ID
     * @return 实际重投正文提取的节点数
     */
    public int sync(UUID ownerUserId, List<UUID> fileNodeIds) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return 0;
        }
        Map<UUID, FileNode> nodesById = fileNodeRepository.findAllById(fileNodeIds).stream()
                .collect(Collectors.toMap(FileNode::getId, node -> node));
        int redispatched = 0;
        for (UUID fileNodeId : fileNodeIds) {
            FileNode node = nodesById.get(fileNodeId);
            // 软删除由数据库在检索时过滤，索引里留着正文不会露出，也不需要清理。
            if (node == null || node.isDeleted()) {
                continue;
            }
            // 文件夹没有内容对象，进入后处理会在构造载荷时抛空指针并让同批剩余文件全部中断。
            if (!NodeType.FILE.getValue().equalsIgnoreCase(node.getNodeType())
                    || node.getCurrentObjectId() == null) {
                continue;
            }
            if (fileSearchIndexService.hasObjectContent(
                    node.getOwnerUserId(),
                    node.getSpaceType().getValue(),
                    node.getCurrentObjectId())) {
                continue;
            }
            filePostProcessingTaskService.enqueueReindex(FileUploadedEvent.fromNode(node));
            redispatched++;
        }
        log.debug("文件正文索引迁移: 节点数={}, 重投解析数={}", fileNodeIds.size(), redispatched);
        return redispatched;
    }
}
