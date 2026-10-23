package com.omninest.modules.file.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.event.SearchIndexRebuildEvent;
import com.omninest.modules.search.service.FileSearchIndexService;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 全站搜索索引重建服务。
 *
 * <p>接口只落任务记录并投递 Outbox，清索引与逐文件重投放在 Worker 侧异步执行：
 * 存量文件可达十万级，同步重建必然超出请求超时，且 Lucene 写入必须留在单写进程内。</p>
 *
 * <p>本服务只覆盖文件索引根目录；照片索引是另一个独立根目录，由 Worker 侧消费者
 * 在同一任务里追加调用 {@code PhotoIndexTaskService.rebuildAll()}，
 * 因为 File 模块不依赖 Media 模块。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class SearchIndexRebuildService {
    /** 任务类型字面量。 */
    public static final String TASK_TYPE = "SEARCH_INDEX_REBUILD";

    private static final int SCAN_BATCH_SIZE = 500;
    private static final List<String> ACTIVE_TASK_STATUSES = List.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RUNNING.getValue(),
            TaskStatus.RETRY_WAIT.getValue()
    );

    private final FileNodeRepository fileNodeRepository;
    private final FileSearchIndexService fileSearchIndexService;
    private final FilePostProcessingTaskService filePostProcessingTaskService;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 受理重建请求：在同一事务内创建任务记录与 outbox 投递行。
     *
     * @param actorUserId 触发重建的管理员用户 ID
     * @return 任务 ID，客户端按既有任务轮询接口跟踪进度
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID start(UUID actorUserId) {
        // 全站重建是重 IO 任务，已有排队/执行中的重建直接复用，不重复清空索引。
        List<UUID> activeTaskIds = taskRecordService.findActiveTaskIdsByType(TASK_TYPE, ACTIVE_TASK_STATUSES);
        if (!activeTaskIds.isEmpty()) {
            return activeTaskIds.getFirst();
        }
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                actorUserId,
                TASK_TYPE,
                QueueNames.SEARCH_INDEX_REBUILD_ROUTING_KEY,
                Map.of("actorUserId", actorUserId.toString())
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.SEARCH_INDEX_REBUILD_ROUTING_KEY,
                new SearchIndexRebuildEvent(taskId, actorUserId)
        );
        return taskId;
    }

    /**
     * 清空全站索引并按存量文件重新派发索引与文本提取任务。
     *
     * <p>仅由 Worker 侧消费调用。重建派发复用上传后处理的任务类型，因此已有 active-task
     * 去重、重试与死信语义一并生效；正文抽取仍由 {@code TEXT_EXTRACTION} 承担，
     * 本方法不会在请求或调度进程里读取文件内容。</p>
     *
     * @param taskId 任务记录 ID
     * @return 派发统计与清空文档数
     */
    public Map<String, Object> rebuild(UUID taskId) {
        taskRecordService.markRunning(taskId, "REBUILDING");
        int cleared = fileSearchIndexService.clearAllIndexes();
        long total = fileNodeRepository.countIndexableFiles(NodeType.FILE.getValue());
        log.info("开始重建全站搜索索引: taskId={}, 待派发文件数={}, 已清空文档数={}",
                taskId, total, cleared);
        int dispatched = dispatchAll(taskId, total);
        return Map.of(
                "clearedDocuments", cleared,
                "dispatchedFiles", dispatched,
                "scannedFiles", total
        );
    }

    private int dispatchAll(UUID taskId, long total) {
        UUID afterId = new UUID(0L, 0L);
        int dispatched = 0;
        while (!taskRecordService.isCancelled(taskId)) {
            List<FileNode> batch = fileNodeRepository.findIndexableFilesAfterId(
                    NodeType.FILE.getValue(), afterId, PageRequest.of(0, SCAN_BATCH_SIZE));
            if (batch.isEmpty()) {
                break;
            }
            for (FileNode node : batch) {
                filePostProcessingTaskService.enqueueReindex(FileUploadedEvent.fromNode(node));
                dispatched++;
            }
            afterId = batch.getLast().getId();
            if (batch.size() < SCAN_BATCH_SIZE) {
                break;
            }
            taskRecordService.updateProgress(taskId, progressPercent(dispatched, total));
        }
        return dispatched;
    }

    private int progressPercent(int done, long total) {
        if (total <= 0L) {
            return 99;
        }
        return (int) Math.min(99L, (long) done * 100L / total);
    }
}
