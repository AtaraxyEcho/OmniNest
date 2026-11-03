package com.omninest.worker.photos;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.event.PhotoIndexUserPurgeEvent;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.omninest.worker.support.TransientRetry;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 用户照片索引清理消费者。
 *
 * <p>Worker 是照片共享 Lucene 卷的唯一写侧，删除必须在持有 {@code write.lock}
 * 的进程内执行；请求进程直接改卷会与 Worker 抢锁。用户已删除而索引文档残留时，
 * 其标题、位置与 OCR 正文仍可能被其他成员检索到，因此失败必须可见。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class PhotoIndexUserPurgeConsumer {

    private final PhotoSearchIndexService photoSearchIndexService;

    /**
     * 删除指定用户的照片索引文档并确认消费结果。
     *
     * @param event 索引清理事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.PHOTO_INDEX_USER_PURGE_QUEUE)
    public void handle(PhotoIndexUserPurgeEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            TransientRetry.call("删除用户照片索引", () -> {
                photoSearchIndexService.deleteByOwnerUserId(event.ownerUserId());
                return null;
            });
            channel.basicAck(deliveryTag, false);
        } catch (Throwable exception) {
            log.error("用户照片索引清理失败，转入死信: userId={}", event.ownerUserId(), exception);
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
