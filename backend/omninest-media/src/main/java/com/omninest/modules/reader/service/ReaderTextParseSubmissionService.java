package com.omninest.modules.reader.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.event.ReaderParseTaskEvent;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文本书籍解析任务提交服务，保证任务记录、业务状态和 Outbox 同事务提交。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class ReaderTextParseSubmissionService {

    private final ReaderItemRepository itemRepository;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 提交文本书籍解析任务。
     *
     * @param item 阅读条目
     * @param retry 是否为重试
     * @return 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID submit(ReaderItem item, boolean retry) {
        item.setImportStatus("PARSING");
        item.setParseErrorCode(null);
        item.setParseErrorMessage(null);
        itemRepository.save(item);

        UUID taskId = UUID.randomUUID();
        // 任务记录归条目所有者（取消与任务列表按此过滤），事件里的文件操作用户必须取源文件节点的
        // 真实所有者：共享空间的书常由成员 A 上传、成员 B 导入，两者混成一个用户会让 Worker 的
        // 生命周期守卫查不到节点，把合法文件静默判成"已删除或不可处理"。
        UUID fileOwnerId = item.getFileNodeId() == null
                ? item.getOwnerUserId()
                : fileMetadataQueryService.findById(item.getFileNodeId())
                        .map(FileDescriptor::ownerUserId)
                        .orElse(item.getOwnerUserId());
        ReaderParseTaskEvent event = new ReaderParseTaskEvent(
                taskId,
                fileOwnerId,
                item.getId(),
                item.getFileNodeId(),
                item.getItemType(),
                item.getContentHash(),
                retry
        );
        // fileOwnerId 必须一起落进 payload：心跳超时恢复是从 payload 重建事件的。
        Map<String, Object> payload = Map.of(
                "ownerUserId", item.getOwnerUserId().toString(),
                "fileOwnerId", fileOwnerId.toString(),
                "itemId", item.getId().toString(),
                "fileNodeId", item.getFileNodeId().toString(),
                "fileFormat", item.getItemType(),
                "contentHash", item.getContentHash() == null ? "" : item.getContentHash(),
                "isRetry", retry
        );
        taskRecordService.createQueuedTask(
                taskId,
                item.getOwnerUserId(),
                "READER_PARSE",
                QueueNames.READER_PARSE_ROUTING_KEY,
                "PENDING",
                "READER_ITEM",
                item.getId(),
                payload
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.READER_PARSE_ROUTING_KEY,
                event
        );
        return taskId;
    }
}
