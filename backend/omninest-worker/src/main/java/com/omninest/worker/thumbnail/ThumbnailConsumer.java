package com.omninest.worker.thumbnail;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.photos.service.PhotoSourceFileService;
import com.omninest.modules.photos.service.PhotoThumbnailService;
import com.omninest.modules.photos.service.PhotoAdminService;
import com.omninest.worker.file.FilePostProcessingTaskTracker;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 缩略图生成消费者：对上传的图片文件自动生成缩略图。
 * 同步维护 sys_tasks 生命周期：领取 → 执行 → 完成 / 失败重试。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class ThumbnailConsumer {

    private static final Set<String> IMAGE_MIME_PREFIXES = Set.of("image/jpeg", "image/png", "image/gif", "image/bmp");
    private static final String TASK_TYPE = "THUMBNAIL";

    private final PhotoSourceFileService photoSourceFileService;
    private final PhotoThumbnailService photoThumbnailService;
    private final PhotoAdminService photoAdminService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final FilePostProcessingTaskTracker taskTracker;

    @RabbitListener(queues = QueueNames.THUMBNAIL_QUEUE)
    public void handle(FileUploadedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        FilePostProcessingTaskTracker.TrackedTask tracked =
                taskTracker.begin(event.ownerUserId(), TASK_TYPE, event.fileNodeId(), "PROCESSING");
        if (tracked.shouldSkip()) {
            log.info("缩略图任务已被其他消费者领取，跳过重复处理: fileNodeId={}", event.fileNodeId());
            channel.basicAck(deliveryTag, false);
            return;
        }
        try {
            if (!isSupportedImage(event.mimeType())) {
                log.debug("跳过非图片文件缩略图生成: fileNodeId={}, mimeType={}", event.fileNodeId(), event.mimeType());
                taskTracker.complete(tracked.taskId(), Map.of("skipped", true, "reason", "UNSUPPORTED_MIME"));
                channel.basicAck(deliveryTag, false);
                return;
            }
            if (!fileLifecycleGuard.isOwnedProcessable(event.ownerUserId(), event.fileNodeId())) {
                log.info("源文件已删除或正在永久删除，跳过缩略图任务: fileNodeId={}", event.fileNodeId());
                taskTracker.complete(tracked.taskId(), Map.of("skipped", true, "reason", "SOURCE_DELETED"));
                channel.basicAck(deliveryTag, false);
                return;
            }

            // 快速路径：缩略图资产已存在时仅回填封面引用，避免重复解码。
            Optional<UUID> storedThumbnail = photoThumbnailService.findStoredThumbnailFileNodeId(
                    event.ownerUserId(), event.fileNodeId());
            if (storedThumbnail.isPresent()) {
                log.info("缩略图已存在，直接回填封面: fileNodeId={}, thumbnailId={}",
                        event.fileNodeId(), storedThumbnail.get());
                photoAdminService.attachCoverIfMissing(
                        event.ownerUserId(), event.fileNodeId(), storedThumbnail.get());
                taskTracker.complete(tracked.taskId(), Map.of("thumbnailId", storedThumbnail.get().toString()));
                channel.basicAck(deliveryTag, false);
                return;
            }

            log.info("开始生成缩略图: fileNodeId={}, fileName={}", event.fileNodeId(), event.fileName());
            UUID thumbnailId = null;
            // provider 无关取源：MinIO 托管与本地媒体挂载的照片统一走受控暂存。
            try (PhotoSourceFileService.StagedPhotoFile source = photoSourceFileService.stageReadable(
                    event.ownerUserId(), event.fileNodeId())) {
                thumbnailId = photoThumbnailService.generateAndStoreFile(
                        event.ownerUserId(), event.fileNodeId(), source.path(), source.fileName());
                if (thumbnailId != null) {
                    photoAdminService.attachCoverIfMissing(
                            event.ownerUserId(), event.fileNodeId(), thumbnailId);
                    log.info("缩略图生成完成: fileNodeId={}, thumbnailId={}", event.fileNodeId(), thumbnailId);
                } else {
                    log.info("缩略图生成跳过（不支持的格式）: fileNodeId={}", event.fileNodeId());
                }
            }
            taskTracker.complete(tracked.taskId(), Map.of("thumbnailId", thumbnailId == null ? "" : thumbnailId.toString()));
            channel.basicAck(deliveryTag, false);
        } catch (Exception e) {
            log.error("缩略图生成失败: fileNodeId={}", event.fileNodeId(), e);
            taskTracker.handleFailure(TASK_TYPE, QueueNames.THUMBNAIL_ROUTING_KEY, tracked.taskId(), event, e);
            channel.basicAck(deliveryTag, false);
        }
    }

    private boolean isSupportedImage(String mimeType) {
        if (mimeType == null) {
            return false;
        }
        String lower = mimeType.toLowerCase(Locale.ROOT);
        return IMAGE_MIME_PREFIXES.stream().anyMatch(lower::startsWith);
    }
}
