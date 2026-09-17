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
import java.io.Writer;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
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
 * 超长文本（千万字级网文）按固定字符块分片写入多条 Lucene 文档，避免单文档内存与字段体积失控。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class TextExtractionConsumer {

    /**
     * 单个 Lucene 文档的最大正文字符数。
     */
    private static final int CHUNK_SIZE_CHARS = 500_000;
    /**
     * 安全护栏：单文件最多索引的块数，对应约 1 亿字符。
     */
    private static final int MAX_CHUNKS = 200;
    private static final String TASK_TYPE = "TEXT_EXTRACTION";

    private final ObjectStorageClient objectStorageClient;
    private final FileSearchIndexService fileSearchIndexService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final FilePostProcessingTaskTracker taskTracker;

    @RabbitListener(
            queues = QueueNames.TEXT_EXTRACTION_QUEUE,
            concurrency = "${omninest.worker.text-extraction-concurrency:2}"
    )
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
            ChunkingTextCollector collector = new ChunkingTextCollector(CHUNK_SIZE_CHARS, MAX_CHUNKS);
            try (InputStream inputStream = objectStorageClient.getObject(key)) {
                AutoDetectParser parser = new AutoDetectParser();
                BodyContentHandler handler = new BodyContentHandler(collector);
                Metadata metadata = new Metadata();
                ParseContext context = new ParseContext();
                context.set(Parser.class, parser);
                parser.parse(inputStream, handler, metadata, context);
                collector.finish();
            }
            List<String> chunks = collector.chunks();
            int textLength = collector.textLength();
            boolean truncated = collector.truncated();
            if (!chunks.isEmpty()) {
                if (!fileLifecycleGuard.isOwnedProcessable(event.ownerUserId(), event.fileNodeId())) {
                    log.info("源文件在文本提取期间进入永久删除流程，放弃索引写入: fileNodeId={}",
                            event.fileNodeId());
                    taskTracker.complete(tracked.taskId(), Map.of("skipped", true, "reason", "SOURCE_DELETED"));
                    channel.basicAck(deliveryTag, false);
                    return;
                }
                fileSearchIndexService.indexFileChunks(
                        event.fileNodeId(),
                        event.ownerUserId(),
                        event.fileName(),
                        chunks,
                        "PERSONAL"
                );
                log.info("文本提取完成: fileNodeId={}, 文本长度={}, chunkCount={}, truncated={}",
                        event.fileNodeId(), textLength, chunks.size(), truncated);
            } else {
                log.info("文件无可提取文本: fileNodeId={}", event.fileNodeId());
            }
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("textLength", textLength);
            result.put("chunkCount", chunks.size());
            if (truncated) {
                result.put("truncated", true);
                result.put("chunkSize", CHUNK_SIZE_CHARS);
                result.put("maxChunks", MAX_CHUNKS);
            }
            taskTracker.complete(tracked.taskId(), result);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("文本提取失败: fileNodeId={}", event.fileNodeId(), e);
            taskTracker.handleFailure(TASK_TYPE, QueueNames.TEXT_EXTRACTION_ROUTING_KEY, tracked.taskId(), event, e);
            channel.basicAck(deliveryTag, false);
        }
    }

    /**
     * 将 Tika 抽出的正文流式切块，避免把千万字全文同时堆进单个字符串或单条 Lucene 文档。
     */
    static final class ChunkingTextCollector extends Writer {
        private final int chunkSizeChars;
        private final int maxChunks;
        private final List<String> chunks = new ArrayList<>();
        private final StringBuilder buffer;
        private int textLength;
        private boolean truncated;

        ChunkingTextCollector(int chunkSizeChars, int maxChunks) {
            this.chunkSizeChars = chunkSizeChars;
            this.maxChunks = maxChunks;
            this.buffer = new StringBuilder(Math.min(chunkSizeChars, 8192));
        }

        @Override
        public void write(char[] cbuf, int off, int len) {
            if (truncated || len <= 0) {
                return;
            }
            int remaining = len;
            int cursor = off;
            while (remaining > 0 && !truncated) {
                int space = chunkSizeChars - buffer.length();
                int take = Math.min(space, remaining);
                buffer.append(cbuf, cursor, take);
                cursor += take;
                remaining -= take;
                textLength += take;
                if (buffer.length() >= chunkSizeChars) {
                    flushBufferedChunk();
                }
            }
        }

        @Override
        public void flush() {
        }

        @Override
        public void close() {
            finish();
        }

        void finish() {
            if (!truncated && !buffer.isEmpty()) {
                chunks.add(buffer.toString());
                buffer.setLength(0);
            }
        }

        List<String> chunks() {
            return chunks;
        }

        int textLength() {
            return textLength;
        }

        boolean truncated() {
            return truncated;
        }

        private void flushBufferedChunk() {
            if (chunks.size() >= maxChunks) {
                truncated = true;
                buffer.setLength(0);
                log.warn("文本提取达到最大分块数，后续内容不再索引: maxChunks={}", maxChunks);
                return;
            }
            chunks.add(buffer.toString());
            buffer.setLength(0);
        }
    }
}
