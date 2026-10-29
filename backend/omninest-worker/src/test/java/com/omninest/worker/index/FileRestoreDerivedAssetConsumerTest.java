package com.omninest.worker.index;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.event.FileRestoredEvent;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

/**
 * 文件恢复派生资产消费者编排测试。
 *
 * @author OmniNest
 */
class FileRestoreDerivedAssetConsumerTest {

    private final FileRestoreDerivedAssetService derivedAssetService = Mockito.mock(
            FileRestoreDerivedAssetService.class
    );
    private final Channel channel = Mockito.mock(Channel.class);
    private final FileRestoreDerivedAssetConsumer consumer =
            new FileRestoreDerivedAssetConsumer(derivedAssetService);

    @Test
    @DisplayName("修复派生资产后确认消息，不再触发第二条索引路径")
    void handleRepairsDerivedAssetsAndAcknowledges() throws IOException {
        FileRestoredEvent event = event();

        consumer.handle(event, message(), channel);

        Mockito.verify(derivedAssetService).validateAndRepair(event);
        Mockito.verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("瞬时失败重试成功后确认，不把恢复消息丢进死信")
    void handleRetriesTransientFailureThenAcknowledges() throws IOException {
        FileRestoredEvent event = event();
        Mockito.doThrow(new IllegalStateException("object storage busy"))
                .doNothing()
                .when(derivedAssetService)
                .validateAndRepair(event);

        consumer.handle(event, message(), channel);

        Mockito.verify(derivedAssetService, Mockito.times(2)).validateAndRepair(event);
        Mockito.verify(channel).basicAck(1L, false);
        Mockito.verify(channel, Mockito.never()).basicNack(Mockito.anyLong(), Mockito.anyBoolean(),
                Mockito.anyBoolean());
    }

    @Test
    @DisplayName("文件再次进入回收站或永久删除时跳过修复并确认")
    void handleAcknowledgesWhenFileEnteredPurgeAgain() throws IOException {
        FileRestoredEvent event = event();
        Mockito.doThrow(new BusinessException(ErrorCode.FILE_LIFECYCLE_CONFLICT, "文件正在永久删除"))
                .when(derivedAssetService)
                .validateAndRepair(event);

        consumer.handle(event, message(), channel);

        Mockito.verify(channel).basicAck(1L, false);
        Mockito.verify(channel, Mockito.never()).basicNack(Mockito.anyLong(), Mockito.anyBoolean(),
                Mockito.anyBoolean());
    }

    @Test
    @DisplayName("源对象缺失时进死信，不静默确认")
    void handleDeadLettersMissingPhysicalObject() throws IOException {
        FileRestoredEvent event = event();
        Mockito.doThrow(new BusinessException(ErrorCode.FILE_OBJECT_MISSING, "文件对象缺失"))
                .when(derivedAssetService)
                .validateAndRepair(event);

        consumer.handle(event, message(), channel);

        Mockito.verify(channel).basicNack(1L, false, false);
        Mockito.verify(channel, Mockito.never()).basicAck(Mockito.anyLong(), Mockito.anyBoolean());
    }

    private FileRestoredEvent event() {
        return new FileRestoredEvent(UUID.randomUUID(), UUID.randomUUID(), "photo.jpg", Instant.now());
    }

    private Message message() {
        MessageProperties properties = new MessageProperties();
        properties.setDeliveryTag(1L);
        return new Message(new byte[0], properties);
    }
}
