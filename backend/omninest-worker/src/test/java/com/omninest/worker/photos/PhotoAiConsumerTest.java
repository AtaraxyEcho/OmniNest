package com.omninest.worker.photos;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.photos.event.PhotoAiEvent;
import com.omninest.modules.photos.event.PhotoAiEvent.Mode;
import com.omninest.modules.photos.service.PhotoAiTaskService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

/**
 * 照片 AI 消费者消息确认测试。
 * 失败时交由重试服务裁决并确认消息；重试服务自身异常才重回队列。
 *
 * @author OmniNest
 */
class PhotoAiConsumerTest {

    private final PhotoAiTaskService taskService = Mockito.mock(PhotoAiTaskService.class);
    private final PhotoAiTaskRetryService retryService = Mockito.mock(PhotoAiTaskRetryService.class);
    private final Channel channel = Mockito.mock(Channel.class);
    private final PhotoAiConsumer consumer = new PhotoAiConsumer(taskService, retryService);

    @Test
    void handleAcknowledgesCompletedTask() throws IOException {
        PhotoAiEvent event = event();

        consumer.handle(event, message(), channel);

        Mockito.verify(taskService).execute(event);
        Mockito.verify(channel).basicAck(1L, false);
        Mockito.verify(channel, Mockito.never()).basicNack(Mockito.anyLong(), Mockito.anyBoolean(), Mockito.anyBoolean());
    }

    @Test
    void handleDelegatesFailureToRetryServiceAndAcknowledges() throws IOException {
        PhotoAiEvent event = event();
        Mockito.doThrow(new IllegalStateException("sidecar unavailable"))
                .when(taskService).execute(event);

        consumer.handle(event, message(), channel);

        Mockito.verify(retryService).handlePhotoAiFailure(
                Mockito.eq(event), Mockito.any(IllegalStateException.class));
        Mockito.verify(channel).basicAck(1L, false);
        Mockito.verify(channel, Mockito.never()).basicNack(Mockito.anyLong(), Mockito.anyBoolean(), Mockito.anyBoolean());
    }

    @Test
    void handleDelegatesDependencyNotReadyToRetryServiceAndAcknowledges() throws IOException {
        PhotoAiEvent event = event();
        Mockito.doThrow(new BusinessException(ErrorCode.TASK_DEPENDENCY_NOT_READY, "照片封面尚未生成，等待缩略图任务回填"))
                .when(taskService).execute(event);

        consumer.handle(event, message(), channel);

        Mockito.verify(retryService).handlePhotoAiFailure(
                Mockito.eq(event), Mockito.any(BusinessException.class));
        Mockito.verify(retryService).isDependencyNotReady(Mockito.any(BusinessException.class));
        Mockito.verify(channel).basicAck(1L, false);
        Mockito.verify(channel, Mockito.never()).basicNack(Mockito.anyLong(), Mockito.anyBoolean(), Mockito.anyBoolean());
    }

    @Test
    void handleRequeuesOriginalMessageWhenRetryStateWriteFails() throws IOException {
        PhotoAiEvent event = event();
        Mockito.doThrow(new IllegalStateException("sidecar unavailable"))
                .when(taskService).execute(event);
        Mockito.doThrow(new IllegalStateException("database down"))
                .when(retryService).handlePhotoAiFailure(Mockito.any(), Mockito.any());

        consumer.handle(event, message(), channel);

        Mockito.verify(channel).basicNack(1L, false, true);
        Mockito.verify(channel, Mockito.never()).basicAck(Mockito.anyLong(), Mockito.anyBoolean());
    }

    private PhotoAiEvent event() {
        return new PhotoAiEvent(
                UUID.randomUUID(),
                UUID.randomUUID(),
                UUID.randomUUID(),
                Mode.SINGLE_PHOTO
        );
    }

    private Message message() {
        MessageProperties properties = new MessageProperties();
        properties.setDeliveryTag(1L);
        return new Message(new byte[0], properties);
    }
}
