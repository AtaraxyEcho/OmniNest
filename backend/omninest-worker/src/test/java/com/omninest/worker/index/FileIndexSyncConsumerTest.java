package com.omninest.worker.index;

import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.event.FileIndexSyncEvent;
import com.omninest.modules.file.service.FileIndexSyncService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

/**
 * 文件索引同步消费者的编排测试。
 *
 * <p>本队列没有任务行可补跑，瞬时失败必须在消费者内重试后确认，否则一次索引锁竞争
 * 就会让节点永久缺索引；只有重试耗尽才进死信。</p>
 *
 * @author OmniNest
 */
class FileIndexSyncConsumerTest {

    private final FileIndexSyncService syncService = Mockito.mock(FileIndexSyncService.class);
    private final Channel channel = Mockito.mock(Channel.class);
    private final FileIndexSyncConsumer consumer = new FileIndexSyncConsumer(syncService);

    @Test
    @DisplayName("瞬时失败重试成功后确认，不把消息丢进死信")
    void handleRetriesTransientFailureThenAcknowledges() throws IOException {
        FileIndexSyncEvent event = event();
        when(syncService.sync(event.ownerUserId(), event.fileNodeIds()))
                .thenThrow(new IllegalStateException("index lock"))
                .thenReturn(1);

        consumer.handle(event, message(), channel);

        verify(syncService, times(2)).sync(event.ownerUserId(), event.fileNodeIds());
        verify(channel).basicAck(1L, false);
        verify(channel, never()).basicNack(Mockito.anyLong(), Mockito.anyBoolean(), Mockito.anyBoolean());
    }

    @Test
    @DisplayName("重试耗尽仍失败时进入死信，不静默确认")
    void handleDeadLettersWhenRetriesAreExhausted() throws IOException {
        FileIndexSyncEvent event = event();
        when(syncService.sync(event.ownerUserId(), event.fileNodeIds()))
                .thenThrow(new IllegalStateException("index unavailable"));

        consumer.handle(event, message(), channel);

        verify(syncService, times(3)).sync(event.ownerUserId(), event.fileNodeIds());
        verify(channel).basicNack(1L, false, false);
        verify(channel, never()).basicAck(Mockito.anyLong(), Mockito.anyBoolean());
    }

    private FileIndexSyncEvent event() {
        return new FileIndexSyncEvent(UUID.randomUUID(), List.of(UUID.randomUUID()));
    }

    private Message message() {
        MessageProperties properties = new MessageProperties();
        properties.setDeliveryTag(1L);
        return new Message(new byte[0], properties);
    }
}
