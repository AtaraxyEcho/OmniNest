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
public interface GeoCityRepository extends JpaRepository<GeoCity, UUID>, GeoCityBatchRepository {

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
