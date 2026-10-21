package com.omninest.modules.file.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.event.FileIndexSyncEvent;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.search.service.FileSearchIndexService;
import com.omninest.modules.task.service.TaskDispatchService;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 文件搜索索引同步编排服务。
 *
 * <p>索引请求一律经 Outbox 投递给 Worker，由单进程写 Lucene：API 与 Worker 共挂同一索引卷时，
 * 请求进程直接打开 {@code IndexWriter} 会与 Worker 抢 {@code write.lock}，抢锁失败被吞掉后
 * 表现为重命名与删除的索引静默丢失。口径与相册侧 {@code PhotoIndexTaskService} 一致。</p>
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
     * 请求把指定节点重新同步进搜索索引。
     *
     * <p>投递与业务写库同事务、提交后发布；写还是删由消费侧按节点当前状态决定，
     * 因此重命名、软删除、批量删除与恢复都走同一入口。</p>
     *
     * @param ownerUserId 索引归属用户 ID
     * @param fileNodeIds 需要同步的文件节点 ID
     */
    public void scheduleAfterCommit(UUID ownerUserId, Collection<UUID> fileNodeIds) {
        if (ownerUserId == null || fileNodeIds == null || fileNodeIds.isEmpty()) {
            return;
        }
        List<UUID> ids = List.copyOf(fileNodeIds);
        taskDispatchService.enqueue(
                ids.getFirst(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_INDEX_SYNC_ROUTING_KEY,
                new FileIndexSyncEvent(ownerUserId, ids)
        );
    }

    /**
     * 按节点当前数据库状态重投索引或移出索引。
     *
     * <p>仅由 Worker 侧消费调用。重命名、软删除、批量删除、恢复、复制与转存共用同一入口，
     * 由节点当前状态决定重投还是移出。</p>
     *
     * <p>活动节点一律交回 {@code FILE_INDEX + TEXT_EXTRACTION}，不写「只补元数据」的快路径：
     * 正文分块与标题共用同一个 {@code fileId} Term，而正文列 {@code Store.NO} 不可回读，
     * 任何绕开抽取的重投都只能让文件按名字搜得到、按内容搜不到——实机验证过还原与复制
     * 就是这个结果。沿用后处理任务类型还能一并吃到 active-task 去重、重试与死信语义。</p>
     *
     * @param ownerUserId 索引归属用户 ID
     * @param fileNodeIds 需要同步的文件节点 ID
     * @return 实际处理的节点数
     */
    public int sync(UUID ownerUserId, List<UUID> fileNodeIds) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return 0;
        }
        Map<UUID, FileNode> nodesById = fileNodeRepository.findAllById(fileNodeIds).stream()
                .collect(Collectors.toMap(FileNode::getId, node -> node));
        List<UUID> removals = new ArrayList<>();
        int redispatched = 0;
        for (UUID fileNodeId : fileNodeIds) {
            FileNode node = nodesById.get(fileNodeId);
            if (node == null || node.isDeleted()) {
                removals.add(fileNodeId);
                continue;
            }
            filePostProcessingTaskService.enqueueReindex(FileUploadedEvent.fromNode(node));
            redispatched++;
        }
        if (!removals.isEmpty()) {
            fileSearchIndexService.deleteFiles(removals, ownerUserId);
        }
        return redispatched + removals.size();
    }
}
