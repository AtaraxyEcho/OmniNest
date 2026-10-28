package com.omninest.worker.index;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.SearchIndexRebuildEvent;
import com.omninest.modules.file.service.SearchIndexRebuildService;
import com.omninest.modules.photos.service.PhotoIndexTaskService;
import com.omninest.modules.task.service.TaskFailureRetryService;
import com.omninest.modules.task.service.TaskRecordService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 全站搜索索引重建消费者。
 *
 * <p>重建是索引卷的唯一「清空 + 全量派发」入口，必须留在单写进程内执行；
 * 管理员接口只投递任务，本消费者负责认领、推进进度与落终态。</p>
 *
 * <p>文件索引与照片索引是两个独立根目录，跨这两个模块的编排只能落在 Worker 侧：
 * File 模块不依赖 Media 模块，反向调用会打断 Maven 依赖方向。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class SearchIndexRebuildConsumer {

    private final TaskRecordService taskRecordService;
    private final TaskFailureRetryService taskFailureRetryService;
    private final SearchIndexRebuildService rebuildService;
    private final PhotoIndexTaskService photoIndexTaskService;

    /**
     * 认领重建任务并执行索引清空与重新派发。
     *
     * @param event 重建任务消息
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(
            queues = QueueNames.SEARCH_INDEX_REBUILD_QUEUE,
            concurrency = "${omninest.worker.file-index-concurrency:1}"
    )
    public void handle(SearchIndexRebuildEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            if (!taskRecordService.claimForExecution(event.taskId(), "REBUILDING")) {
                log.info("索引重建任务已被其他执行者领取或到达终态，跳过: taskId={}", event.taskId());
                channel.basicAck(deliveryTag, false);
                return;
            }
            Map<String, Object> result = new LinkedHashMap<>(rebuildService.rebuild(event.taskId()));
            result.put("reindexedPhotos", photoIndexTaskService.rebuildAll());
            taskRecordService.markCompleted(event.taskId(), result);
            channel.basicAck(deliveryTag, false);
        } catch (Throwable executionException) {
            log.error("索引重建任务失败: taskId={}, errorType={}",
                    event.taskId(), executionException.getClass().getSimpleName(), executionException);
            try {
                taskFailureRetryService.handleFailure(
                        event.taskId(), QueueNames.SEARCH_INDEX_REBUILD_ROUTING_KEY, event, executionException);
                channel.basicAck(deliveryTag, false);
            } catch (RuntimeException stateException) {
                log.error("索引重建失败状态写入失败，转入死信队列: taskId={}, errorType={}",
                        event.taskId(), stateException.getClass().getSimpleName(), stateException);
                channel.basicNack(deliveryTag, false, false);
            }
        }
    }
}
