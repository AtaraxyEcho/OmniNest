package com.omninest.worker.index;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.event.SearchIndexRebuildEvent;
import com.omninest.modules.file.service.SearchIndexRebuildService;
import com.omninest.modules.task.service.TaskFailureRetryService;
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
 * <p>相册检索已收敛到 PostgreSQL，重建只覆盖文件正文索引一个根目录。</p>
 *
 * @author OmniNest
 */
class SearchIndexRebuildConsumerTest {

    private final TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
    private final TaskFailureRetryService failureRetryService = Mockito.mock(TaskFailureRetryService.class);
    private final SearchIndexRebuildService rebuildService = Mockito.mock(SearchIndexRebuildService.class);
    private final Channel channel = Mockito.mock(Channel.class);
    private final SearchIndexRebuildConsumer consumer = new SearchIndexRebuildConsumer(
            taskRecordService,
            failureRetryService,
            rebuildService
    );

    @Test
    void handleRebuildsFileIndexAndReportsDispatchedCount() throws IOException {
        UUID taskId = UUID.randomUUID();
        SearchIndexRebuildEvent event = new SearchIndexRebuildEvent(taskId, UUID.randomUUID());
        Mockito.when(taskRecordService.claimForExecution(taskId, "REBUILDING")).thenReturn(true);
        Mockito.when(rebuildService.rebuild(taskId)).thenReturn(Map.of("dispatchedFiles", 12L));

        consumer.handle(event, message(), channel);

        InOrder order = Mockito.inOrder(rebuildService, taskRecordService, channel);
        order.verify(rebuildService).rebuild(taskId);
        ArgumentCaptor<Map<String, Object>> result = ArgumentCaptor.captor();
        order.verify(taskRecordService).markCompleted(Mockito.eq(taskId), result.capture());
        order.verify(channel).basicAck(1L, false);
        Assertions.assertThat(result.getValue()).containsEntry("dispatchedFiles", 12L);
    }

    @Test
    void handleSkipsRebuildWhenClaimLost() throws IOException {
        UUID taskId = UUID.randomUUID();
        SearchIndexRebuildEvent event = new SearchIndexRebuildEvent(taskId, UUID.randomUUID());
        Mockito.when(taskRecordService.claimForExecution(taskId, "REBUILDING")).thenReturn(false);

        consumer.handle(event, message(), channel);

        Mockito.verify(channel).basicAck(1L, false);
        Mockito.verifyNoInteractions(rebuildService);
        Mockito.verify(taskRecordService, Mockito.never()).markCompleted(Mockito.eq(taskId), Mockito.any());
    }

    @Test
    void handleFailsTaskWhenRebuildThrows() throws IOException {
        UUID taskId = UUID.randomUUID();
        SearchIndexRebuildEvent event = new SearchIndexRebuildEvent(taskId, UUID.randomUUID());
        Mockito.when(taskRecordService.claimForExecution(taskId, "REBUILDING")).thenReturn(true);
        IllegalStateException failure = new IllegalStateException("清空索引失败");
        Mockito.when(rebuildService.rebuild(taskId)).thenThrow(failure);

        consumer.handle(event, message(), channel);

        Mockito.verify(failureRetryService).handleFailure(
                Mockito.eq(taskId),
                Mockito.eq(QueueNames.SEARCH_INDEX_REBUILD_ROUTING_KEY),
                Mockito.eq(event),
                Mockito.eq(failure));
        Mockito.verify(channel).basicAck(1L, false);
        Mockito.verify(taskRecordService, Mockito.never()).markCompleted(Mockito.eq(taskId), Mockito.any());
    }

    private Message message() {
        MessageProperties properties = new MessageProperties();
        properties.setDeliveryTag(1L);
        return new Message(new byte[0], properties);
    }
}
