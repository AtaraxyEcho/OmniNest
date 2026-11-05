package com.omninest.worker.tika;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.search.service.FileSearchIndexService;
import com.omninest.worker.file.FilePostProcessingTaskTracker;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 文本提取消费者：编排生命周期与索引写入，Tika 解析下沉 {@link TextExtractionService}。
 * 同步维护 sys_tasks 生命周期：领取 → 执行 → 完成 / 失败重试。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class TextExtractionConsumer {

    private static final String TASK_TYPE = "TEXT_EXTRACTION";

    private final TextExtractionService textExtractionService;
    private final FileSearchIndexService fileSearchIndexService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final FilePostProcessingTaskTracker taskTracker;

    @RabbitListener(
            queues = QueueNames.TEXT_EXTRACTION_QUEUE,
            concurrency = "${omninest.worker.text-extraction-concurrency:2}"
    )
    public void handle(FileUploadedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        FilePostProcessingTaskTracker.TrackedTask tracked = null;
        FileSearchIndexService.ChunkIndexSession indexSession = null;
        UUID extractedObjectId = null;
        boolean indexCommitted = false;
        try {
            // 领取也在 try 内：手动 ACK 模式没有容器兜底，领取异常逃逸会让消息永久 Unacked。
            tracked = taskTracker.begin(event.ownerUserId(), TASK_TYPE, event.fileNodeId(), "EXTRACTING");
            if (tracked.shouldSkip()) {
                log.info("文本提取任务已被其他消费者领取，跳过重复处理: fileNodeId={}", event.fileNodeId());
                channel.basicAck(deliveryTag, false);
                return;
            }
            log.info("收到文本提取任务: fileNodeId={}, fileName={}", event.fileNodeId(), event.fileName());
            // 流式写入需要提前知道空间归属；解析耗时段内文件被删除时，完成后统一清理已写文档。
            FileDescriptor descriptor = fileLifecycleGuard
                    .findOwnedProcessable(event.ownerUserId(), event.fileNodeId())
                    .orElse(null);
            if (descriptor == null) {
                log.info("源文件已删除或正在永久删除，跳过文本提取: fileNodeId={}", event.fileNodeId());
                skipAndAck(channel, deliveryTag, tracked, "SOURCE_DELETED");
                return;
            }
            if (descriptor.currentObjectId() == null) {
                // 外链导入占位节点等场景可能还没有内容对象：正文索引以对象为键，没有键就无从写入。
                log.info("文件尚无内容对象，跳过文本提取: fileNodeId={}", event.fileNodeId());
                skipAndAck(channel, deliveryTag, tracked, "NO_CONTENT_OBJECT");
                return;
            }
            // 正文按不可变的内容对象索引：节点标识与文件名都是可变元数据，
            // 以它们为键会让每次重命名都退化成整份文件的重新解析。
            extractedObjectId = descriptor.currentObjectId();
            indexSession = fileSearchIndexService.openChunkIndex(
                    extractedObjectId,
                    event.ownerUserId(),
                    descriptor.spaceType().getValue()
            );
            TextExtractionService.ExtractionResult extraction =
                    textExtractionService.extract(event.ownerUserId(), event.fileNodeId(), indexSession::append);
            FileDescriptor current = fileLifecycleGuard
                    .findOwnedProcessable(event.ownerUserId(), event.fileNodeId())
                    .orElse(null);
            if (current == null) {
                log.info("源文件在文本提取期间进入永久删除流程，放弃索引写入: fileNodeId={}",
                        event.fileNodeId());
                fileSearchIndexService.deleteObjects(List.of(extractedObjectId), event.ownerUserId());
                skipAndAck(channel, deliveryTag, tracked, "SOURCE_DELETED");
                return;
            }
            int chunkCount = indexSession.complete();
            indexCommitted = true;
            if (chunkCount > 0) {
                log.info("文本提取完成: fileNodeId={}, 文本长度={}, chunkCount={}, truncated={}",
                        event.fileNodeId(), extraction.textLength(), chunkCount, extraction.truncated());
            } else {
                log.info("文件无可提取文本: fileNodeId={}", event.fileNodeId());
            }
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("textLength", extraction.textLength());
            result.put("chunkCount", chunkCount);
            if (extraction.truncated()) {
                result.put("truncated", true);
                result.put("chunkSize", extraction.chunkSize());
                result.put("maxChunks", extraction.maxChunks());
            }
            taskTracker.complete(tracked.taskId(), result);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("文本提取失败: fileNodeId={}", event.fileNodeId(), e);
            if (indexSession != null && !indexCommitted && extractedObjectId != null) {
                // 分块是边解析边写入的：中途失败会在写缓冲里留下半截文档，
                // 被后续文件的提交顺带刷出后就会命中残缺正文，必须按对象清掉再提交。
                try {
                    fileSearchIndexService.deleteObjects(
                            List.of(extractedObjectId), event.ownerUserId());
                } catch (RuntimeException cleanupException) {
                    log.warn("文本提取失败后清理半截索引失败: fileNodeId={}, errorType={}",
                            event.fileNodeId(), cleanupException.getClass().getSimpleName(), cleanupException);
                }
            }
            try {
                if (tracked == null) {
                    log.error("文本提取任务领取失败，转入死信队列: fileNodeId={}, errorType={}",
                            event.fileNodeId(), e.getClass().getSimpleName());
                    channel.basicNack(deliveryTag, false, false);
                    return;
                }
                taskTracker.handleFailure(
                        TASK_TYPE, QueueNames.TEXT_EXTRACTION_ROUTING_KEY, tracked.taskId(), event, e);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException stateException) {
                log.error("文本提取失败状态写入失败，转入死信队列: taskId={}, errorType={}",
                        tracked.taskId(), stateException.getClass().getSimpleName(), stateException);
                channel.basicNack(deliveryTag, false, false);
            }
        }
    }

    /** 回写跳过原因并确认消息：手动 ACK 没有容器兜底，提前返回必须显式 ACK。 */
    private void skipAndAck(Channel channel, long deliveryTag,
            FilePostProcessingTaskTracker.TrackedTask tracked, String reason) throws IOException {
        taskTracker.complete(tracked.taskId(), Map.of("skipped", true, "reason", reason));
        channel.basicAck(deliveryTag, false);
    }
}
