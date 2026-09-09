package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.config.GeonamesImportProperties;
import com.omninest.modules.photos.domain.GeoDataset;
import com.omninest.modules.photos.event.PhotoGeoBackfillEvent;
import com.omninest.modules.photos.event.PhotoGeoImportEvent;
import com.omninest.modules.photos.repository.GeoDatasetRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * GeoNames 数据集管理服务（API 侧）。
 *
 * <p>负责创建导入/回填任务、查询当前版本与手动重载；文件解析和发布由 Worker 执行。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class GeoDatasetService {

    /** 创建 GeoNames 导入任务请求。 */
    public record GeoImportRequest(String dumpDate, String sourceHash) {
    }

    /** 创建导入任务响应。 */
    public record GeoImportCreated(UUID taskId, UUID datasetId, String datasetVersion) {
    }

    /** 创建回填任务响应。 */
    public record GeoBackfillCreated(UUID taskId, boolean reused) {
    }

    /** 导入任务类型。 */
    public static final String TASK_TYPE_IMPORT = "PHOTO_GEO_IMPORT";
    /** 回填任务类型。 */
    public static final String TASK_TYPE_BACKFILL = "PHOTO_GEO_BACKFILL";

    /** 回填任务配置广播 key 前缀：数据集发布后通知所有实例重载索引。 */
    public static final String BROADCAST_KEY_PREFIX = "photo.geo.dataset.reload:";

    /** 数据集版本号中的数据集类型段。 */
    private static final String DATASET_TYPE = "cities5000";
    /** 默认回填批次大小。 */
    private static final int DEFAULT_BACKFILL_BATCH_SIZE = 200;
    /** 回填批次大小上限。 */
    private static final int MAX_BACKFILL_BATCH_SIZE = 1000;

    private final GeoDatasetRepository geoDatasetRepository;
    private final GeoCityIndex geoCityIndex;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final GeonamesImportProperties importProperties;

    /**
     * 创建 GeoNames 数据集导入任务。
     *
     * <p>仅创建 geo_dataset 与 sys_tasks 并投递消息；四个 dump 文件须由管理员预先放置在
     * 共享目录（photo.geo.import.dir，默认 data/geonames）下，由 Worker 读取；
     * dumpDate 仅用于数据集版本记录，不参与文件路径。</p>
     *
     * @param request 导入请求（dumpDate 必填）
     * @param operatorUserId 操作管理员用户 ID
     * @return 任务与数据集标识
     */
    @Transactional(rollbackFor = Exception.class)
    public GeoImportCreated createImportTask(GeoImportRequest request, UUID operatorUserId) {
        if (request == null || request.dumpDate() == null || request.dumpDate().isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "缺少 dumpDate 参数");
        }
        LocalDate dumpDate;
        try {
            dumpDate = LocalDate.parse(request.dumpDate().trim());
        } catch (DateTimeParseException ex) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "dumpDate 必须为 ISO 日期格式（如 2026-09-05）");
        }

        String datasetVersion = nextDatasetVersion(dumpDate);
        GeoDataset dataset = new GeoDataset();
        dataset.setDatasetVersion(datasetVersion);
        dataset.setSourceDumpDate(dumpDate);
        dataset.setDatasetType(DATASET_TYPE);
        dataset.setSourceHash(request.sourceHash());
        dataset.setStatus(GeoDataset.STATUS_IMPORTING);
        geoDatasetRepository.save(dataset);

        UUID taskId = UUID.randomUUID();
        PhotoGeoImportEvent event = new PhotoGeoImportEvent(taskId, dataset.getId(), datasetVersion, dumpDate.toString());
        taskRecordService.createQueuedTask(
                taskId,
                operatorUserId,
                TASK_TYPE_IMPORT,
                QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY,
                GeonamesImportService.PHASE_VALIDATING,
                "GEO_DATASET",
                dataset.getId(),
                Map.of(
                        "datasetId", dataset.getId().toString(),
                        "datasetVersion", datasetVersion,
                        "dumpDate", dumpDate.toString()
                ));

        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY,
                event
        );

        log.info("GeoNames 数据集导入任务已创建: taskId={}, datasetVersion={}, operator={}",
                taskId, datasetVersion, operatorUserId);
        return new GeoImportCreated(taskId, dataset.getId(), datasetVersion);
    }

    /**
     * 创建存量照片位置回填任务；已存在活跃回填任务时返回原任务，避免重复执行。
     *
     * @param operatorUserId 操作管理员用户 ID
     * @param batchSize 每批处理数量，空值使用默认值
     * @return 任务标识与是否复用已有任务
     */
    @Transactional(rollbackFor = Exception.class)
    public GeoBackfillCreated createBackfillTask(UUID operatorUserId, Integer batchSize) {
        List<UUID> active = taskRecordService.findActiveTaskIdsByType(
                TASK_TYPE_BACKFILL,
                List.of("QUEUED", "RUNNING", "RETRY_WAIT"));
        if (!active.isEmpty()) {
            return new GeoBackfillCreated(active.get(0), true);
        }

        int safeBatchSize = batchSize == null
                ? DEFAULT_BACKFILL_BATCH_SIZE
                : Math.clamp(batchSize, 1, MAX_BACKFILL_BATCH_SIZE);
        GeoDataset published = geoDatasetRepository.findFirstByStatusOrderByPublishedAtDesc(GeoDataset.STATUS_PUBLISHED).orElse(null);

        UUID taskId = UUID.randomUUID();
        PhotoGeoBackfillEvent event = new PhotoGeoBackfillEvent(
                taskId,
                safeBatchSize,
                published == null ? null : published.getDatasetVersion());
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("batchSize", safeBatchSize);
        payload.put("datasetVersion", event.datasetVersion());
        taskRecordService.createQueuedTask(
                taskId,
                operatorUserId,
                TASK_TYPE_BACKFILL,
                QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY,
                payload);

        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY,
                event
        );

        log.info("照片位置回填任务已创建: taskId={}, batchSize={}, operator={}",
                taskId, safeBatchSize, operatorUserId);
        return new GeoBackfillCreated(taskId, false);
    }

    /**
     * 手动重载本实例索引到当前已发布数据集。
     *
     * @return 加载的版本号，无已发布数据集时返回 null
     */
    public String reloadCurrentPublished() {
        return geoCityIndex.reloadCurrentPublished();
    }

    /** @return 当前已发布数据集版本，不存在时返回 null */
    @Transactional(readOnly = true)
    public String currentPublishedVersion() {
        return geoDatasetRepository.findFirstByStatusOrderByPublishedAtDesc(GeoDataset.STATUS_PUBLISHED)
                .map(GeoDataset::getDatasetVersion)
                .orElse(null);
    }

    /** @return GeoNames 数据文件共享根目录 */
    public String importRootDir() {
        return importProperties.getDir();
    }

    private String nextDatasetVersion(LocalDate dumpDate) {
        String prefix = dumpDate + "-" + DATASET_TYPE + "-";
        long existing = geoDatasetRepository.countByDatasetVersionStartingWith(prefix);
        String candidate = prefix + String.format("%03d", existing + 1);
        if (geoDatasetRepository.findByDatasetVersion(candidate).isPresent()) {
            // 并发创建同前缀版本时兜底报错，由管理员重试生成新序号。
            throw new BusinessException(ErrorCode.CONFLICT, "数据集版本已存在: " + candidate);
        }
        return candidate;
    }
}
