package com.omninest.worker.index;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileIndexSyncEvent;
import com.omninest.modules.file.service.FileIndexSyncService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 文件搜索索引同步消费者。
 *
 * <p>与 {@code FileIndexConsumer}、{@code TextExtractionConsumer} 同处 Worker 进程，
 * 是 Lucene 索引卷的唯一写侧；请求进程只能通过 Outbox 投递本队列消息。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class FileIndexSyncConsumer {

    private final FileIndexSyncService fileIndexSyncService;

    /**
     * 按节点当前状态同步索引并确认消费结果。
     *
     * @param event 索引同步事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(
            queues = QueueNames.FILE_INDEX_SYNC_QUEUE,
            concurrency = "${omninest.worker.file-index-concurrency:1}"
    )
    public void handle(FileIndexSyncEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            int handled = fileIndexSyncService.sync(event.ownerUserId(), event.fileNodeIds());
            log.info("文件索引同步完成: ownerUserId={}, 请求节点数={}, 实际处理={}",
                    event.ownerUserId(), event.fileNodeIds().size(), handled);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("文件索引同步失败: ownerUserId={}, nodeCount={}",
                    event.ownerUserId(), event.fileNodeIds().size(), e);
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
