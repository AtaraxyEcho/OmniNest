package com.omninest.worker.index;

import com.omninest.modules.file.event.SearchIndexRebuildEvent;
import com.omninest.modules.file.service.SearchIndexRebuildService;
import com.omninest.modules.photos.service.PhotoIndexTaskService;
import com.omninest.modules.task.service.TaskRecordService;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.util.Map;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.mockito.Mockito;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

/**
 * 全站搜索索引重建消费者编排测试。
 *
 * @author OmniNest
 */
class SearchIndexRebuildConsumerTest {

    private final TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
    private final SearchIndexRebuildService rebuildService = Mockito.mock(SearchIndexRebuildService.class);
    private final PhotoIndexTaskService photoIndexTaskService = Mockito.mock(PhotoIndexTaskService.class);
    private final Channel channel = Mockito.mock(Channel.class);
    private final SearchIndexRebuildConsumer consumer = new SearchIndexRebuildConsumer(
            taskRecordService,
            rebuildService,
            photoIndexTaskService
    );

    @Test
    void handleRebuildsFileIndexThenPhotoIndexAndReportsBoth() throws IOException {
        UUID taskId = UUID.randomUUID();
        SearchIndexRebuildEvent event = new SearchIndexRebuildEvent(taskId, UUID.randomUUID());
        Mockito.when(taskRecordService.claimForExecution(taskId, "REBUILDING")).thenReturn(true);
        Mockito.when(rebuildService.rebuild(taskId)).thenReturn(Map.of("dispatchedFiles", 12L));
        Mockito.when(photoIndexTaskService.rebuildAll()).thenReturn(7);

        consumer.handle(event, message(), channel);

        InOrder order = Mockito.inOrder(rebuildService, photoIndexTaskService, taskRecordService, channel);
        order.verify(rebuildService).rebuild(taskId);
        order.verify(photoIndexTaskService).rebuildAll();
        ArgumentCaptor<Map<String, Object>> result = ArgumentCaptor.captor();
        order.verify(taskRecordService).markCompleted(Mockito.eq(taskId), result.capture());
        order.verify(channel).basicAck(1L, false);
        // 文件索引与照片索引是两个独立根目录，任务结果必须同时暴露两侧计数，
        // 否则管理员只能看到「重建成功」而无法判断相册侧是否真的重投过。
        Assertions.assertThat(result.getValue())
                .containsEntry("dispatchedFiles", 12L)
                .containsEntry("reindexedPhotos", 7);
    }

    @Test
    void handleSkipsBothIndexesWhenClaimLost() throws IOException {
        UUID taskId = UUID.randomUUID();
        SearchIndexRebuildEvent event = new SearchIndexRebuildEvent(taskId, UUID.randomUUID());
        Mockito.when(taskRecordService.claimForExecution(taskId, "REBUILDING")).thenReturn(false);

        consumer.handle(event, message(), channel);

        Mockito.verify(channel).basicAck(1L, false);
        Mockito.verifyNoInteractions(rebuildService, photoIndexTaskService);
        Mockito.verify(taskRecordService, Mockito.never()).markCompleted(Mockito.eq(taskId), Mockito.any());
    }

    @Test
    void handleFailsTaskWhenPhotoIndexRebuildThrows() throws IOException {
        UUID taskId = UUID.randomUUID();
        SearchIndexRebuildEvent event = new SearchIndexRebuildEvent(taskId, UUID.randomUUID());
        Mockito.when(taskRecordService.claimForExecution(taskId, "REBUILDING")).thenReturn(true);
        Mockito.when(rebuildService.rebuild(taskId)).thenReturn(Map.of("dispatchedFiles", 3L));
        Mockito.when(photoIndexTaskService.rebuildAll())
                .thenThrow(new IllegalStateException("清空照片索引失败"));

        consumer.handle(event, message(), channel);

        Mockito.verify(taskRecordService).markFailed(taskId, "清空照片索引失败");
        Mockito.verify(channel).basicAck(1L, false);
        Mockito.verify(taskRecordService, Mockito.never()).markCompleted(Mockito.eq(taskId), Mockito.any());
    }

    private Message message() {
        MessageProperties properties = new MessageProperties();
        properties.setDeliveryTag(1L);
        return new Message(new byte[0], properties);
    }
}
