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
    private static final String PHOTO_MOTION_TASK_TYPE = "PHOTO_MOTION";
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
        Map<String, Object> payload = postProcessPayload(event);
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
     * 在当前文件事务内创建正文提取和缩略图任务并写入 outbox。
     *
     * <p>只有可提取文本的文件才需要正文索引任务：文件名检索由数据库按当前名称实时完成，
     * 不再为每份文件写一条只有元数据的索引文档，因此非文档类文件在这里没有任何索引任务。</p>
     *
     * @param event 文件上传事件
     * @param mimeType 文件 MIME 类型
     */
    @Transactional(rollbackFor = Exception.class)
    public void enqueuePostProcess(FileUploadedEvent event, String mimeType) {
        if (isTextExtractable(mimeType) && !hasActiveTask(event, "TEXT_EXTRACTION")) {
            enqueueTextExtraction(event);
        }
        if (isImage(mimeType) && !hasActiveTask(event, "THUMBNAIL")) {
            enqueueThumbnail(event);
        }
    }

    /**
     * 为索引重建或内容索引迁移派发正文提取任务，不重做缩略图等派生资产。
     *
     * <p>沿用上传后处理的任务类型与 active-task 去重，因此管理员重试、恢复与死信语义
     * 一并生效；派生资产已在首次上传时生成，重建正文索引不应重新覆盖它们。</p>
     *
     * @param event 由存量文件节点还原的文件事件
     */
    @Transactional(rollbackFor = Exception.class)
    public void enqueueReindex(FileUploadedEvent event) {
        if (isTextExtractable(event.mimeType()) && !hasActiveTask(event, "TEXT_EXTRACTION")) {
            enqueueTextExtraction(event);
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

    /**
     * 为已识别的动态照片投递运动视频提取任务；已有进行中的同任务时跳过。
     *
     * <p>仅由照片导入在检测命中后调用，调用方负责事务提交时机（经 outbox 投递）。</p>
     *
     * @param event 照片源文件事件
     */
    @Transactional(rollbackFor = Exception.class)
    public void enqueuePhotoMotionIfAbsent(FileUploadedEvent event) {
        if (hasActiveTask(event, PHOTO_MOTION_TASK_TYPE)) {
            return;
        }
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                event.ownerUserId(),
                PHOTO_MOTION_TASK_TYPE,
                QueueNames.PHOTO_MOTION_ROUTING_KEY,
                "PENDING",
                RESOURCE_TYPE,
                event.fileNodeId(),
                postProcessPayload(event)
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_MOTION_ROUTING_KEY,
                event
        );
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

    /**
     * 后处理类任务记录载荷：与 {@link FileUploadedEvent} 同形。
     *
     * <p>必须存完整事件字段：管理员重试与死信重投在投递行已过保留期时只能从任务记录
     * 重建消息，缺 bucket/objectKey/occurredAt 会让重建直接报"缺少可重试载荷字段"，
     * 表现为"重试按钮对该任务永久失效"。</p>
     */
    private Map<String, Object> postProcessPayload(FileUploadedEvent event) {
        return Map.of(
                "fileNodeId", event.fileNodeId().toString(),
                "fileObjectId", event.fileObjectId().toString(),
                "ownerUserId", event.ownerUserId().toString(),
                "bucket", event.bucket() == null ? "" : event.bucket(),
                "objectKey", event.objectKey() == null ? "" : event.objectKey(),
                "fileName", event.fileName(),
                "mimeType", event.mimeType() == null ? "" : event.mimeType(),
                "sizeBytes", event.sizeBytes(),
                "occurredAt", event.occurredAt() == null ? "" : event.occurredAt().toString()
        );
    }

    private static boolean isTextExtractable(String mimeType) {
        if (mimeType == null) {
            return false;
        }
        String lower = mimeType.toLowerCase(Locale.ROOT);
        // application/* 的纯文本结构化格式同样能被 Tika 抽出正文：
        // 漏掉它们会让 JSON/XML/RTF/CSV 等只能按文件名搜到，重命名后也不会触发重建。
        return lower.startsWith("text/")
                || lower.contains("pdf")
                || lower.contains("epub")
                || lower.contains("officedocument")
                || lower.contains("msword")
                || lower.contains("mspowerpoint")
                || lower.contains("msexcel")
                || lower.contains("opendocument")
                || lower.contains("json")
                || lower.contains("xml")
                || lower.contains("rtf")
                || lower.contains("csv")
                || lower.contains("sql")
                || lower.contains("javascript")
                || lower.contains("yaml")
                || lower.contains("toml")
                || lower.contains("x-sh")
                || lower.equals("application/x-httpd-php");
    }

    private static boolean isImage(String mimeType) {
        return mimeType != null && mimeType.toLowerCase(Locale.ROOT).startsWith("image/");
    }
}
