package com.omninest.modules.photos.event;

import java.util.UUID;

/**
 * 照片图像分析异步任务事件。
 *
 * @param taskId 通用任务标识，旧消息可能为空
 * @param ownerUserId 所属用户标识
 * @param photoId 单张分析时的照片标识
 * @param mode 任务执行模式
 * @author OmniNest
 */
public record PhotoAiEvent(
        UUID taskId,
        UUID ownerUserId,
        UUID photoId,
        Mode mode
) {

    /**
     * 照片图像分析任务执行模式。
     *
     * @author OmniNest
     */
    public enum Mode {
        SINGLE_PHOTO,
        LIBRARY_REANALYSIS
    }
}
