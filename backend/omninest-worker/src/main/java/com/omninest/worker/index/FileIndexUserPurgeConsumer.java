package com.omninest.worker.index;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.search.event.FileIndexUserPurgeEvent;
import com.omninest.modules.search.service.SearchIndexUserPurgeService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.concurrent.TimeUnit;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 用户搜索索引目录清理消费者。
 *
 * <p>Worker 是 Lucene 索引卷的唯一写侧，物理删除必须在本地关闭该用户的
 * {@code IndexWriter} 后执行，避免跨进程写锁冲突。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class FileIndexUserPurgeConsumer {

    /** 目录删除的短重试次数：杀软扫描、句柄释放延迟通常在一次退避内结束。 */
    private static final int MAX_DELETE_ATTEMPTS = 3;
    private static final long RETRY_BACKOFF_MILLIS = 200L;

    private final SearchIndexUserPurgeService searchIndexUserPurgeService;

    /**
     * 删除用户索引目录并确认消费结果。
     *
     * @param event 索引清理事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(
            queues = QueueNames.FILE_INDEX_USER_PURGE_QUEUE,
            concurrency = "${omninest.worker.file-index-concurrency:1}"
    )
    public void handle(FileIndexUserPurgeEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            boolean deleted = false;
            for (int attempt = 1; attempt <= MAX_DELETE_ATTEMPTS && !deleted; attempt++) {
                deleted = searchIndexUserPurgeService.purgePhysicalIndex(event.ownerUserId());
                if (!deleted && attempt < MAX_DELETE_ATTEMPTS) {
                    TimeUnit.MILLISECONDS.sleep(RETRY_BACKOFF_MILLIS * attempt);
                }
            }
            if (deleted) {
                log.info("用户搜索索引目录清理完成: userId={}", event.ownerUserId());
                channel.basicAck(deliveryTag, false);
                return;
            }
            log.error("用户搜索索引目录清理重试耗尽，转入死信: userId={}", event.ownerUserId());
            channel.basicNack(deliveryTag, false, false);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("用户搜索索引目录清理被中断: userId={}", event.ownerUserId());
            channel.basicNack(deliveryTag, false, false);
        } catch (Throwable e) {
            log.error("用户搜索索引目录清理失败: userId={}", event.ownerUserId(), e);
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
