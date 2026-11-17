package com.omninest.modules.photos.service;

import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.event.PhotoAiEvent.Mode;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 原子提交照片图像分析任务终态与客户端同步失效事件。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class PhotoAiTaskCompletionService {

    private final TaskRecordService taskRecordService;
    private final MediaSyncEventService syncEventService;

    /**
     * 在同一事务中完成任务并记录照片结果失效事件。
     *
     * @param taskId 任务标识
     * @param ownerUserId 所属用户标识
     * @param mode 任务模式
     * @param result 任务结果
     * @param succeededItems 成功项目数
     * @param failedItems 失败项目数
     */
    @Transactional(rollbackFor = Exception.class)
    public void complete(
            UUID taskId,
            UUID ownerUserId,
            Mode mode,
            Map<String, Object> result,
            long succeededItems,
            long failedItems
    ) {
        taskRecordService.markCompleted(taskId, result);
        recordInvalidation(ownerUserId, taskId, mode, succeededItems, failedItems);
    }

    /**
     * 在独立事务中记录兼容消息产生的照片结果失效事件。
     *
     * @param ownerUserId 所属用户标识
     * @param resourceId 资源标识
     * @param mode 任务模式
     * @param succeededItems 成功项目数
     * @param failedItems 失败项目数
     */
    @Transactional(rollbackFor = Exception.class)
    public void invalidate(
            UUID ownerUserId,
            UUID resourceId,
            Mode mode,
            long succeededItems,
            long failedItems
    ) {
        recordInvalidation(ownerUserId, resourceId, mode, succeededItems, failedItems);
    }

    private void recordInvalidation(
            UUID ownerUserId,
            UUID resourceId,
            Mode mode,
            long succeededItems,
            long failedItems
    ) {
        syncEventService.invalidate(
                ownerUserId,
                SyncScope.PHOTOS,
                "PHOTO_AI_RESULTS",
                Map.of(
                        "resourceId", resourceId.toString(),
                        "mode", mode.name(),
                        "succeededItems", succeededItems,
                        "failedItems", failedItems
                )
        );
    }
}
