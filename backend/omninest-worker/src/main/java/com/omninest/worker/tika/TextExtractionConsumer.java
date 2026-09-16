package com.omninest.worker.tika;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.search.service.FileSearchIndexService;
import com.omninest.worker.file.FilePostProcessingTaskTracker;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.io.InputStream;
import java.util.LinkedHashMap;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.tika.exception.WriteLimitReachedException;
import org.apache.tika.metadata.Metadata;
import org.apache.tika.parser.AutoDetectParser;
import org.apache.tika.parser.ParseContext;
import org.apache.tika.parser.Parser;
import org.apache.tika.sax.BodyContentHandler;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 文本提取消费者，使用 Apache Tika 从文件中提取文本内容并写入 Lucene 索引。
 * 同步维护 sys_tasks 生命周期：领取 → 执行 → 完成 / 失败重试。
 * 超过写入上限时按已提取片段完成索引，避免长文（如长篇小说 EPUB）被误判为提取失败。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class TextExtractionConsumer {

    /**
     * 搜索索引用文本写入上限。足够覆盖多数长篇中文小说，同时约束单文档内存占用。
     */
    private static final int MAX_CONTENT_LENGTH = 2_000_000;
    private static final String TASK_TYPE = "TEXT_EXTRACTION";

    private final ObjectStorageClient objectStorageClient;
    private final FileSearchIndexService fileSearchIndexService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final FilePostProcessingTaskTracker taskTracker;

    @RabbitListener(queues = QueueNames.TEXT_EXTRACTION_QUEUE)
    public void handle(FileUploadedEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        FilePostProcessingTaskTracker.TrackedTask tracked =
                taskTracker.begin(event.ownerUserId(), TASK_TYPE, event.fileNodeId(), "EXTRACTING");
        if (tracked.shouldSkip()) {
            log.info("文本提取任务已被其他消费者领取，跳过重复处理: fileNodeId={}", event.fileNodeId());
            channel.basicAck(deliveryTag, false);
            return;
        }
        try {
            if (!fileLifecycleGuard.isOwnedProcessable(event.ownerUserId(), event.fileNodeId())) {
                log.info("源文件已删除或正在永久删除，跳过文本提取: fileNodeId={}", event.fileNodeId());
                taskTracker.complete(tracked.taskId(), Map.of("skipped", true, "reason", "SOURCE_DELETED"));
                channel.basicAck(deliveryTag, false);
                return;
            }
            log.info("收到文本提取任务: fileNodeId={}, fileName={}", event.fileNodeId(), event.fileName());
            ObjectStorageKey key = new ObjectStorageKey(event.bucket(), event.objectKey());
            int textLength = 0;
            boolean truncated = false;
            try (InputStream inputStream = objectStorageClient.getObject(key)) {
                AutoDetectParser parser = new AutoDetectParser();
                BodyContentHandler handler = new BodyContentHandler(MAX_CONTENT_LENGTH);
                Metadata metadata = new Metadata();
                ParseContext context = new ParseContext();
                context.set(Parser.class, parser);
                try {
                    parser.parse(inputStream, handler, metadata, context);
                } catch (Exception parseException) {
                    if (!isWriteLimitReached(parseException)) {
                        throw parseException;
                    }
                    // 上限保护的是内存与索引体积；已达上限的片段仍可检索，按部分成功完成。
                    truncated = true;
                    log.info("文本提取达到写入上限，按已提取片段建立索引: fileNodeId={}, limit={}",
                            event.fileNodeId(), MAX_CONTENT_LENGTH);
                }
                String extractedText = handler.toString();
                if (extractedText != null && !extractedText.isBlank()) {
                    if (!fileLifecycleGuard.isOwnedProcessable(event.ownerUserId(), event.fileNodeId())) {
                        log.info("源文件在文本提取期间进入永久删除流程，放弃索引写入: fileNodeId={}",
                                event.fileNodeId());
                        taskTracker.complete(tracked.taskId(), Map.of("skipped", true, "reason", "SOURCE_DELETED"));
                        channel.basicAck(deliveryTag, false);
                        return;
                    }
                    fileSearchIndexService.indexFile(
                            event.fileNodeId(),
                            event.ownerUserId(),
                            event.fileName(),
                            extractedText
                    );
                    textLength = extractedText.length();
                    log.info("文本提取完成: fileNodeId={}, 文本长度={}, truncated={}",
                            event.fileNodeId(), textLength, truncated);
                } else {
                    log.info("文件无可提取文本: fileNodeId={}", event.fileNodeId());
                }
            }
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("textLength", textLength);
            if (truncated) {
                result.put("truncated", true);
                result.put("writeLimit", MAX_CONTENT_LENGTH);
            }
            taskTracker.complete(tracked.taskId(), result);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("文本提取失败: fileNodeId={}", event.fileNodeId(), e);
            taskTracker.handleFailure(TASK_TYPE, QueueNames.TEXT_EXTRACTION_ROUTING_KEY, tracked.taskId(), event, e);
            channel.basicAck(deliveryTag, false);
        }
    }

    private boolean isWriteLimitReached(Throwable throwable) {
        Throwable current = throwable;
        while (current != null) {
            if (current instanceof WriteLimitReachedException) {
                return true;
            }
            current = current.getCause();
        }
        return false;
    }
}
