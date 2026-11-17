package com.omninest.modules.photos.service;

import com.omninest.modules.photos.repository.GeoCityRepository;
import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

/**
 * 已发布 GeoNames 数据集的不可变内存快照。
 *
 * <p>构建完成后整体不可变，索引切换通过整体替换引用完成，禁止原地增删。
 * 除原始城市列表外，快照内含按纬度排序的副本，供最近城市查询做
 * "球面距离下界剪枝"（大圆角距恒不低于纬度差，纬度距离之外的候选不可能更近），
 * 结果与全量线性扫描完全一致。</p>
 *
 * @param datasetVersion 数据集版本号
 * @param cities 城市条目（原始顺序）
 * @param byLatitude 按纬度升序排序的城市数组
 * @author OmniNest
 */
public record GeoCitySnapshot(String datasetVersion, List<Entry> cities, Entry[] byLatitude) {

    /** 空快照：尚未导入或未发布任何数据集。 */
    public static final GeoCitySnapshot EMPTY = new GeoCitySnapshot(null, List.of(), null);

    /** 快照城市条目，坐标为弧度预计算值。 */
    public record Entry(
            long geonameId,
            String name,
            String nameZh,
            String countryCode,
            String countryNameEn,
            String countryNameZh,
            String provinceNameEn,
            String provinceNameZh,
            double latitudeRadians,
            double longitudeRadians) {
    }

    /**
     * 构建快照；未显式提供纬度排序副本时由城市列表计算。
     *
     * @param datasetVersion 数据集版本号
     * @param cities 城市条目
     * @param byLatitude 纬度排序副本，为 null 时自动计算
     */
    public GeoCitySnapshot {
        if (byLatitude == null) {
            Entry[] sorted = cities.toArray(new Entry[0]);
            Arrays.sort(sorted, Comparator.comparingDouble(Entry::latitudeRadians));
            byLatitude = sorted;
        }
    }

    /**
     * 常规构建入口。
     *
     * @param datasetVersion 数据集版本号
     * @param cities 城市条目
     * @return 快照
     */
    public static GeoCitySnapshot of(String datasetVersion, List<Entry> cities) {
        return new GeoCitySnapshot(datasetVersion, cities, null);
    }

    /**
     * 从仓储行构建不可变快照。
     *
     * @param datasetVersion 数据集版本号
     * @param rows 城市行
     * @return 快照
     */
    public static GeoCitySnapshot from(String datasetVersion, List<GeoCityRepository.GeoCityRow> rows) {
        List<Entry> entries = rows.stream()
                .map(row -> new Entry(
                        row.getGeonameId(),
                        row.getName(),
                        row.getNameZh(),
                        row.getCountryCode(),
                        row.getCountryNameEn(),
                        row.getCountryNameZh(),
                        row.getProvinceNameEn(),
                        row.getProvinceNameZh(),
                        Math.toRadians(row.getLatitude().doubleValue()),
                        Math.toRadians(row.getLongitude().doubleValue())))
                .toList();
        return of(datasetVersion, entries);
    }
}
