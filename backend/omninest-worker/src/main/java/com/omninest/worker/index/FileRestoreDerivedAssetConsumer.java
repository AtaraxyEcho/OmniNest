package com.omninest.worker.index;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import com.omninest.worker.support.TransientRetry;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.FileRestoredEvent;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

/**
 * 文件恢复后的派生资产消费者：校验源对象是否仍在，并补齐缺失的图片缩略图。
 *
 * <p>搜索索引不在这里重建。恢复写入侧已经通过 {@code FileIndexSyncService} 派发
 * {@code FILE_INDEX + TEXT_EXTRACTION} 重投，那是唯一能保住正文的一条路；本消费者此前附带
 * 的 {@code indexFile(content=null)} 对已抽过正文的文件会被"已有正文就跳过"那道闸吞掉，
 * 属于第二条更弱的索引路径，已撤下。</p>
 *
 * <p>队列与路由键沿用 {@code omni.task.file-restore-index}：改名会在已部署的 broker 上留下
 * 需要手工清理的旧队列，而这条链路的职责已由类名与 Javadoc 说明，不值得换来运维残留。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class FileRestoreDerivedAssetConsumer {
    private final FileRestoreDerivedAssetService derivedAssetService;

    /**
     * 处理文件恢复索引消息中的派生资产修复部分。
     *
     * @param event 文件恢复事件
     * @param message AMQP 消息
     * @param channel RabbitMQ 通道
     * @throws IOException ACK 或 NACK 失败时抛出
     */
    @RabbitListener(queues = QueueNames.FILE_RESTORE_INDEX_QUEUE)
    public void handle(FileRestoredEvent event, Message message, Channel channel) throws IOException {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            // 恢复索引队列没有任务行可补跑：先做几次短退避重试，失败才进死信。
            TransientRetry.call("恢复文件派生资产修复", () -> {
                derivedAssetService.validateAndRepair(event);
                return null;
            });
            channel.basicAck(deliveryTag, false);
        } catch (BusinessException exception) {
            if (ErrorCode.FILE_NOT_FOUND.equals(exception.errorCode())
                    || ErrorCode.FILE_LIFECYCLE_CONFLICT.equals(exception.errorCode())) {
                log.info("恢复文件已再次删除或正在永久删除，跳过派生资产修复: fileNodeId={}", event.fileNodeId());
                channel.basicAck(deliveryTag, false);
                return;
            }
            log.error("恢复文件派生资产修复业务处理失败: fileNodeId={}", event.fileNodeId(), exception);
            channel.basicNack(deliveryTag, false, false);
        } catch (Throwable exception) {
            log.error("恢复文件派生资产修复失败: fileNodeId={}", event.fileNodeId(), exception);
            channel.basicNack(deliveryTag, false, false);
        }
    }
}
