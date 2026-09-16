package com.omninest.worker.photos;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.photos.service.PhotoMotionVideoService;
import com.omninest.modules.photos.service.PhotoSourceFileService;
import com.omninest.worker.file.FilePostProcessingTaskTracker;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 动态照片运动视频提取消费者：对导入时识别为动态照片的文件提取内嵌 MP4。
 * 同步维护 sys_tasks 生命周期：领取 → 执行 → 完成 / 失败重试。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class PhotoMotionConsumer {

    private static final String TASK_TYPE = "PHOTO_MOTION";

    private final PhotoSourceFileService photoSourceFileService;
    private final PhotoMotionVideoService photoMotionVideoService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final FilePostProcessingTaskTracker taskTracker;

    /**
     * 执行动态视频提取任务并确认消息结果。
     *
     * @param event 照片源文件事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.PHOTO_MOTION_QUEUE)
    public void handle(FileUploadedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        FilePostProcessingTaskTracker.TrackedTask tracked =
                taskTracker.begin(event.ownerUserId(), TASK_TYPE, event.fileNodeId(), "PROCESSING");
        if (tracked.shouldSkip()) {
            log.info("动态视频提取任务已被其他消费者领取，跳过重复处理: fileNodeId={}", event.fileNodeId());
            channel.basicAck(deliveryTag, false);
            return;
        }
        try {
            if (!fileLifecycleGuard.isOwnedProcessable(event.ownerUserId(), event.fileNodeId())) {
                log.info("源文件已删除或正在永久删除，跳过动态视频提取任务: fileNodeId={}", event.fileNodeId());
                taskTracker.complete(tracked.taskId(), Map.of("skipped", true, "reason", "SOURCE_DELETED"));
                channel.basicAck(deliveryTag, false);
                return;
            }
            // provider 无关取源：MinIO 托管与本地媒体挂载的照片统一走受控暂存。
            try (PhotoSourceFileService.StagedPhotoFile source =
                         photoSourceFileService.stageReadable(event.ownerUserId(), event.fileNodeId())) {
                UUID videoFileNodeId = photoMotionVideoService.extractAndStore(
                        event.ownerUserId(),
                        event.fileNodeId(),
                        source.path()
                );
                taskTracker.complete(tracked.taskId(), Map.of(
                        "videoFileNodeId", videoFileNodeId == null ? "" : videoFileNodeId.toString()
                ));
            }
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("动态视频提取失败: fileNodeId={}", event.fileNodeId(), e);
            taskTracker.handleFailure(
                    TASK_TYPE,
                    QueueNames.PHOTO_MOTION_ROUTING_KEY,
                    tracked.taskId(),
                    event,
                    e
            );
            channel.basicAck(deliveryTag, false);
        }
    }
}
