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
import com.omninest.modules.notification.service.NotificationEmailService;
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
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000009");

    private final TaskDispatchService taskDispatchService = Mockito.mock(TaskDispatchService.class);
    private final TaskDispatchRepository taskDispatchRepository =
            Mockito.mock(TaskDispatchRepository.class);
    private final TaskRedispatchService redispatchService =
            new TaskRedispatchService(taskDispatchService, taskDispatchRepository);

    @Test
    void redispatchRecordRebuildsPayloadAndEnqueuesToTaskExchange() {
        TaskRecord record = record(QueueNames.EXTERNAL_IMPORT_ROUTING_KEY,
                "{\"importTaskId\":\"60000000-0000-0000-0000-000000000001\"}");

        redispatchService.redispatch(record);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(taskDispatchService).enqueue(
                eq(TASK_ID),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.EXTERNAL_IMPORT_ROUTING_KEY),
                payloadCaptor.capture()
        );
        assertThat(payloadCaptor.getValue())
                .containsEntry("taskId", "60000000-0000-0000-0000-000000000001");
    }

    @Test
    void rebuildsComicParsePayloadWithFileOwnerAndEmptyHash() {
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK_ID))
                .thenReturn(Optional.empty());
        String payloadJson = """
                {
                  "ownerUserId": "10000000-0000-0000-0000-000000000001",
                  "fileOwnerId": "10000000-0000-0000-0000-000000000002",
                  "itemId": "20000000-0000-0000-0000-000000000001",
                  "sourceId": "60000000-0000-0000-0000-000000000001",
                  "fileNodeId": "30000000-0000-0000-0000-000000000001",
                  "fileFormat": "EPUB",
                  "contentHash": ""
                }
                """;

        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, null, "COMIC_PARSE", QueueNames.COMIC_PARSE_ROUTING_KEY, payloadJson);

        assertThat(payload)
                .containsEntry("ownerUserId", "10000000-0000-0000-0000-000000000002")
                .containsEntry("contentHash", "")
                .containsEntry("isRetry", true);
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
                TASK_ID, null, "MEDIA_SCRAPE", QueueNames.MEDIA_SCRAPE_ROUTING_KEY, payloadJson);

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
        TaskRecord record = record(QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY, "not-json");

        assertThatThrownBy(() -> redispatchService.rebuildPayload(
                TASK_ID, null, "PHOTO_THUMBNAILS", QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY, record.getPayload()))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("任务载荷不是合法 JSON");
    }

    @Test
    void rebuildRejectsPayloadMissingRequiredField() {
        assertThatThrownBy(() -> redispatchService.rebuildPayload(
                TASK_ID, null, "MUSIC_SCRAPE", QueueNames.MUSIC_SCRAPE_ROUTING_KEY, "{}"))
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
                TASK_ID, null, "PHOTO_THUMBNAILS", QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY,
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
                TASK_ID, null, "PHOTO_GEO_IMPORT", QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY,
                "{\"datasetId\":\"60000000-0000-0000-0000-000000000001\","
                        + "\"datasetVersion\":\"v1\",\"dumpDate\":\"2026-01-01\"}");

        assertThat(payload)
                .containsEntry("taskId", TASK_ID.toString())
                .containsEntry("datasetId", "60000000-0000-0000-0000-000000000001")
                .containsEntry("datasetVersion", "v1")
                .containsEntry("dumpDate", "2026-01-01");
    }

    /** 库级分析没有 photoId，mode 丢失会让任务退化成单张分析并在消费端立即失败。 */
    @Test
    void rebuildsPhotoAiLibraryModeWithoutInventingPhotoId() {
        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, OWNER_ID, "AI_ANALYSIS", QueueNames.PHOTO_AI_ROUTING_KEY,
                "{\"ownerUserId\":\"10000000-0000-0000-0000-000000000001\","
                        + "\"mode\":\"LIBRARY_REANALYSIS\",\"totalItems\":120}");

        assertThat(payload)
                .containsEntry("taskId", TASK_ID.toString())
                .containsEntry("ownerUserId", "10000000-0000-0000-0000-000000000001")
                .containsEntry("mode", "LIBRARY_REANALYSIS")
                .containsEntry("photoId", null);
    }

    @Test
    void rebuildsPhotoGeoBackfillPayloadWithoutDispatch() {
        when(taskDispatchRepository.findFirstByTaskIdOrderByCreatedAtDesc(TASK_ID))
                .thenReturn(Optional.empty());

        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, null, "PHOTO_GEO_BACKFILL", QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY,
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
                TASK_ID, null, "PHOTO_GEO_BACKFILL", QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY, "{}"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("batchSize");
    }

    @Test
    void rebuildsFileSecurityScanPayloadWithOwnerFallbackAndBlankOptionalFields() {
        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, OWNER_ID, "FILE_SECURITY_SCAN", QueueNames.FILE_SECURITY_SCAN_ROUTING_KEY,
                "{\"ingressItemId\":\"70000000-0000-0000-0000-000000000001\","
                        + "\"asVersionOfFileId\":\"\",\"declaredSha256\":\"\"}");

        assertThat(payload)
                .containsEntry("taskId", TASK_ID.toString())
                .containsEntry("ownerUserId", OWNER_ID.toString())
                .containsEntry("ingressItemId", "70000000-0000-0000-0000-000000000001")
                // 空串在事件里就是"不是版本上传/未声明摘要"，不能保留成字符串。
                .containsEntry("asVersionOfFileId", null)
                .containsEntry("declaredSha256", null);
    }

    @Test
    void rebuildsBackdropSecurityScanPayloadFromOwnerFallback() {
        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, OWNER_ID, "BACKDROP_SECURITY_SCAN", QueueNames.BACKDROP_SECURITY_SCAN_ROUTING_KEY,
                "{\"assetId\":\"80000000-0000-0000-0000-000000000001\","
                        + "\"ingressItemId\":\"70000000-0000-0000-0000-000000000001\","
                        + "\"originalFileName\":\"wall.png\"}");

        assertThat(payload)
                .containsEntry("ownerUserId", OWNER_ID.toString())
                .containsEntry("assetId", "80000000-0000-0000-0000-000000000001")
                .containsEntry("originalFileName", "wall.png");
    }

    @Test
    void rebuildsNotificationEmailPayload() {
        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, OWNER_ID, NotificationEmailService.TASK_TYPE,
                QueueNames.NOTIFICATION_EMAIL_ROUTING_KEY,
                "{\"notificationId\":\"90000000-0000-0000-0000-000000000001\"}");

        assertThat(payload)
                .containsEntry("taskId", TASK_ID.toString())
                .containsEntry("ownerUserId", OWNER_ID.toString())
                .containsEntry("notificationId", "90000000-0000-0000-0000-000000000001");
    }

    @Test
    void rebuildsFilePurgePayload() {
        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, OWNER_ID, "FILE_PURGE", QueueNames.FILE_PURGE_ROUTING_KEY,
                "{\"taskId\":\"" + TASK_ID + "\","
                        + "\"ownerUserId\":\"10000000-0000-0000-0000-000000000001\","
                        + "\"rootFileNodeId\":\"30000000-0000-0000-0000-000000000001\","
                        + "\"cascade\":true}");

        assertThat(payload)
                .containsEntry("ownerUserId", "10000000-0000-0000-0000-000000000001")
                .containsEntry("rootFileNodeId", "30000000-0000-0000-0000-000000000001")
                .doesNotContainKey("cascade");
    }

    @Test
    void rebuildsMediaScanPayloadWithBlankRootFolderAsNull() {
        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, OWNER_ID, "MEDIA_SCAN", QueueNames.MEDIA_SCAN_ROUTING_KEY,
                "{\"rootFolderId\":\"\",\"incremental\":true}");

        assertThat(payload)
                .containsEntry("taskId", TASK_ID.toString())
                .containsEntry("ownerUserId", OWNER_ID.toString())
                .containsEntry("rootFolderId", null)
                .containsEntry("incremental", true);
    }

    @Test
    void rebuildsReaderParsePayloadPreferringFileOwner() {
        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, OWNER_ID, "READER_PARSE", QueueNames.READER_PARSE_ROUTING_KEY,
                "{\"ownerUserId\":\"10000000-0000-0000-0000-000000000001\","
                        + "\"fileOwnerId\":\"90000000-0000-0000-0000-000000000001\","
                        + "\"itemId\":\"20000000-0000-0000-0000-000000000001\","
                        + "\"fileNodeId\":\"30000000-0000-0000-0000-000000000001\","
                        + "\"fileFormat\":\"TXT\",\"contentHash\":\"abc\"}");

        assertThat(payload)
                .containsEntry("ownerUserId", "90000000-0000-0000-0000-000000000001")
                .containsEntry("itemId", "20000000-0000-0000-0000-000000000001")
                .containsEntry("fileFormat", "TXT")
                .containsEntry("isRetry", true);
    }

    @Test
    void rebuildsPhotoMotionExtractPayloadAsFileUploadedEvent() {
        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, OWNER_ID, "PHOTO_MOTION", QueueNames.PHOTO_MOTION_ROUTING_KEY,
                "{\"fileNodeId\":\"30000000-0000-0000-0000-000000000001\","
                        + "\"fileObjectId\":\"40000000-0000-0000-0000-000000000001\","
                        + "\"ownerUserId\":\"10000000-0000-0000-0000-000000000001\","
                        + "\"bucket\":\"user-files\",\"objectKey\":\"2024/01/a.jpg\","
                        + "\"fileName\":\"a.jpg\",\"mimeType\":\"image/jpeg\",\"sizeBytes\":1024}");

        assertThat(payload)
                .containsEntry("bucket", "user-files")
                .containsEntry("objectKey", "2024/01/a.jpg");
    }

    @Test
    @SuppressWarnings("unchecked")
    void rebuildsAutoImportAsNestedFileEvent() {
        // 投递行已过保留期时只能从记录载荷重建；自动导入的事件形状是 {taskId, file:{...}}。
        Map<String, Object> payload = redispatchService.rebuildPayload(
                TASK_ID, OWNER_ID, "MEDIA_AUTO_IMPORT", QueueNames.MEDIA_AUTO_IMPORT_ROUTING_KEY,
                "{\"fileNodeId\":\"30000000-0000-0000-0000-000000000001\","
                        + "\"fileObjectId\":\"40000000-0000-0000-0000-000000000001\","
                        + "\"ownerUserId\":\"10000000-0000-0000-0000-000000000001\","
                        + "\"bucket\":\"user-files\",\"objectKey\":\"2024/01/a.jpg\","
                        + "\"fileName\":\"a.jpg\",\"mimeType\":\"image/jpeg\",\"sizeBytes\":1024,"
                        + "\"occurredAt\":\"2026-06-01T10:00:00Z\"}");

        assertThat(payload).containsEntry("taskId", TASK_ID.toString());
        Map<String, Object> file = (Map<String, Object>) payload.get("file");
        assertThat(file)
                .containsEntry("bucket", "user-files")
                .containsEntry("objectKey", "2024/01/a.jpg")
                .containsEntry("ownerUserId", "10000000-0000-0000-0000-000000000001");
    }

    /** 恢复索引事件不落任务记录，重建分支必须拒绝而不是投一个错误形状。 */
    @Test
    void rejectsRestoreIndexRebuildBecauseNoTaskRecordExists() {
        assertThatThrownBy(() -> redispatchService.rebuildPayload(
                TASK_ID, OWNER_ID, "FILE_RESTORE_INDEX", QueueNames.FILE_RESTORE_INDEX_ROUTING_KEY, "{}"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不支持自动重新投递");
    }

    private TaskRecord record(String routingKey, String payload) {
        TaskRecord record = new TaskRecord();
        record.setId(TASK_ID);
        record.setTaskType("MEDIA_SCRAPE");
        record.setStatus("DLQ");
        record.setRoutingKey(routingKey);
        record.setOwnerUserId(OWNER_ID);
        record.setPayload(payload);
        return record;
    }
}
