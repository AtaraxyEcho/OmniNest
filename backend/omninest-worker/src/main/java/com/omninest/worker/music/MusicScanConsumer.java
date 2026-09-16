package com.omninest.worker.music;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.music.event.MusicScanEvent;
import com.omninest.modules.music.service.MusicAdminService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 音乐扫描异步消费者，从队列接收扫描任务并执行导入。
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class MusicScanConsumer {

    private final MusicAdminService musicAdminService;
    private final MusicTaskRetryService retryService;

    @RabbitListener(queues = QueueNames.MUSIC_SCAN_QUEUE)
    public void handle(MusicScanEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            log.info("收到音乐扫描任务: jobId={}, ownerUserId={}", event.jobId(), event.ownerUserId());
            musicAdminService.executeScanJob(event.jobId(), event.ownerUserId());
            channel.basicAck(deliveryTag, false);
        } catch (Throwable e) {
            log.error("音乐扫描处理失败: jobId={}", event.jobId(), e);
            try {
                retryService.handleScanFailure(event, e);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException retryException) {
                log.error("音乐扫描失败状态写入失败，将重新投递原消息: taskId={}",
                        event.jobId(), retryException);
                channel.basicNack(deliveryTag, false, true);
            }
        }
    }
}
