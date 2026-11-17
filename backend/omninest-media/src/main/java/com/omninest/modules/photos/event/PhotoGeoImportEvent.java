package com.omninest.modules.photos.event;

import java.util.UUID;

/**
 * GeoNames 数据集导入异步任务事件。
 *
 * @param taskId 通用任务标识
 * @param datasetId 数据集标识
 * @param datasetVersion 数据集版本号
 * @param dumpDate GeoNames dump 日期（ISO，即共享目录名）
 * @author OmniNest
 */
public record PhotoGeoImportEvent(
        UUID taskId,
        UUID datasetId,
        String datasetVersion,
        String dumpDate
) {
}
