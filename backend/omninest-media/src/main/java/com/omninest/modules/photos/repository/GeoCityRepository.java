package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.GeoCity;
import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * GeoNames 城市数据仓储。
 *
 * @author OmniNest
 */
public interface GeoCityRepository extends JpaRepository<GeoCity, UUID> {

    /**
     * 快照加载投影：仅取索引与双语展示所需字段，避免长事务内的持久化上下文开销。
     */
    interface GeoCityRow {
        Long getGeonameId();

        String getName();

        String getNameZh();

        String getCountryCode();

        String getCountryNameEn();

        String getCountryNameZh();

        String getProvinceNameEn();

        String getProvinceNameZh();

        BigDecimal getLatitude();

        BigDecimal getLongitude();
    }

    /** @return 指定数据集的城市行（索引快照加载用，约数万行） */
    @Query("""
            select c.geonameId as geonameId, c.name as name, c.nameZh as nameZh,
                   c.countryCode as countryCode, c.countryNameEn as countryNameEn,
                   c.countryNameZh as countryNameZh, c.provinceNameEn as provinceNameEn,
                   c.provinceNameZh as provinceNameZh, c.latitude as latitude,
                   c.longitude as longitude
            from GeoCity c
            where c.datasetId = :datasetId
            """)
    List<GeoCityRow> findRowsByDatasetId(@Param("datasetId") UUID datasetId);

    /** @return 指定数据集的城市数量（数据集验证用） */
    long countByDatasetId(UUID datasetId);

    /** @return 指定数据集内全部城市 geonameId（中文名回填范围） */
    @Query("select c.geonameId from GeoCity c where c.datasetId = :datasetId")
    List<Long> findGeonameIdsByDatasetId(@Param("datasetId") UUID datasetId);

    /**
     * 幂等写入单条城市记录；冲突时保留已回填的中文名，其余字段以本次导入为准。
     *
     * @param datasetId 数据集 ID
     * @param geonameId GeoNames 城市 ID
     * @param name 主名称
     * @param nameZh 中文名（城市基础导入阶段通常为空）
     * @param countryCode ISO 国家码
     * @param countryNameEn 国家英文名
     * @param countryNameZh 国家中文名
     * @param provinceNameEn 一级行政区英文名
     * @param provinceNameZh 一级行政区中文名
     * @param latitude 纬度
     * @param longitude 经度
     * @param population 人口
     * @param featureCode 地物类型代码
     */
    @Modifying
    @Query(value = """
            INSERT INTO omni.geo_cities (
                dataset_id, geoname_id, name, name_zh, country_code,
                country_name_en, country_name_zh, province_name_en, province_name_zh,
                latitude, longitude, population, feature_code, created_at
            ) VALUES (
                :datasetId, :geonameId, :name, :nameZh, :countryCode,
                :countryNameEn, :countryNameZh, :provinceNameEn, :provinceNameZh,
                :latitude, :longitude, :population, :featureCode, now()
            )
            ON CONFLICT (dataset_id, geoname_id) DO UPDATE SET
                name = EXCLUDED.name,
                name_zh = COALESCE(geo_cities.name_zh, EXCLUDED.name_zh),
                country_code = EXCLUDED.country_code,
                country_name_en = EXCLUDED.country_name_en,
                country_name_zh = EXCLUDED.country_name_zh,
                province_name_en = EXCLUDED.province_name_en,
                province_name_zh = EXCLUDED.province_name_zh,
                latitude = EXCLUDED.latitude,
                longitude = EXCLUDED.longitude,
                population = EXCLUDED.population,
                feature_code = EXCLUDED.feature_code
            """, nativeQuery = true)
    void upsertCity(
            @Param("datasetId") UUID datasetId,
            @Param("geonameId") long geonameId,
            @Param("name") String name,
            @Param("nameZh") String nameZh,
            @Param("countryCode") String countryCode,
            @Param("countryNameEn") String countryNameEn,
            @Param("countryNameZh") String countryNameZh,
            @Param("provinceNameEn") String provinceNameEn,
            @Param("provinceNameZh") String provinceNameZh,
            @Param("latitude") BigDecimal latitude,
            @Param("longitude") BigDecimal longitude,
            @Param("population") long population,
            @Param("featureCode") String featureCode
    );

    /**
     * 回填城市中文名。
     *
     * @return 更新行数
     */
    @Modifying
    @Query(value = """
            UPDATE omni.geo_cities
            SET name_zh = :nameZh
            WHERE dataset_id = :datasetId AND geoname_id = :geonameId
              AND (name_zh IS NULL OR name_zh <> :nameZh)
            """, nativeQuery = true)
    int updateCityNameZh(
            @Param("datasetId") UUID datasetId,
            @Param("geonameId") long geonameId,
            @Param("nameZh") String nameZh
    );

    /**
     * 按一级行政区英文名批量回填中文名。
     *
     * @return 更新行数
     */
    @Modifying
    @Query(value = """
            UPDATE omni.geo_cities
            SET province_name_zh = :nameZh
            WHERE dataset_id = :datasetId AND province_name_en = :nameEn
              AND (province_name_zh IS NULL OR province_name_zh <> :nameZh)
            """, nativeQuery = true)
    int updateProvinceNameZh(
            @Param("datasetId") UUID datasetId,
            @Param("nameEn") String nameEn,
            @Param("nameZh") String nameZh
    );

    /**
     * 按国家码批量回填国家中文名。
     *
     * @return 更新行数
     */
    @Modifying
    @Query(value = """
            UPDATE omni.geo_cities
            SET country_name_zh = :nameZh
            WHERE dataset_id = :datasetId AND country_code = :countryCode
              AND (country_name_zh IS NULL OR country_name_zh <> :nameZh)
            """, nativeQuery = true)
    int updateCountryNameZh(
            @Param("datasetId") UUID datasetId,
            @Param("countryCode") String countryCode,
            @Param("nameZh") String nameZh
    );
}
