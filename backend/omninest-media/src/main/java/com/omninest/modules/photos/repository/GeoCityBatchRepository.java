package com.omninest.modules.photos.repository;

import java.util.List;
import java.util.UUID;

/**
 * GeoNames 城市批量写入仓储。
 *
 * @author OmniNest
 */
public interface GeoCityBatchRepository {

    /**
     * 幂等批量写入城市记录；冲突时保留已回填的城市中文名，其余字段以本次导入为准。
     *
     * <p>单批一次网络往返，避免逐行 upsert 把数万行导入放大成数万次往返。</p>
     *
     * @param datasetId 数据集 ID
     * @param rows 同一批次的城市记录
     * @return 实际写入行数
     */
    int upsertCities(UUID datasetId, List<GeoCityUpsertRow> rows);
}
