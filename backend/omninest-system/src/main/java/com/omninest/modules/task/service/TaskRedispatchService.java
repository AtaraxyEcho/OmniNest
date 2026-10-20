package com.omninest.modules.task.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.json.JsonSupport;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.domain.TaskDispatch;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.repository.TaskDispatchRepository;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import tools.jackson.core.type.TypeReference;

/**
 * 任务重新投递服务：从任务记录重建消费方事件载荷并经 Outbox 重发。
 *
 * <p>供管理员重试、死信重试与停滞任务清扫三类入口共用，保证"存储载荷 →
 * 消费事件"的重建规则只有一份。优先复用最近一次 Outbox 投递的原始消息，
 * 无投递记录（历史数据或已过保留期）时按路由键从记录载荷重建；重建要求的字段
 * 与生产侧记录载荷同形。未收录的路由键拒绝重投，避免以错误形状的载荷打爆消费方。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class TaskRedispatchService {

    private static final TypeReference<Map<String, Object>> MAP_TYPE = new TypeReference<>() {
    };

    private final TaskDispatchService taskDispatchService;
    private final TaskDispatchRepository taskDispatchRepository;

    /**
     * 按任务记录重建载荷并立即经 Outbox 重新投递。
     *
     * @param record 待重投的任务记录
     */
    public void redispatch(TaskRecord record) {
        String routingKey = record.getRoutingKey();
        if (routingKey == null || routingKey.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "任务缺少路由键，无法重新投递");
        }
        TaskDispatch dispatch = taskDispatchRepository
                .findFirstByTaskIdOrderByCreatedAtDesc(record.getId())
                .orElse(null);
        if (dispatch != null && dispatch.getPayload() != null && !dispatch.getPayload().isBlank()) {
            taskDispatchService.enqueue(
                    record.getId(),
                    QueueNames.TASK_EXCHANGE,
                    dispatch.getRoutingKey(),
                    JsonSupport.fromJson(dispatch.getPayload(), Object.class)
            );
            return;
        }
        Map<String, Object> payload = rebuildPayload(
                record.getId(),
                record.getOwnerUserId(),
                record.getTaskType(),
                routingKey,
                record.getPayload()
        );
        enqueueRedispatch(record.getId(), routingKey, payload);
    }

    /**
     * 按路由键将任务载荷重建为消费方事件形状，并经 Outbox 立即投递。
     *
     * <p>文件恢复索引事件由领域事件直接投递、不落任务记录，因此只在存在投递行时可重投；
     * 落到重建路径时按"不支持"拒绝，避免以错误形状投递。</p>
     *
     * @param taskId 任务 ID
     * @param fallbackOwnerUserId 任务记录上的归属用户，供载荷未冗余 ownerUserId 的类型回退
     * @param taskType 任务类型（仅用于错误提示）
     * @param routingKey 任务路由键
     * @param payloadJson 任务记录中的载荷 JSON
     * @return 实际投递的载荷
     */
    public Map<String, Object> redispatch(
            UUID taskId,
            UUID fallbackOwnerUserId,
            String taskType,
            String routingKey,
            String payloadJson
    ) {
        Map<String, Object> payload = rebuildPayload(taskId, fallbackOwnerUserId, taskType, routingKey, payloadJson);
        enqueueRedispatch(taskId, routingKey, payload);
        return payload;
    }

    /**
     * 将载荷写入当前业务事务内的 Outbox，由调度器投递到任务交换机。
     *
     * @param taskId 任务 ID
     * @param routingKey 任务路由键
     * @param payload 已重建的载荷
     */
    public void enqueueRedispatch(UUID taskId, String routingKey, Map<String, Object> payload) {
        taskDispatchService.enqueue(taskId, QueueNames.TASK_EXCHANGE, routingKey, payload);
    }

    /**
     * 按路由键重建消费方事件载荷。
     *
     * @param taskId 任务 ID
     * @param fallbackOwnerUserId 任务行上的归属用户，仅用于载荷未冗余 ownerUserId 的类型
     * @param taskType 任务类型（仅用于错误提示）
     * @param routingKey 任务路由键
     * @param payloadJson 任务记录载荷 JSON
     * @return 消费方事件形状的载荷
     */
    public Map<String, Object> rebuildPayload(
            UUID taskId,
            UUID fallbackOwnerUserId,
            String taskType,
            String routingKey,
            String payloadJson
    ) {
        Map<String, Object> payload = parsePayload(payloadJson);
        return switch (routingKey) {
            case QueueNames.FILE_INDEX_ROUTING_KEY,
                    QueueNames.TEXT_EXTRACTION_ROUTING_KEY,
                    QueueNames.THUMBNAIL_ROUTING_KEY,
                    QueueNames.PHOTO_MOTION_ROUTING_KEY -> fileUploadedPayload(payload);
            case QueueNames.MEDIA_AUTO_IMPORT_ROUTING_KEY -> Map.of(
                    "taskId", taskId.toString(),
                    // 事件是嵌套形状：文件字段整体落在 file 之下（MediaAutoImportRequestedEvent）。
                    "file", fileUploadedPayload(payload)
            );
            case QueueNames.MEDIA_SCAN_ROUTING_KEY -> {
                Map<String, Object> scan = new LinkedHashMap<>();
                scan.put("taskId", taskId.toString());
                scan.put("ownerUserId", requireOwner(payload, fallbackOwnerUserId).toString());
                scan.put("rootFolderId", nullableUuid(payload.get("rootFolderId")));
                scan.put("incremental", booleanValue(payload.get("incremental")));
                yield scan;
            }
            case QueueNames.READER_PARSE_ROUTING_KEY -> readerParsePayload(taskId, payload);
            case QueueNames.FILE_PURGE_ROUTING_KEY -> Map.of(
                    "taskId", taskId.toString(),
                    "ownerUserId", requireOwner(payload, fallbackOwnerUserId).toString(),
                    "rootFileNodeId", requiredUuid(payload, "rootFileNodeId").toString()
            );
            case QueueNames.FILE_SECURITY_SCAN_ROUTING_KEY -> {
                Map<String, Object> scan = new LinkedHashMap<>();
                scan.put("taskId", taskId.toString());
                scan.put("ownerUserId", requireOwner(payload, fallbackOwnerUserId).toString());
                scan.put("ingressItemId", requiredUuid(payload, "ingressItemId").toString());
                // 空串在消费端等价于"不是版本上传"，必须还原成 null 而不是抛格式错误。
                scan.put("asVersionOfFileId", nullableUuid(payload.get("asVersionOfFileId")));
                scan.put("declaredSha256", nullableText(payload.get("declaredSha256")));
                yield scan;
            }
            case QueueNames.BACKDROP_SECURITY_SCAN_ROUTING_KEY -> Map.of(
                    "taskId", taskId.toString(),
                    "ownerUserId", requireOwner(payload, fallbackOwnerUserId).toString(),
                    "assetId", requiredUuid(payload, "assetId").toString(),
                    "ingressItemId", requiredUuid(payload, "ingressItemId").toString(),
                    "originalFileName", optionalText(payload, "originalFileName", "")
            );
            case QueueNames.EXTERNAL_IMPORT_ROUTING_KEY -> Map.of(
                    "taskId", requiredUuid(payload, "importTaskId").toString()
            );
            case QueueNames.MUSIC_SCAN_ROUTING_KEY,
                    QueueNames.PHOTO_SCAN_ROUTING_KEY -> Map.of(
                    "jobId", requiredUuid(payload, "jobId").toString(),
                    "ownerUserId", requiredUuid(payload, "ownerUserId").toString()
            );
            case QueueNames.MUSIC_SCRAPE_ROUTING_KEY -> Map.of(
                    "jobId", requiredUuid(payload, "jobId").toString(),
                    "ownerUserId", requiredUuid(payload, "ownerUserId").toString(),
                    "force", booleanValue(payload.get("force"))
            );
            case QueueNames.MEDIA_SCRAPE_ROUTING_KEY -> mediaScrapePayload(taskId, payload);
            case QueueNames.VIDEO_TRANSCODE_ROUTING_KEY -> transcodePayload(taskId, payload);
            case QueueNames.LOCAL_VIDEO_LIBRARY_SCAN_ROUTING_KEY,
                    QueueNames.LOCAL_VIDEO_LIBRARY_APPLY_ROUTING_KEY -> Map.of(
                    "taskId", taskId.toString(),
                    "ownerUserId", requiredUuid(payload, "ownerUserId").toString(),
                    "sourceId", requiredUuid(payload, "sourceId").toString(),
                    "scanRunId", requiredUuid(payload, "scanRunId").toString()
            );
            case QueueNames.COMIC_PARSE_ROUTING_KEY -> comicParsePayload(taskId, payload);
            case QueueNames.PHOTO_BATCH_ROUTING_KEY -> Map.of(
                    "taskId", taskId.toString(),
                    "ownerUserId", requiredUuid(payload, "ownerUserId").toString()
            );
            case QueueNames.PHOTO_INDEX_ROUTING_KEY -> Map.of(
                    "photoId", requiredUuid(payload, "photoId").toString(),
                    "ownerUserId", requiredUuid(payload, "ownerUserId").toString()
            );
            case QueueNames.PHOTO_AI_ROUTING_KEY -> {
                Map<String, Object> analysis = new LinkedHashMap<>();
                analysis.put("taskId", taskId.toString());
                analysis.put("ownerUserId", requireOwner(payload, fallbackOwnerUserId).toString());
                // 库级模式（重分析、重聚类）本就没有 photoId，事件里必须保持 null 而不是报错。
                analysis.put("photoId", nullableUuid(payload.get("photoId")));
                // 丢失 mode 会让库级任务退化成单张分析，消费端按 SINGLE_PHOTO 处理空 photoId 直接失败。
                analysis.put("mode", nullableText(payload.get("mode")));
                yield analysis;
            }
            case QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY,
                    QueueNames.PHOTO_MOTION_RESCAN_ROUTING_KEY -> Map.of(
                    "taskId", taskId.toString(),
                    "ownerUserId", requiredUuid(payload, "ownerUserId").toString()
            );
            case QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY -> Map.of(
                    // 记录载荷不冗余 taskId，消费端按 event.taskId() 定位任务行，必须从任务行补齐。
                    "taskId", taskId.toString(),
                    "datasetId", requiredUuid(payload, "datasetId").toString(),
                    "datasetVersion", requiredText(payload, "datasetVersion"),
                    "dumpDate", requiredText(payload, "dumpDate")
            );
            case QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY -> {
                Integer batchSize = optionalInteger(payload.get("batchSize"));
                if (batchSize == null) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR, "任务缺少可重试载荷字段: batchSize");
                }
                Map<String, Object> backfill = new LinkedHashMap<>();
                backfill.put("taskId", taskId.toString());
                backfill.put("batchSize", batchSize);
                backfill.put("datasetVersion", optionalText(payload, "datasetVersion", null));
                yield backfill;
            }
            default -> throw new BusinessException(
                    ErrorCode.PARAM_ERROR,
                    "任务类型不支持自动重新投递: " + (taskType == null ? routingKey : taskType)
            );
        };
    }

    private Map<String, Object> fileUploadedPayload(Map<String, Object> payload) {
        return Map.of(
                "fileNodeId", requiredUuid(payload, "fileNodeId").toString(),
                "fileObjectId", requiredUuid(payload, "fileObjectId").toString(),
                "ownerUserId", requiredUuid(payload, "ownerUserId").toString(),
                "bucket", requiredText(payload, "bucket"),
                "objectKey", requiredText(payload, "objectKey"),
                "fileName", requiredText(payload, "fileName"),
                "mimeType", requiredText(payload, "mimeType"),
                "sizeBytes", longValue(payload.get("sizeBytes")),
                "occurredAt", optionalText(payload, "occurredAt", Instant.now().toString())
        );
    }

    private Map<String, Object> mediaScrapePayload(UUID taskId, Map<String, Object> payload) {
        Map<String, Object> retryPayload = new LinkedHashMap<>();
        retryPayload.put("taskId", taskId.toString());
        retryPayload.put("ownerUserId", requiredUuid(payload, "ownerUserId").toString());
        retryPayload.put("fileNodeId", requiredUuid(payload, "fileNodeId").toString());
        retryPayload.put("title", optionalText(payload, "title", null));
        retryPayload.put("year", optionalInteger(payload.get("year")));
        retryPayload.put("seasonNumber", optionalInteger(payload.get("seasonNumber")));
        retryPayload.put("episodeNumber", optionalInteger(payload.get("episodeNumber")));
        retryPayload.put("force", booleanValue(payload.get("force")));
        return retryPayload;
    }

    private Map<String, Object> transcodePayload(UUID taskId, Map<String, Object> payload) {
        return Map.of(
                "taskId", taskId.toString(),
                "videoItemId", requiredUuid(payload, "videoItemId").toString(),
                "ownerUserId", requiredUuid(payload, "ownerUserId").toString(),
                "audioOnly", booleanValue(payload.get("audioOnly")),
                "webOptimize", booleanValue(payload.get("webOptimize"))
        );
    }

    private Map<String, Object> comicParsePayload(UUID taskId, Map<String, Object> payload) {
        return Map.of(
                "taskId", taskId.toString(),
                "ownerUserId", requiredUuid(payload, "ownerUserId").toString(),
                "itemId", requiredUuid(payload, "itemId").toString(),
                "sourceId", requiredUuid(payload, "sourceId").toString(),
                "fileNodeId", requiredUuid(payload, "fileNodeId").toString(),
                "fileFormat", requiredText(payload, "fileFormat"),
                "contentHash", requiredText(payload, "contentHash"),
                "isRetry", true
        );
    }

    /**
     * 重建文本书籍解析事件。
     *
     * <p>事件里的 ownerUserId 是文件归属者而不是书架归属者，两者在共享文件场景下不同，
     * 因此优先取 fileOwnerId，老任务无该键时退回 ownerUserId。</p>
     */
    private Map<String, Object> readerParsePayload(UUID taskId, Map<String, Object> payload) {
        UUID fileOwnerId = nullableUuid(payload.getOrDefault("fileOwnerId", payload.get("ownerUserId")));
        if (fileOwnerId == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "任务缺少可重试载荷字段: fileOwnerId");
        }
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("taskId", taskId.toString());
        event.put("ownerUserId", fileOwnerId.toString());
        event.put("itemId", requiredUuid(payload, "itemId").toString());
        event.put("fileNodeId", requiredUuid(payload, "fileNodeId").toString());
        event.put("fileFormat", requiredText(payload, "fileFormat"));
        event.put("contentHash", optionalText(payload, "contentHash", ""));
        event.put("isRetry", true);
        return event;
    }

    /**
     * 取载荷里的归属用户，缺失时回退到任务行上的归属用户。
     */
    private UUID requireOwner(Map<String, Object> payload, UUID fallbackOwnerUserId) {
        UUID fromPayload = nullableUuid(payload.get("ownerUserId"));
        if (fromPayload != null) {
            return fromPayload;
        }
        if (fallbackOwnerUserId != null) {
            return fallbackOwnerUserId;
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "任务缺少可重试载荷字段: ownerUserId");
    }

    /**
     * 空串与缺失都按 null 处理：这些字段在事件里本就可为空。
     */
    private UUID nullableUuid(Object raw) {
        if (raw == null || raw.toString().isBlank()) {
            return null;
        }
        try {
            return UUID.fromString(raw.toString().trim());
        } catch (IllegalArgumentException ex) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "任务载荷字段格式错误");
        }
    }

    private String nullableText(Object raw) {
        if (raw == null || raw.toString().isBlank()) {
            return null;
        }
        return raw.toString().trim();
    }

    private Map<String, Object> parsePayload(String payloadJson) {
        if (payloadJson == null || payloadJson.isBlank()) {
            return Map.of();
        }
        try {
            Map<String, Object> parsed = JsonSupport.fromJson(payloadJson, MAP_TYPE);
            return parsed == null ? Map.of() : parsed;
        } catch (RuntimeException ex) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "任务载荷不是合法 JSON，无法重试");
        }
    }

    private UUID requiredUuid(Map<String, Object> payload, String key) {
        String value = requiredText(payload, key);
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException ex) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "任务载荷字段格式错误: " + key);
        }
    }

    private String requiredText(Map<String, Object> payload, String key) {
        String value = optionalText(payload, key, null);
        if (value == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "任务缺少可重试载荷字段: " + key);
        }
        return value;
    }

    private String optionalText(Map<String, Object> payload, String key, String defaultValue) {
        Object value = payload.get(key);
        if (value == null || value.toString().isBlank()) {
            return defaultValue;
        }
        return value.toString().trim();
    }

    private Integer optionalInteger(Object value) {
        if (value == null || value.toString().isBlank()) {
            return null;
        }
        if (value instanceof Number number) {
            return number.intValue();
        }
        try {
            return Integer.parseInt(value.toString());
        } catch (NumberFormatException ex) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "任务载荷数字字段格式错误");
        }
    }

    private long longValue(Object value) {
        if (value instanceof Number number) {
            return number.longValue();
        }
        try {
            return Long.parseLong(value.toString());
        } catch (RuntimeException ex) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "任务载荷 sizeBytes 格式错误");
        }
    }

    private boolean booleanValue(Object value) {
        if (value instanceof Boolean bool) {
            return bool;
        }
        return value != null && Boolean.parseBoolean(value.toString());
    }
}
