package com.omninest.worker.task;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.error.BusinessException;
import com.omninest.common.json.JsonSupport;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.backdrop.event.BackdropSecurityScanRequestedEvent;
import com.omninest.modules.file.event.ExternalImportRequestedEvent;
import com.omninest.modules.file.event.FilePurgeRequestedEvent;
import com.omninest.modules.file.event.FileSecurityScanRequestedEvent;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.event.MediaAutoImportRequestedEvent;
import com.omninest.modules.file.event.SearchIndexRebuildEvent;
import com.omninest.modules.music.event.MusicScanEvent;
import com.omninest.modules.music.event.MusicScrapeEvent;
import com.omninest.modules.photos.event.PhotoAiEvent;
import com.omninest.modules.photos.event.PhotoBatchEvent;
import com.omninest.modules.photos.event.PhotoGeoBackfillEvent;
import com.omninest.modules.photos.event.PhotoGeoImportEvent;
import com.omninest.modules.photos.event.PhotoIndexEvent;
import com.omninest.modules.photos.event.PhotoMotionRescanEvent;
import com.omninest.modules.photos.event.PhotoScanEvent;
import com.omninest.modules.photos.event.PhotoThumbnailRegenerationEvent;
import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.event.ReaderParseTaskEvent;
import com.omninest.modules.task.repository.TaskDispatchRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRedispatchService;
import com.omninest.modules.notification.event.NotificationEmailRequestedEvent;
import com.omninest.modules.video.event.LocalVideoLibraryApplyRequestedEvent;
import com.omninest.modules.video.event.LocalVideoLibraryScanRequestedEvent;
import com.omninest.modules.video.event.MediaLibraryScanRequestedEvent;
import com.omninest.modules.video.event.MediaScrapeRequestedEvent;
import com.omninest.modules.video.event.TranscodeRequestedEvent;
import java.lang.reflect.Field;
import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 任务重投载荷与消费端事件形状的契约测试。
 *
 * <p>重投走的是"记录载荷 → 消费事件"的手工重建，两端没有共同类型约束：漏掉一个字段、
 * 键名写错、或新增路由键时忘了加重建分支，都只在管理员点重试且投递行已过期时才暴露。
 * 本测试按 {@link QueueNames} 的全部路由键逐一核对重建结果的字段集合，
 * 并把重建结果反序列化回消费端事件，确认每个组件都拿到值。</p>
 *
 * @author OmniNest
 */
class TaskPayloadContractTest {

    private static final UUID TASK_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000009");

    private final TaskRedispatchService redispatchService = new TaskRedispatchService(
            Mockito.mock(TaskDispatchService.class),
            Mockito.mock(TaskDispatchRepository.class)
    );

    /**
     * 不落任务记录的路由键：恢复索引与索引同步事件由请求侧 Outbox 直投（与 PHOTO_INDEX 同口径，
     * 载荷就是节点 ID，无需进度与重试台账），死信路由键属于 {@code omni.dlx} 交换机。
     */
    private static final Set<String> ROUTING_KEYS_WITHOUT_TASK_RECORD = Set.of(
            QueueNames.FILE_RESTORE_INDEX_ROUTING_KEY,
            QueueNames.FILE_INDEX_SYNC_ROUTING_KEY,
            QueueNames.DEAD_LETTER_ROUTING_KEY
    );

    private static final List<Contract> CONTRACTS = List.of(
            new Contract(QueueNames.FILE_INDEX_ROUTING_KEY, FileUploadedEvent.class, null),
            new Contract(QueueNames.TEXT_EXTRACTION_ROUTING_KEY, FileUploadedEvent.class, null),
            new Contract(QueueNames.THUMBNAIL_ROUTING_KEY, FileUploadedEvent.class, null),
            new Contract(QueueNames.PHOTO_MOTION_ROUTING_KEY, FileUploadedEvent.class, null),
            // 自动导入的事件是嵌套形状，但记录载荷把文件字段平铺在顶层。
            new Contract(
                    QueueNames.MEDIA_AUTO_IMPORT_ROUTING_KEY,
                    MediaAutoImportRequestedEvent.class,
                    derivePayload(FileUploadedEvent.class)
            ),
            new Contract(QueueNames.MEDIA_SCAN_ROUTING_KEY, MediaLibraryScanRequestedEvent.class, null),
            new Contract(QueueNames.NOTIFICATION_EMAIL_ROUTING_KEY,
                    NotificationEmailRequestedEvent.class, null),
            // 解析事件的 ownerUserId 是文件归属者，记录载荷用 fileOwnerId 与书架归属者区分。
            new Contract(
                    QueueNames.READER_PARSE_ROUTING_KEY,
                    ReaderParseTaskEvent.class,
                    readerParseRecordPayload()
            ),
            new Contract(QueueNames.FILE_PURGE_ROUTING_KEY, FilePurgeRequestedEvent.class, null),
            new Contract(QueueNames.FILE_SECURITY_SCAN_ROUTING_KEY, FileSecurityScanRequestedEvent.class, null),
            new Contract(QueueNames.BACKDROP_SECURITY_SCAN_ROUTING_KEY, BackdropSecurityScanRequestedEvent.class, null),
            // 外链导入的记录载荷用 importTaskId 记录业务任务标识，事件组件名是 taskId。
            new Contract(
                    QueueNames.EXTERNAL_IMPORT_ROUTING_KEY,
                    ExternalImportRequestedEvent.class,
                    Map.of("importTaskId", sampleUuid("importTaskId"))
            ),
            new Contract(QueueNames.MUSIC_SCAN_ROUTING_KEY, MusicScanEvent.class, null),
            new Contract(QueueNames.MUSIC_SCRAPE_ROUTING_KEY, MusicScrapeEvent.class, null),
            new Contract(QueueNames.MEDIA_SCRAPE_ROUTING_KEY, MediaScrapeRequestedEvent.class, null),
            new Contract(QueueNames.VIDEO_TRANSCODE_ROUTING_KEY, TranscodeRequestedEvent.class, null),
            new Contract(
                    QueueNames.LOCAL_VIDEO_LIBRARY_SCAN_ROUTING_KEY,
                    LocalVideoLibraryScanRequestedEvent.class,
                    null
            ),
            new Contract(
                    QueueNames.LOCAL_VIDEO_LIBRARY_APPLY_ROUTING_KEY,
                    LocalVideoLibraryApplyRequestedEvent.class,
                    null
            ),
            new Contract(QueueNames.COMIC_PARSE_ROUTING_KEY, ComicParseTaskEvent.class, null),
            new Contract(QueueNames.PHOTO_SCAN_ROUTING_KEY, PhotoScanEvent.class, null),
            new Contract(QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY, PhotoThumbnailRegenerationEvent.class, null),
            new Contract(QueueNames.PHOTO_INDEX_ROUTING_KEY, PhotoIndexEvent.class, null),
            new Contract(QueueNames.SEARCH_INDEX_REBUILD_ROUTING_KEY, SearchIndexRebuildEvent.class, null),
            new Contract(QueueNames.PHOTO_BATCH_ROUTING_KEY, PhotoBatchEvent.class, null),
            new Contract(QueueNames.PHOTO_AI_ROUTING_KEY, PhotoAiEvent.class, null),
            new Contract(QueueNames.PHOTO_MOTION_RESCAN_ROUTING_KEY, PhotoMotionRescanEvent.class, null),
            new Contract(QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY, PhotoGeoImportEvent.class, null),
            new Contract(QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY, PhotoGeoBackfillEvent.class, null)
    );

    @Test
    void everyTaskRoutingKeyIsCoveredByContract() throws ReflectiveOperationException {
        Set<String> covered = new LinkedHashSet<>(ROUTING_KEYS_WITHOUT_TASK_RECORD);
        CONTRACTS.forEach(contract -> covered.add(contract.routingKey()));

        assertThat(declaredRoutingKeys()).isEqualTo(covered);
    }

    @Test
    void rebuiltPayloadMatchesConsumerEventShape() {
        for (Contract contract : CONTRACTS) {
            Map<String, Object> recordPayload =
                    contract.recordPayload() == null ? derivePayload(contract.eventType()) : contract.recordPayload();
            Map<String, Object> rebuilt = redispatchService.rebuildPayload(
                    TASK_ID, OWNER_ID, null, contract.routingKey(), JsonSupport.toJson(recordPayload));

            assertThat(rebuilt.keySet())
                    .as("路由键 %s 重建出的字段必须与 %s 的组件同名",
                            contract.routingKey(), contract.eventType().getSimpleName())
                    .containsExactlyInAnyOrderElementsOf(componentNames(contract.eventType()));
            assertThatPopulatedComponents(contract, rebuilt);
        }
    }

    @Test
    void routingKeysWithoutTaskRecordRejectRebuild() {
        for (String routingKey : ROUTING_KEYS_WITHOUT_TASK_RECORD) {
            assertThatThrownBy(() -> redispatchService.rebuildPayload(TASK_ID, OWNER_ID, null, routingKey, "{}"))
                    .as("路由键 %s 没有任务记录，不能凭猜测重建", routingKey)
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("不支持自动重新投递");
        }
    }

    @Test
    void contractListKeepsEveryRoutingKeyUnique() {
        List<String> routingKeys = CONTRACTS.stream().map(Contract::routingKey).toList();

        assertThat(routingKeys).doesNotHaveDuplicates();
        assertThat(routingKeys).doesNotContainAnyElementsOf(ROUTING_KEYS_WITHOUT_TASK_RECORD);
    }

    private Set<String> declaredRoutingKeys() throws ReflectiveOperationException {
        Set<String> routingKeys = new LinkedHashSet<>();
        for (Field field : QueueNames.class.getFields()) {
            if (field.getName().endsWith("_ROUTING_KEY") && field.getType() == String.class) {
                routingKeys.add((String) field.get(null));
            }
        }
        return routingKeys;
    }

    private void assertThatPopulatedComponents(Contract contract, Map<String, Object> rebuilt) {
        Class<?> eventType = contract.eventType();
        Object event = JsonSupport.fromJson(JsonSupport.toJson(rebuilt), eventType);
        List<String> unfilled = new ArrayList<>();
        for (RecordComponent component : eventType.getRecordComponents()) {
            if (readComponent(component, event) == null) {
                unfilled.add(component.getName());
            }
        }

        assertThat(unfilled)
                .as("路由键 %s 重建后仍有事件组件取不到值", contract.routingKey())
                .isEmpty();
    }

    private Object readComponent(RecordComponent component, Object event) {
        try {
            return component.getAccessor().invoke(event);
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException("无法读取事件组件: " + component.getName(), exception);
        }
    }

    private static List<String> componentNames(Class<?> eventType) {
        return Arrays.stream(eventType.getRecordComponents())
                .map(RecordComponent::getName)
                .toList();
    }

    private static Map<String, Object> derivePayload(Class<?> eventType) {
        Map<String, Object> payload = new LinkedHashMap<>();
        for (RecordComponent component : eventType.getRecordComponents()) {
            payload.put(component.getName(), sampleValue(component.getType(), component.getName()));
        }
        return payload;
    }

    private static Map<String, Object> readerParseRecordPayload() {
        Map<String, Object> payload = derivePayload(ReaderParseTaskEvent.class);
        payload.put("fileOwnerId", payload.remove("ownerUserId"));
        return payload;
    }

    private static Object sampleValue(Class<?> type, String name) {
        if (type == UUID.class) {
            return sampleUuid(name);
        }
        if (type == String.class) {
            return "sample-" + name;
        }
        if (type == long.class || type == Long.class) {
            return 1024L;
        }
        if (type == int.class || type == Integer.class) {
            return 7;
        }
        if (type == boolean.class || type == Boolean.class) {
            return true;
        }
        if (type == Instant.class) {
            return "2026-06-01T10:00:00Z";
        }
        if (type.isEnum()) {
            return type.getEnumConstants()[0].toString();
        }
        if (type.isRecord()) {
            return derivePayload(type);
        }
        throw new IllegalStateException("契约测试尚未支持的事件字段类型: " + type.getName());
    }

    private static String sampleUuid(String name) {
        return UUID.nameUUIDFromBytes(name.getBytes(StandardCharsets.UTF_8)).toString();
    }

    private record Contract(String routingKey, Class<?> eventType, Map<String, Object> recordPayload) {
    }
}
