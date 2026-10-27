package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.DomainEventPublisher;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.config.ConfigRefreshEvent;
import com.omninest.modules.photos.config.GeonamesImportProperties;
import com.omninest.modules.photos.domain.GeoDataset;
import com.omninest.modules.photos.repository.GeoCityRepository;
import com.omninest.modules.photos.repository.GeoCityUpsertRow;
import com.omninest.modules.photos.repository.GeoDatasetRepository;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.photos.service.GeoNamesParser.Admin1Entry;
import com.omninest.modules.photos.service.GeoNamesParser.CityRow;
import com.omninest.modules.photos.service.GeoNamesParser.CountryEntry;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * GeoNames 数据集导入执行服务（Worker 侧）。
 *
 * <p>按阶段执行：VALIDATING → IMPORTING_CITIES → IMPORTING_ALTERNATE_NAMES →
 * VALIDATING_DATASET → PUBLISHING。阶段状态保存在 sys_tasks.phase，
 * 失败重试从失败阶段继续；数据写入按 (dataset_id, geoname_id) 幂等 upsert，
 * 不做 byte-level checkpoint。发布为短事务原子交换，完成后广播各实例重载索引。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class GeonamesImportService {
    private static final int CITY_NAME_UPDATE_BATCH_SIZE = 1_000;

    private static final String UPDATE_CITY_NAME_ZH_SQL = """
            UPDATE omni.geo_cities
            SET name_zh = ?
            WHERE dataset_id = ? AND geoname_id = ?
              AND (name_zh IS NULL OR name_zh <> ?)
            """;

    /** 阶段：校验数据文件。 */
    public static final String PHASE_VALIDATING = "VALIDATING";
    /** 阶段：导入城市基础数据（含省市英文名）。 */
    public static final String PHASE_IMPORTING_CITIES = "IMPORTING_CITIES";
    /** 阶段：导入中文别名并回填。 */
    public static final String PHASE_IMPORTING_ALTERNATE_NAMES = "IMPORTING_ALTERNATE_NAMES";
    /** 阶段：验证数据集并置为 READY。 */
    public static final String PHASE_VALIDATING_DATASET = "VALIDATING_DATASET";
    /** 阶段：发布为当前线上版本。 */
    public static final String PHASE_PUBLISHING = "PUBLISHING";

    private static final List<String> PHASE_ORDER = List.of(
            PHASE_VALIDATING,
            PHASE_IMPORTING_CITIES,
            PHASE_IMPORTING_ALTERNATE_NAMES,
            PHASE_VALIDATING_DATASET,
            PHASE_PUBLISHING
    );

    private static final String CITIES_FILE = "cities5000.txt";
    private static final String ADMIN1_FILE = "admin1CodesASCII.txt";
    private static final String COUNTRY_FILE = "countryInfo.txt";
    private static final String ALTERNATES_FILE = "alternateNamesV2.txt";

    /** 导入必需文件；alternateNamesV2.txt 可选，缺失时中文名回退主名称。 */
    public static final List<String> REQUIRED_DUMP_FILES =
            List.of(CITIES_FILE, ADMIN1_FILE, COUNTRY_FILE);

    private final GeoDatasetRepository geoDatasetRepository;
    private final GeoCityRepository geoCityRepository;
    private final GeoNamesParser parser;
    private final GeonamesImportProperties importProperties;
    private final PhotosRuntimeConfigService configService;
    private final TaskRecordService taskRecordService;
    private final TransactionTemplate transactionTemplate;
    private final GeoCityIndex geoCityIndex;
    private final JdbcTemplate jdbcTemplate;
    private final DomainEventPublisher eventPublisher;

    /**
     * 执行 GeoNames 导入任务（由 Worker 消费者调用）。
     *
     * @param taskId 任务 ID
     */
    public void executeImportTask(UUID taskId) {
        Map<String, Object> payload = taskRecordService.taskPayload(taskId);
        UUID datasetId = parseUuid(payload.get("datasetId"));
        String datasetVersion = string(payload.get("datasetVersion"));
        String dumpDate = string(payload.get("dumpDate"));
        if (datasetId == null || datasetVersion == null || dumpDate == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "导入任务载荷缺少 datasetId/datasetVersion/dumpDate");
        }

        String phase = taskRecordService.taskPhase(taskId);
        if (phase == null || phase.isBlank()) {
            phase = PHASE_VALIDATING;
        }
        if (!taskRecordService.claimForExecution(taskId, phase)) {
            return;
        }

        GeoDataset dataset = geoDatasetRepository.findById(datasetId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "GeoNames 数据集不存在"));
        Path importDir = importDir();
        try {
            runPhases(taskId, dataset, importDir, phase);
        } catch (TaskCancelled cancelled) {
            markDatasetFailed(dataset, "导入已取消");
            taskRecordService.markCancelled(taskId);
            log.info("GeoNames 导入任务已取消: taskId={}, datasetVersion={}", taskId, datasetVersion);
            return;
        } catch (RuntimeException | IOException ex) {
            markDatasetFailed(dataset, ex.getMessage());
            throw ex instanceof RuntimeException runtime ? runtime : new IllegalStateException(ex);
        }
    }

    private void runPhases(UUID taskId, GeoDataset dataset, Path importDir, String startPhase)
            throws IOException {
        UUID datasetId = dataset.getId();
        String datasetVersion = dataset.getDatasetVersion();

        if (atOrBefore(startPhase, PHASE_VALIDATING)) {
            validateFiles(importDir);
            taskRecordService.updateExecution(taskId, PHASE_IMPORTING_CITIES, 3);
        }
        if (atOrBefore(startPhase, PHASE_IMPORTING_CITIES)) {
            importCities(taskId, datasetId, importDir);
            taskRecordService.updateExecution(taskId, PHASE_IMPORTING_ALTERNATE_NAMES, 45);
        }
        if (atOrBefore(startPhase, PHASE_IMPORTING_ALTERNATE_NAMES)) {
            importAlternateNames(taskId, datasetId, importDir);
            taskRecordService.updateExecution(taskId, PHASE_VALIDATING_DATASET, 88);
        }
        if (atOrBefore(startPhase, PHASE_VALIDATING_DATASET)) {
            validateDataset(dataset);
            taskRecordService.updateExecution(taskId, PHASE_PUBLISHING, 94);
        }
        if (atOrBefore(startPhase, PHASE_PUBLISHING)) {
            publish(dataset);
        }

        long cityCount = geoCityRepository.countByDatasetId(datasetId);
        taskRecordService.markCompleted(taskId, Map.of(
                "datasetVersion", datasetVersion,
                "cities", cityCount));
        geoCityIndex.reloadCurrentPublished();
        broadcastReload(datasetVersion);
        log.info("GeoNames 数据集导入完成: datasetVersion={}, cityCount={}", datasetVersion, cityCount);
    }

    /** 校验共享目录下的必需文件存在且可读。 */
    private void validateFiles(Path importDir) throws IOException {
        if (!Files.isDirectory(importDir)) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND,
                    "GeoNames 导入目录不存在: " + importDir.getFileName());
        }
        for (String file : REQUIRED_DUMP_FILES) {
            Path path = importDir.resolve(file);
            if (!Files.isRegularFile(path) || !Files.isReadable(path)) {
                throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "缺少 GeoNames 数据文件: " + file);
            }
        }
        // alternateNamesV2 可选：缺失时中文名回退 GeoNames 主名称。
    }

    /** 城市基础数据导入：流式解析 + 分批事务 upsert。 */
    private void importCities(UUID taskId, UUID datasetId, Path importDir) throws IOException {
        Map<String, Admin1Entry> admin1ByCode = parseRequired(importDir.resolve(ADMIN1_FILE), parser::parseAdmin1Codes);
        Map<String, CountryEntry> countryByCode = parseRequired(importDir.resolve(COUNTRY_FILE), parser::parseCountryInfo);
        int batchSize = configService.geoImportBatchSize();

        List<CityRow> buffer = new ArrayList<>(batchSize);
        long[] written = {0};
        long[] skipped = {0};
        int[] batchesSinceHeartbeat = {0};
        try (InputStream citiesInput = Files.newInputStream(importDir.resolve(CITIES_FILE))) {
            parser.streamCities(citiesInput, row -> {
                if (row.countryCode() == null) {
                    skipped[0]++;
                    return;
                }
                buffer.add(row);
                if (buffer.size() >= batchSize) {
                    written[0] += flushCityBuffer(datasetId, buffer, admin1ByCode, countryByCode);
                    batchesSinceHeartbeat[0]++;
                    if (batchesSinceHeartbeat[0] >= 10) {
                        // 独立事务更新进度并保活心跳，避免长阶段被误判为心跳超时。
                        taskRecordService.updateProgressImmediately(taskId, cityPhaseProgress(written[0]));
                        batchesSinceHeartbeat[0] = 0;
                    }
                    ensureNotCancelled(taskId);
                }
            });
        }
        if (!buffer.isEmpty()) {
            written[0] += flushCityBuffer(datasetId, buffer, admin1ByCode, countryByCode);
        }
        if (skipped[0] > 0) {
            log.warn("已跳过缺少国家码的 GeoNames 行: count={}", skipped[0]);
        }
        taskRecordService.updateResult(taskId, Map.of(
                "phase", PHASE_IMPORTING_CITIES,
                "citiesImported", written[0]));
    }

    /** 中文名导入：流式扫描 alternateNamesV2，按需收集候选后分批回填。 */
    private void importAlternateNames(UUID taskId, UUID datasetId, Path importDir) throws IOException {
        Set<Long> cityIds = new HashSet<>(geoCityRepository.findGeonameIdsByDatasetId(datasetId));
        Map<String, Admin1Entry> admin1ByCode = parseRequired(importDir.resolve(ADMIN1_FILE), parser::parseAdmin1Codes);
        Map<String, CountryEntry> countryByCode = parseRequired(importDir.resolve(COUNTRY_FILE), parser::parseCountryInfo);

        Map<Long, String> admin1NameById = new HashMap<>();
        admin1ByCode.forEach((code, entry) -> admin1NameById.putIfAbsent(entry.geonameId(), entry.nameEn()));
        Map<Long, String> countryIsoById = new HashMap<>();
        countryByCode.forEach((iso, entry) -> countryIsoById.putIfAbsent(entry.geonameId(), iso));

        GeoLocationNameSelector selector = new GeoLocationNameSelector();
        Path alternatesPath = importDir.resolve(ALTERNATES_FILE);
        if (!Files.isRegularFile(alternatesPath)) {
            log.info("未检测到可选文件 {}，跳过中文别名补充", ALTERNATES_FILE);
            taskRecordService.updateResult(taskId, Map.of(
                    "phase", PHASE_IMPORTING_ALTERNATE_NAMES,
                    "alternateNamesScanned", 0));
            return;
        }
        long[] scanned = {0};
        long[] lastHeartbeatNanos = {System.nanoTime()};
        try (InputStream alternatesInput = Files.newInputStream(alternatesPath)) {
            parser.streamAlternateNames(alternatesInput, candidate -> {
                long geonameId = candidate.geonameId();
                if (cityIds.contains(geonameId)
                        || admin1NameById.containsKey(geonameId)
                        || countryIsoById.containsKey(geonameId)) {
                    selector.offer(
                            geonameId,
                            candidate.language(),
                            candidate.name(),
                            candidate.preferred(),
                            candidate.historic());
                }
                scanned[0]++;
                // 按时间间隔保活心跳（约 30 秒），避免长扫描阶段被误判为心跳超时。
                if (System.nanoTime() - lastHeartbeatNanos[0] > 30_000_000_000L) {
                    taskRecordService.updateResult(taskId, Map.of(
                            "phase", PHASE_IMPORTING_ALTERNATE_NAMES,
                            "alternateNamesScanned", scanned[0]));
                    lastHeartbeatNanos[0] = System.nanoTime();
                }
            });
        }

        transactionTemplate.executeWithoutResult(status -> {
            // 逐条 UPDATE 在 4-6 万个城市上会产生同样次数的数据库往返；
            // 按批提交既保留事务边界又能在秒级完成。
            List<Object[]> cityNameBatches = new ArrayList<>();
            for (Long geonameId : selector.collectedIds()) {
                if (!cityIds.contains(geonameId)) {
                    continue;
                }
                String nameZh = selector.best(geonameId);
                if (nameZh != null) {
                    cityNameBatches.add(new Object[]{nameZh, datasetId, geonameId, nameZh});
                }
            }
            for (int start = 0; start < cityNameBatches.size(); start += CITY_NAME_UPDATE_BATCH_SIZE) {
                int end = Math.min(start + CITY_NAME_UPDATE_BATCH_SIZE, cityNameBatches.size());
                jdbcTemplate.batchUpdate(UPDATE_CITY_NAME_ZH_SQL, cityNameBatches.subList(start, end));
            }
            admin1ByCode.forEach((code, entry) -> {
                String zh = selector.best(entry.geonameId());
                if (zh != null) {
                    geoCityRepository.updateProvinceNameZh(datasetId, entry.nameEn(), zh);
                }
            });
            countryByCode.forEach((iso, entry) -> {
                String zh = selector.best(entry.geonameId());
                if (zh != null) {
                    geoCityRepository.updateCountryNameZh(datasetId, iso, zh);
                }
            });
        });
        taskRecordService.updateResult(taskId, Map.of(
                "phase", PHASE_IMPORTING_ALTERNATE_NAMES,
                "alternateNamesScanned", scanned[0]));
    }

    /** 数据集验证：非空即视为通过，并置为 READY。 */
    private void validateDataset(GeoDataset dataset) {
        long count = geoCityRepository.countByDatasetId(dataset.getId());
        if (count == 0) {
            throw new BusinessException(ErrorCode.VALIDATION_FAILED, "数据集城市为空，校验未通过");
        }
        dataset.setStatus(GeoDataset.STATUS_READY);
        geoDatasetRepository.save(dataset);
    }

    /** 发布：短事务原子交换，任意时刻至多一个 PUBLISHED 数据集。 */
    private void publish(GeoDataset dataset) {
        transactionTemplate.executeWithoutResult(status -> {
            GeoDataset target = geoDatasetRepository.findById(dataset.getId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "GeoNames 数据集不存在"));
            if (GeoDataset.STATUS_PUBLISHED.equals(target.getStatus())) {
                return;
            }
            geoDatasetRepository.findFirstByStatusForUpdate(GeoDataset.STATUS_PUBLISHED)
                    .filter(current -> !current.getId().equals(target.getId()))
                    .ifPresent(current -> current.setStatus(GeoDataset.STATUS_ARCHIVED));
            target.setStatus(GeoDataset.STATUS_PUBLISHED);
            target.setPublishedAt(Instant.now());
            geoDatasetRepository.save(target);
        });
    }

    private int flushCityBuffer(
            UUID datasetId,
            List<CityRow> buffer,
            Map<String, Admin1Entry> admin1ByCode,
            Map<String, CountryEntry> countryByCode) {
        List<GeoCityUpsertRow> rows = new ArrayList<>(buffer.size());
        for (CityRow row : buffer) {
            Admin1Entry admin1 = row.admin1Code() == null
                    ? null
                    : admin1ByCode.get(row.countryCode() + "." + row.admin1Code());
            String provinceEn = admin1 == null ? row.admin1Code() : admin1.nameEn();
            CountryEntry country = countryByCode.get(row.countryCode());
            String countryEn = country == null ? row.countryCode() : country.nameEn();
            rows.add(new GeoCityUpsertRow(
                    row.geonameId(),
                    row.name(),
                    row.countryCode(),
                    countryEn,
                    provinceEn,
                    row.latitude(),
                    row.longitude(),
                    row.population(),
                    row.featureCode()));
        }
        int[] written = {0};
        transactionTemplate.executeWithoutResult(status ->
                written[0] = geoCityRepository.upsertCities(datasetId, rows));
        buffer.clear();
        return written[0];
    }

    private void broadcastReload(String datasetVersion) {
        try {
            eventPublisher.publishFanout(
                    QueueNames.CONFIG_REFRESH_EXCHANGE,
                    new ConfigRefreshEvent(UUID.randomUUID(), GeoDatasetService.BROADCAST_KEY_PREFIX + datasetVersion, Instant.now()));
        } catch (RuntimeException ex) {
            // 广播失败不影响发布结果；其他实例可通过手动 reload 或重启对齐。
            log.error("GeoNames 数据集发布广播失败: datasetVersion={}", datasetVersion, ex);
        }
    }

    private void markDatasetFailed(GeoDataset dataset, String message) {
        try {
            GeoDataset current = geoDatasetRepository.findById(dataset.getId()).orElse(null);
            if (current != null && !GeoDataset.STATUS_PUBLISHED.equals(current.getStatus())) {
                current.setStatus(GeoDataset.STATUS_FAILED);
                geoDatasetRepository.save(current);
            }
        } catch (RuntimeException ex) {
            log.error("标记 GeoNames 数据集失败状态出错: datasetId={}", dataset.getId(), ex);
        }
        log.warn("GeoNames 导入失败: datasetVersion={}, reason={}", dataset.getDatasetVersion(), message);
    }

    private void ensureNotCancelled(UUID taskId) {
        if (taskRecordService.isCancelled(taskId)) {
            throw new TaskCancelled();
        }
    }

    private int cityPhaseProgress(long written) {
        // cities5000 实测约 7 万行，按每 1250 行提升 1% 估算，封顶到城市阶段区间（3~44）。
        return Math.min(44, 3 + (int) (written / 1250));
    }

    /** @return GeoNames 数据文件共享目录（四个 dump 文件直接置于该目录下） */
    private Path importDir() {
        return Path.of(importProperties.getDir()).normalize();
    }

    private <T> T parseRequired(Path file, IoFunction<InputStream, T> parserFunction) throws IOException {
        try (InputStream input = Files.newInputStream(file)) {
            return parserFunction.apply(input);
        }
    }

    private boolean atOrBefore(String currentPhase, String phase) {
        return PHASE_ORDER.indexOf(currentPhase) <= PHASE_ORDER.indexOf(phase);
    }

    private static UUID parseUuid(Object value) {
        try {
            return value == null ? null : UUID.fromString(String.valueOf(value));
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }

    private static String string(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    /** 任务被协作式取消的内部信号。 */
    private static final class TaskCancelled extends RuntimeException {

        @Override
        public synchronized Throwable fillInStackTrace() {
            return this;
        }
    }

    /** 可抛 IOException 的函数接口。 */
    @FunctionalInterface
    private interface IoFunction<T, R> {

        /**
         * 应用函数。
         *
         * @param input 输入
         * @return 输出
         * @throws IOException IO 异常
         */
        R apply(T input) throws IOException;
    }
}
