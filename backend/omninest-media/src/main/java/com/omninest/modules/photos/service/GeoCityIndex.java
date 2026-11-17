package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.photos.domain.GeoDataset;
import com.omninest.modules.photos.repository.GeoCityRepository;
import com.omninest.modules.photos.repository.GeoDatasetRepository;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * GeoNames 城市内存索引。
 *
 * <p>启动即加载已发布（PUBLISHED）数据集并构建不可变快照；数据集发布或收到广播后
 * 通过"构建新快照 + 原子引用交换"整体刷新，禁止先清空再加载的中间态。
 * 最近城市查询基于快照的纬度排序副本做球面距离下界剪枝扫描（方案 §35 全量线性扫描
 * 在真实 cities5000 数据上实测超出延迟目标后触发的内置优化），结果与全量 O(N) 扫描一致。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class GeoCityIndex {

    private final GeoCityRepository geoCityRepository;
    private final GeoDatasetRepository geoDatasetRepository;

    private final AtomicReference<GeoCitySnapshot> snapshot = new AtomicReference<>(GeoCitySnapshot.EMPTY);

    /** 应用启动完成后加载当前已发布数据集；失败不阻塞启动，保持空索引。 */
    @EventListener(ApplicationReadyEvent.class)
    public void loadOnStartup() {
        try {
            geoDatasetRepository.findFirstByStatusOrderByPublishedAtDesc(GeoDataset.STATUS_PUBLISHED)
                    .ifPresentOrElse(
                            dataset -> swapTo(dataset.getDatasetVersion(), dataset.getId()),
                            () -> log.info("当前无已发布 GeoNames 数据集，离线索引保持为空"));
        } catch (RuntimeException ex) {
            log.error("启动加载 GeoNames 离线索引失败，可通过管理端 reload 恢复", ex);
        }
    }

    /**
     * 查询最近城市；GPS 非法或索引为空时返回 empty。
     *
     * @param latitude 纬度
     * @param longitude 经度
     * @return 最近城市命中结果
     */
    public Optional<GeoCityMatch> nearest(double latitude, double longitude) {
        return nearestInSnapshot(snapshot.get(), latitude, longitude);
    }

    /**
     * 在指定快照内查询最近城市（供回填任务的钉定快照复用同一条剪枝扫描路径）。
     *
     * <p>剪枝依据：大圆角距恒不低于两点纬度差，因此当候选城市的纬度差对应弧长
     * 已不小于当前最优距离时，纬度排序下该侧剩余候选均不可能更近。</p>
     *
     * @param snapshot 目标快照
     * @param latitude 纬度（度）
     * @param longitude 经度（度）
     * @return 最近城市命中结果
     */
    public static Optional<GeoCityMatch> nearestInSnapshot(
            GeoCitySnapshot snapshot,
            double latitude,
            double longitude) {
        if (!isValidCoordinate(latitude, longitude)) {
            return Optional.empty();
        }
        GeoCitySnapshot.Entry[] byLatitude = snapshot.byLatitude();
        if (byLatitude.length == 0) {
            return Optional.empty();
        }

        double latitudeRadians = Math.toRadians(latitude);
        double longitudeRadians = Math.toRadians(longitude);

        int higher = lowerBound(byLatitude, latitudeRadians);
        int lower = higher - 1;
        boolean lowerDone = lower < 0;
        boolean higherDone = higher >= byLatitude.length;

        GeoCitySnapshot.Entry best = null;
        double bestKm = Double.MAX_VALUE;
        while (!lowerDone || !higherDone) {
            GeoCitySnapshot.Entry candidate;
            boolean takeLower;
            if (lowerDone) {
                takeLower = false;
            } else if (higherDone) {
                takeLower = true;
            } else {
                takeLower = latitudeRadians - byLatitude[lower].latitudeRadians()
                        <= byLatitude[higher].latitudeRadians() - latitudeRadians;
            }
            if (takeLower) {
                candidate = byLatitude[lower--];
                lowerDone = lower < 0;
            } else {
                candidate = byLatitude[higher++];
                higherDone = higher >= byLatitude.length;
            }

            if (GeoDistance.EARTH_RADIUS_KM
                    * Math.abs(candidate.latitudeRadians() - latitudeRadians) >= bestKm) {
                if (takeLower) {
                    lowerDone = true;
                } else {
                    higherDone = true;
                }
                continue;
            }
            double distanceKm = GeoDistance.haversineKmRadians(
                    latitudeRadians,
                    longitudeRadians,
                    candidate.latitudeRadians(),
                    candidate.longitudeRadians());
            if (distanceKm < bestKm) {
                bestKm = distanceKm;
                best = candidate;
            }
        }
        return best == null ? Optional.empty() : Optional.of(new GeoCityMatch(best, bestKm));
    }

    /** @return 当前快照（不可变） */
    public GeoCitySnapshot currentSnapshot() {
        return snapshot.get();
    }

    /**
     * 获取指定已发布数据集的独立快照（不切换线上索引）。
     *
     * <p>回填任务用其在整个任务期间绑定同一数据版本；版本不存在或未发布时回退当前快照。</p>
     *
     * @param datasetVersion 目标数据集版本号，为空时返回当前快照
     * @return 绑定版本的快照
     */
    public GeoCitySnapshot snapshotOfVersion(String datasetVersion) {
        if (datasetVersion == null || datasetVersion.isBlank()) {
            return snapshot.get();
        }
        if (datasetVersion.equals(snapshot.get().datasetVersion())) {
            return snapshot.get();
        }
        return geoDatasetRepository.findByDatasetVersion(datasetVersion)
                .filter(dataset -> GeoDataset.STATUS_PUBLISHED.equals(dataset.getStatus()))
                .map(dataset -> GeoCitySnapshot.from(
                        dataset.getDatasetVersion(),
                        geoCityRepository.findRowsByDatasetId(dataset.getId())))
                .orElseGet(() -> {
                    log.warn("指定的 GeoNames 数据集不可用，回填改用当前快照: datasetVersion={}", datasetVersion);
                    return snapshot.get();
                });
    }

    /**
     * 重载到指定版本的数据集；版本不存在或未发布时抛出业务异常。
     *
     * @param datasetVersion 目标数据集版本号
     * @return 实际加载的版本号
     */
    public String reloadToVersion(String datasetVersion) {
        var dataset = geoDatasetRepository.findByDatasetVersion(datasetVersion)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "GeoNames 数据集不存在"));
        if (!GeoDataset.STATUS_PUBLISHED.equals(dataset.getStatus())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "GeoNames 数据集未发布，无法加载");
        }
        swapTo(dataset.getDatasetVersion(), dataset.getId());
        return dataset.getDatasetVersion();
    }

    /** @return 重载当前已发布数据集后的版本号；无已发布数据集时返回 null */
    public String reloadCurrentPublished() {
        var dataset = geoDatasetRepository.findFirstByStatusOrderByPublishedAtDesc(GeoDataset.STATUS_PUBLISHED);
        if (dataset.isEmpty()) {
            snapshot.set(GeoCitySnapshot.EMPTY);
            log.info("已清空 GeoNames 离线索引（无已发布数据集）");
            return null;
        }
        swapTo(dataset.get().getDatasetVersion(), dataset.get().getId());
        return dataset.get().getDatasetVersion();
    }

    private void swapTo(String datasetVersion, UUID datasetId) {
        List<GeoCityRepository.GeoCityRow> rows = geoCityRepository.findRowsByDatasetId(datasetId);
        snapshot.set(GeoCitySnapshot.from(datasetVersion, rows));
        log.info("GeoNames 离线城市索引已切换: datasetVersion={}, cityCount={}",
                datasetVersion, rows.size());
    }

    /** 返回第一个纬度不小于目标值的下标（upper bound）。 */
    private static int lowerBound(GeoCitySnapshot.Entry[] byLatitude, double latitudeRadians) {
        int low = 0;
        int high = byLatitude.length;
        while (low < high) {
            int mid = (low + high) >>> 1;
            if (byLatitude[mid].latitudeRadians() < latitudeRadians) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return low;
    }

    private static boolean isValidCoordinate(double latitude, double longitude) {
        return !Double.isNaN(latitude)
                && !Double.isNaN(longitude)
                && !Double.isInfinite(latitude)
                && !Double.isInfinite(longitude)
                && latitude >= -90.0
                && latitude <= 90.0
                && longitude >= -180.0
                && longitude <= 180.0;
    }
}
