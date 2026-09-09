package com.omninest.modules.task.service;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.TypeReference;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
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

/**
 * 任务重新投递服务：从任务记录重建消费方事件载荷并经 Outbox 重发。
 *
 * <p>供管理员重试、死信重试与停滞任务清扫三类入口共用，保证"存储载荷 →
 * 消费事件"的重建规则只有一份。优先复用最近一次 Outbox 投递的原始消息
 * （部分任务类型的记录载荷是事件子集，只有投递行携带完整事件）；无投递
 * 记录时按路由键从记录载荷重建。未收录的路由键拒绝重投，避免以错误形状
 * 的载荷打爆消费方。</p>
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
                    JSON.parse(dispatch.getPayload())
            );
            return;
        }
        Map<String, Object> payload = rebuildPayload(
                record.getId(),
                record.getTaskType(),
                routingKey,
                record.getPayload()
        );
        enqueueRedispatch(record.getId(), routingKey, payload);
    }

    /**
     * 按路由键将任务载荷重建为消费方事件形状，并经 Outbox 立即投递。
     *
     * @param taskId 任务 ID
     * @param taskType 任务类型（仅用于错误提示）
     * @param routingKey 任务路由键
     * @param payloadJson 任务记录中的载荷 JSON
     * @return 实际投递的载荷
     */
    public Map<String, Object> redispatch(
            UUID taskId,
            String taskType,
            String routingKey,
            String payloadJson
    ) {
        Map<String, Object> payload = rebuildPayload(taskId, taskType, routingKey, payloadJson);
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
     */
    public Map<String, Object> rebuildPayload(
            UUID taskId,
            String taskType,
            String routingKey,
            String payloadJson
    ) {
        Map<String, Object> payload = parsePayload(payloadJson);
        return switch (routingKey) {
            case QueueNames.FILE_INDEX_ROUTING_KEY,
                    QueueNames.TEXT_EXTRACTION_ROUTING_KEY,
                    QueueNames.THUMBNAIL_ROUTING_KEY -> fileUploadedPayload(payload);
            case QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY -> Map.of("taskId", taskId.toString());
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
            case QueueNames.PHOTO_AI_ROUTING_KEY -> Map.of(
                    "photoId", requiredUuid(payload, "photoId").toString(),
                    "ownerUserId", requiredUuid(payload, "ownerUserId").toString()
            );
            case QueueNames.PHOTO_THUMBNAILS_ROUTING_KEY,
                    QueueNames.PHOTO_MOTION_RESCAN_ROUTING_KEY -> Map.of(
                    "taskId", taskId.toString(),
                    "ownerUserId", requiredUuid(payload, "ownerUserId").toString()
            );
            case QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY -> Map.of(
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

    private Map<String, Object> parsePayload(String payloadJson) {
        if (payloadJson == null || payloadJson.isBlank()) {
            return Map.of();
        }
        try {
            Map<String, Object> parsed = JSON.parseObject(payloadJson, MAP_TYPE);
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
