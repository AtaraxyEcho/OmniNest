package com.omninest.modules.photos.repository;

import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Types;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.BatchPreparedStatementSetter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 基于 JDBC 批处理的 GeoNames 城市批量写入实现。
 *
 * @author OmniNest
 */
@Repository
@RequiredArgsConstructor
public class GeoCityBatchRepositoryImpl implements GeoCityBatchRepository {

    private static final String UPSERT_SQL = """
            INSERT INTO omni.geo_cities (
                dataset_id, geoname_id, name, name_zh, country_code,
                country_name_en, country_name_zh, province_name_en, province_name_zh,
                latitude, longitude, population, feature_code, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, now())
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
            """;

    private final JdbcTemplate jdbcTemplate;

    @Override
    public int upsertCities(UUID datasetId, List<GeoCityUpsertRow> rows) {
        if (rows.isEmpty()) {
            return 0;
        }
        jdbcTemplate.batchUpdate(UPSERT_SQL, new BatchPreparedStatementSetter() {
            @Override
            public void setValues(PreparedStatement statement, int index) throws SQLException {
                GeoCityUpsertRow row = rows.get(index);
                statement.setObject(1, datasetId);
                statement.setLong(2, row.geonameId());
                statement.setString(3, row.name());
                statement.setNull(4, Types.VARCHAR);
                statement.setString(5, row.countryCode());
                statement.setString(6, row.countryNameEn());
                statement.setNull(7, Types.VARCHAR);
                statement.setString(8, row.provinceNameEn());
                statement.setNull(9, Types.VARCHAR);
                statement.setBigDecimal(10, row.latitude());
                statement.setBigDecimal(11, row.longitude());
                statement.setLong(12, row.population());
                statement.setString(13, row.featureCode());
            }

            @Override
            public int getBatchSize() {
                return rows.size();
            }
        });
        // 每条 upsert 必然插入或更新一行；批量更新计数在不同驱动下可能返回
        // SUCCESS_NO_INFO，直接按提交行数上报更稳定。
        return rows.size();
    }
}
