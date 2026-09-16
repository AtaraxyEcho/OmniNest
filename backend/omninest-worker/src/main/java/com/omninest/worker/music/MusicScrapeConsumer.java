package com.omninest.worker.music;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.music.event.MusicScrapeEvent;
import com.omninest.modules.music.service.MusicScrapeService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 音乐刮削异步消费者，从队列接收批量刮削任务并执行元数据匹配。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class MusicScrapeConsumer {

    private final MusicScrapeService musicScrapeService;
    private final MusicTaskRetryService retryService;

    /**
     * 处理音乐批量刮削任务。
     *
     * @param event 任务事件
     * @param message RabbitMQ 原始消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK/NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.MUSIC_SCRAPE_QUEUE)
    public void handle(MusicScrapeEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到音乐刮削任务: jobId={}, ownerUserId={}, force={}",
                    event.jobId(), event.ownerUserId(), event.force());
            musicScrapeService.executeScrapeLibrary(event.jobId(), event.ownerUserId(), event.force());
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("音乐刮削处理失败: jobId={}", event.jobId(), e);
            try {
                retryService.handleScrapeFailure(event, e);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException retryException) {
                log.error("音乐刮削失败状态写入失败，将重新投递原消息: taskId={}",
                        event.jobId(), retryException);
                channel.basicNack(deliveryTag, false, true);
            }
        }
    }
}
