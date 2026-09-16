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
import com.omninest.modules.task.domain.TaskDispatch;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.repository.TaskDispatchRepository;
import java.util.Map;
import java.util.Optional;
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
    private final TaskDispatchRepository taskDispatchRepository =
            Mockito.mock(TaskDispatchRepository.class);
    private final TaskRedispatchService redispatchService =
            new TaskRedispatchService(taskDispatchService, taskDispatchRepository);

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
        TaskRecord record = record("unknown.task.key", "{\"jobId\":\"x\"}");

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

    @Test
    void redispatchPrefersLatestDispatchPayloadOverRecordPayload() {
        TaskDispatch dispatch = new TaskDispatch();
        dispatch.setTaskId(TASK_ID);
        dispatch.setExchangeName("omni.task");
        dispatch.setRoutingKey(QueueNames.PHOTO_MOTION_ROUTING_KEY);
        // 文件后处理类记录载荷缺 bucket/objectKey，只有投递行携带完整事件。
        dispatch.setPayload("""
                {"fileNodeId":"30000000-0000-0000-0000-000000000001",
                 "fileObjectId":"40000000-0000-0000-0000-000000000001",
                 "ownerUserId":"10000000-0000-0000-0000-000000000001",
                 "bucket":"user-files","objectKey":"2024/01/a.jpg",
                 "fileName":"a.jpg","mimeType":"image/jpeg","sizeBytes":1024}
                """);
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK_ID))
                .thenReturn(Optional.of(dispatch));
        TaskRecord record = record(QueueNames.PHOTO_MOTION_ROUTING_KEY, "{\"fileNodeId\":\"x\"}");

        redispatchService.redispatch(record);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(taskDispatchService).enqueue(
                eq(TASK_ID),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.PHOTO_MOTION_ROUTING_KEY),
                payloadCaptor.capture()
        );
        assertThat(payloadCaptor.getValue()).containsEntry("bucket", "user-files");
    }

    @Test
    void rebuildsPhotoThumbnailsPayloadWithoutDispatch() {
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK_ID))
                .thenReturn(Optional.empty());

        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, "PHOTO_THUMBNAILS", QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY,
                "{\"ownerUserId\":\"10000000-0000-0000-0000-000000000001\"}");

        assertThat(payload)
                .containsEntry("taskId", TASK_ID.toString())
                .containsEntry("ownerUserId", "10000000-0000-0000-0000-000000000001");
    }

    @Test
    void rebuildsPhotoGeoImportPayloadWithoutDispatch() {
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK_ID))
                .thenReturn(Optional.empty());

        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, "PHOTO_GEO_IMPORT", QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY,
                "{\"datasetId\":\"60000000-0000-0000-0000-000000000001\","
                        + "\"datasetVersion\":\"v1\",\"dumpDate\":\"2026-01-01\"}");

        assertThat(payload)
                .containsEntry("datasetId", "60000000-0000-0000-0000-000000000001")
                .containsEntry("datasetVersion", "v1")
                .containsEntry("dumpDate", "2026-01-01");
    }

    @Test
    void rebuildsPhotoGeoBackfillPayloadWithoutDispatch() {
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK_ID))
                .thenReturn(Optional.empty());

        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, "PHOTO_GEO_BACKFILL", QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY,
                "{\"batchSize\":500}");

        assertThat(payload)
                .containsEntry("taskId", TASK_ID.toString())
                .containsEntry("batchSize", 500);
    }

    @Test
    void rejectsPhotoGeoBackfillPayloadMissingBatchSize() {
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> redispatchService.rebuildPayload(
                TASK_ID, "PHOTO_GEO_BACKFILL", QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY, "{}"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("batchSize");
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
