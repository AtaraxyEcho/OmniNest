package com.omninest.modules.file.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.event.MediaAutoImportRequestedEvent;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件上传后持久任务创建服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FilePostProcessingTaskService {
    private static final String TASK_TYPE = "MEDIA_AUTO_IMPORT";
    private static final String RESOURCE_TYPE = "FILE_NODE";
    private static final List<String> ACTIVE_STATUSES = List.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RUNNING.getValue(),
            TaskStatus.RETRY_WAIT.getValue()
    );

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 在当前文件事务内创建媒体自动导入任务和 outbox。
     *
     * @param event 文件上传事件
     * @return 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID enqueueMediaAutoImport(FileUploadedEvent event) {
        Optional<TaskRecord> activeTask = taskRecordService.findActiveResourceTask(
                event.ownerUserId(),
                TASK_TYPE,
                RESOURCE_TYPE,
                event.fileNodeId(),
                ACTIVE_STATUSES
        );
        if (activeTask.isPresent()) {
            return activeTask.get().getId();
        }

        UUID taskId = UUID.randomUUID();
        Map<String, Object> payload = Map.of(
                "fileNodeId", event.fileNodeId().toString(),
                "fileObjectId", event.fileObjectId().toString(),
                "fileName", event.fileName(),
                "mimeType", event.mimeType() == null ? "" : event.mimeType(),
                "sizeBytes", event.sizeBytes()
        );
        taskRecordService.createQueuedTask(
                taskId,
                event.ownerUserId(),
                TASK_TYPE,
                QueueNames.MEDIA_AUTO_IMPORT_ROUTING_KEY,
                "DETECTING",
                RESOURCE_TYPE,
                event.fileNodeId(),
                payload
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.MEDIA_AUTO_IMPORT_ROUTING_KEY,
                new MediaAutoImportRequestedEvent(taskId, event)
        );
        return taskId;
    }

    /**
     * 在当前文件事务内创建索引、文本提取和缩略图任务并写入 outbox。
     * 索引任务始终创建，文本提取仅对文档类文件，缩略图仅对图片文件。
     * 走 sys_task_dispatches outbox，避免请求线程直发 RabbitMQ。
     * 各任务带 active-task 去重，避免重复触发时堆积重复任务记录。
     *
     * @param event 文件上传事件
     * @param mimeType 文件 MIME 类型
     */
    @Transactional(rollbackFor = Exception.class)
    public void enqueuePostProcess(FileUploadedEvent event, String mimeType) {
        if (!hasActiveTask(event, "FILE_INDEX")) {
            enqueueIndex(event);
        }
        if (isTextExtractable(mimeType) && !hasActiveTask(event, "TEXT_EXTRACTION")) {
            enqueueTextExtraction(event);
        }
        if (isImage(mimeType) && !hasActiveTask(event, "THUMBNAIL")) {
            enqueueThumbnail(event);
        }
    }

    /**
     * 为导入完成的图片补投缩略图任务；已有进行中的同任务时跳过。
     *
     * <p>照片导入不再同步生成封面，由本任务在 Worker/内嵌 Worker 中
     * 异步生成并回填，避免上传请求路径承担整图解码开销。</p>
     *
     * @param event 文件上传事件
     */
    @Transactional(rollbackFor = Exception.class)
    public void enqueueThumbnailIfAbsent(FileUploadedEvent event) {
        if (isImage(event.mimeType()) && !hasActiveTask(event, "THUMBNAIL")) {
            enqueueThumbnail(event);
        }
    }

    private boolean hasActiveTask(FileUploadedEvent event, String taskType) {
        return taskRecordService.findActiveResourceTask(
                event.ownerUserId(),
                taskType,
                RESOURCE_TYPE,
                event.fileNodeId(),
                ACTIVE_STATUSES
        ).isPresent();
    }

    private void enqueueIndex(FileUploadedEvent event) {
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                event.ownerUserId(),
                "FILE_INDEX",
                QueueNames.FILE_INDEX_ROUTING_KEY,
                "PENDING",
                RESOURCE_TYPE,
                event.fileNodeId(),
                postProcessPayload(event)
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_INDEX_ROUTING_KEY,
                event
        );
    }

    private void enqueueTextExtraction(FileUploadedEvent event) {
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                event.ownerUserId(),
                "TEXT_EXTRACTION",
                QueueNames.TEXT_EXTRACTION_ROUTING_KEY,
                "PENDING",
                RESOURCE_TYPE,
                event.fileNodeId(),
                postProcessPayload(event)
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.TEXT_EXTRACTION_ROUTING_KEY,
                event
        );
    }

    private void enqueueThumbnail(FileUploadedEvent event) {
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                event.ownerUserId(),
                "THUMBNAIL",
                QueueNames.THUMBNAIL_ROUTING_KEY,
                "PENDING",
                RESOURCE_TYPE,
                event.fileNodeId(),
                postProcessPayload(event)
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.THUMBNAIL_ROUTING_KEY,
                event
        );
    }

    private Map<String, Object> postProcessPayload(FileUploadedEvent event) {
        return Map.of(
                "fileNodeId", event.fileNodeId().toString(),
                "fileObjectId", event.fileObjectId().toString(),
                "fileName", event.fileName(),
                "mimeType", event.mimeType() == null ? "" : event.mimeType(),
                "sizeBytes", event.sizeBytes()
        );
    }

    private static boolean isTextExtractable(String mimeType) {
        if (mimeType == null) {
            return false;
        }
        String lower = mimeType.toLowerCase(Locale.ROOT);
        return lower.startsWith("text/")
                || lower.contains("pdf")
                || lower.contains("epub")
                || lower.contains("officedocument")
                || lower.contains("msword")
                || lower.contains("mspowerpoint")
                || lower.contains("msexcel")
                || lower.contains("opendocument");
    }

    private static boolean isImage(String mimeType) {
        return mimeType != null && mimeType.toLowerCase(Locale.ROOT).startsWith("image/");
    }
}
