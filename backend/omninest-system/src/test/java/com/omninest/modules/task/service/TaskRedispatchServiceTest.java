package com.omninest.modules.task.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.domain.TaskRecord;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 任务重投服务测试：验证按路由键重建载荷与 Outbox 重投的统一入口。
 *
 * @author OmniNest
 */
class TaskRedispatchServiceTest {

    private static final UUID TASK_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");

    private final TaskDispatchService taskDispatchService = Mockito.mock(TaskDispatchService.class);
    private final TaskRedispatchService redispatchService =
            new TaskRedispatchService(taskDispatchService);

    @Test
    void redispatchRecordRebuildsPayloadAndEnqueuesToTaskExchange() {
        TaskRecord record = record(QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY,
                "{\"taskId\":\"" + TASK_ID + "\"}");

        redispatchService.redispatch(record);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(taskDispatchService).enqueue(
                eq(TASK_ID),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY),
                payloadCaptor.capture()
        );
        assertThat(payloadCaptor.getValue()).containsEntry("taskId", TASK_ID.toString());
    }

    @Test
    void rebuildsMediaScrapeEventPayloadFromStoredFields() {
        String payloadJson = """
                {
                  "ownerUserId": "10000000-0000-0000-0000-000000000001",
                  "fileNodeId": "30000000-0000-0000-0000-000000000001",
                  "title": "Inception",
                  "year": 2010,
                  "seasonNumber": null,
                  "episodeNumber": null,
                  "force": true
                }
                """;

        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, "MEDIA_SCRAPE", QueueNames.MEDIA_SCRAPE_ROUTING_KEY, payloadJson);

        assertThat(payload)
                .containsEntry("taskId", TASK_ID.toString())
                .containsEntry("ownerUserId", "10000000-0000-0000-0000-000000000001")
                .containsEntry("fileNodeId", "30000000-0000-0000-0000-000000000001")
                .containsEntry("title", "Inception")
                .containsEntry("year", 2010)
                .containsEntry("force", true);
    }

    @Test
    void rejectsUnknownRoutingKeyInsteadOfDispatchingWrongShape() {
        TaskRecord record = record("photo.geo.import", "{\"jobId\":\"x\"}");

        assertThatThrownBy(() -> redispatchService.redispatch(record))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("任务类型不支持自动重新投递");
        Mockito.verifyNoInteractions(taskDispatchService);
    }

    @Test
    void rejectsMissingRoutingKey() {
        TaskRecord record = record(null, "{}");

        assertThatThrownBy(() -> redispatchService.redispatch(record))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("任务缺少路由键");
        Mockito.verifyNoInteractions(taskDispatchService);
    }

    @Test
    void rejectsInvalidPayloadJson() {
        TaskRecord record = record(QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY, "not-json");

        assertThatThrownBy(() -> redispatchService.rebuildPayload(
                TASK_ID, "OFFLINE_DOWNLOAD", QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY, record.getPayload()))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("任务载荷不是合法 JSON");
    }

    @Test
    void rebuildRejectsPayloadMissingRequiredField() {
        assertThatThrownBy(() -> redispatchService.rebuildPayload(
                TASK_ID, "MUSIC_SCRAPE", QueueNames.MUSIC_SCRAPE_ROUTING_KEY, "{}"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("任务缺少可重试载荷字段");
        Mockito.verifyNoInteractions(taskDispatchService);
    }

    private TaskRecord record(String routingKey, String payload) {
        TaskRecord record = new TaskRecord();
        record.setId(TASK_ID);
        record.setTaskType("MEDIA_SCRAPE");
        record.setStatus("DLQ");
        record.setRoutingKey(routingKey);
        record.setPayload(payload);
        return record;
    }
}
