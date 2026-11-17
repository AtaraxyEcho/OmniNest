package com.omninest.modules.photos.event;

import java.util.UUID;

/**
 * 照片位置回填异步任务事件。
 *
 * @param taskId 通用任务标识
 * @param batchSize 每批处理照片数量
 * @param datasetVersion 任务绑定的数据集版本，为空时使用执行时的当前快照
 * @author OmniNest
 */
public record PhotoGeoBackfillEvent(
        UUID taskId,
        int batchSize,
        String datasetVersion
) {
}
