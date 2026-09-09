package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoAiTaskDto;
import com.omninest.modules.photos.event.PhotoAiEvent;
import com.omninest.modules.photos.event.PhotoAiEvent.Mode;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 照片图像分析长任务编排服务，统一管理任务记录、分页执行和结果失效通知。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoAiTaskService {

    public static final String TASK_TYPE_SINGLE = "PHOTO_AI_ANALYSIS";
    public static final String TASK_TYPE_REANALYSIS = "PHOTO_AI_REANALYSIS";
    public static final String TASK_TYPE_RECLUSTER = "PHOTO_AI_RECLUSTER";
    private static final int PAGE_SIZE = 25;
    private static final int MAX_FAILED_PHOTO_SAMPLES = 20;
    private static final List<String> ACTIVE_STATUSES = List.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RUNNING.getValue(),
            TaskStatus.RETRY_WAIT.getValue()
    );

    private final PhotoAiService photoAiService;
    private final PhotoItemRepository photoItemRepository;
    private final PhotosRuntimeConfigService configService;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final PhotoAiTaskCompletionService completionService;

    /**
     * 为新导入照片创建单张分析任务。
     *
     * @param ownerUserId 所属用户标识
     * @param photoId 照片标识
     * @return 任务标识
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID queueSingleAnalysis(UUID ownerUserId, UUID photoId) {
        UUID fileNodeId = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .map(photo -> photo.getFileNodeId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        UUID taskId = UUID.randomUUID();
        Map<String, Object> payload = taskPayload(ownerUserId, Mode.SINGLE_PHOTO, 1L);
        payload.put("photoId", photoId.toString());
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                TASK_TYPE_SINGLE,
                QueueNames.PHOTO_AI_ROUTING_KEY,
                "QUEUED",
                "FILE_NODE",
                fileNodeId,
                payload
        );
        enqueueAnalysisTask(new PhotoAiEvent(taskId, ownerUserId, photoId, Mode.SINGLE_PHOTO));
        return taskId;
    }

    /**
     * 创建当前用户照片库的存量图像分析重分析任务。
     *
     * @param ownerUserId 所属用户标识
     * @return 任务提交结果
     */
    @Transactional(rollbackFor = Exception.class)
    public PhotoAiTaskDto queueLibraryReanalysis(UUID ownerUserId) {
        requireNoActiveTask(ownerUserId, TASK_TYPE_REANALYSIS, Mode.LIBRARY_REANALYSIS);
        long totalItems = photoItemRepository.countByOwnerUserId(ownerUserId);
        return queueLibraryTask(ownerUserId, TASK_TYPE_REANALYSIS, Mode.LIBRARY_REANALYSIS, totalItems);
    }

    /**
     * 创建当前用户已有脸部数据的重新聚类任务。
     *
     * @param ownerUserId 所属用户标识
     * @return 任务提交结果
     */
    @Transactional(rollbackFor = Exception.class)
    public PhotoAiTaskDto queueFaceRecluster(UUID ownerUserId) {
        requireNoActiveTask(ownerUserId, TASK_TYPE_RECLUSTER, Mode.FACE_RECLUSTER);
        return queueLibraryTask(ownerUserId, TASK_TYPE_RECLUSTER, Mode.FACE_RECLUSTER, 0L);
    }

    /**
     * 执行照片图像分析事件并维护通用任务状态。
     *
     * <p>生命周期冲突（源文件已删除或正在删除）在此取消任务；
     * 其余失败的终态裁决（进入等待重试或死信）由 PhotoAiTaskRetryService 处理。</p>
     *
     * @param event 图像分析任务事件
     */
    public void execute(PhotoAiEvent event) {
        if (!configService.isAiEnabled()) {
            cancelDisabledTask(event);
            return;
        }
        if (event.taskId() == null) {
            executeLegacyEvent(event);
            return;
        }
        if (!taskRecordService.claimForExecution(event.taskId(), "AI_ANALYSIS")) {
            return;
        }
        try {
            Mode mode = event.mode() == null ? Mode.SINGLE_PHOTO : event.mode();
            switch (mode) {
                case SINGLE_PHOTO -> executeSingle(event);
                case LIBRARY_REANALYSIS -> executeLibraryReanalysis(event);
                case FACE_RECLUSTER -> executeFaceRecluster(event);
                default -> throw new BusinessException(ErrorCode.BAD_REQUEST, "不支持的照片图像分析任务模式");
            }
        } catch (BusinessException exception) {
            if (isLifecycleCancellation(exception)) {
                taskRecordService.markCancelled(event.taskId());
                log.info("照片源文件已删除或正在永久删除，取消图像分析任务: taskId={}, photoId={}",
                        event.taskId(), event.photoId());
                return;
            }
            throw exception;
        }
    }

    private PhotoAiTaskDto queueLibraryTask(
            UUID ownerUserId,
            String taskType,
            Mode mode,
            long totalItems
    ) {
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                taskType,
                QueueNames.PHOTO_AI_ROUTING_KEY,
                taskPayload(ownerUserId, mode, totalItems)
        );
        enqueueAnalysisTask(new PhotoAiEvent(taskId, ownerUserId, null, mode));
        return new PhotoAiTaskDto(taskId, TaskStatus.QUEUED.getValue(), totalItems);
    }

    private void requireNoActiveTask(UUID ownerUserId, String taskType, Mode mode) {
        if (taskRecordService.hasActiveTaskByPayload(
                ownerUserId,
                taskType,
                "mode",
                mode.name(),
                ACTIVE_STATUSES
        )) {
                throw new BusinessException(ErrorCode.BAD_REQUEST, "相同的照片图像分析任务正在执行");
        }
    }

    private Map<String, Object> taskPayload(UUID ownerUserId, Mode mode, long totalItems) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("ownerUserId", ownerUserId.toString());
        payload.put("mode", mode.name());
        payload.put("totalItems", totalItems);
        return payload;
    }

    private void executeSingle(PhotoAiEvent event) {
        if (event.photoId() == null) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "单张照片图像分析任务缺少照片标识");
        }
        photoAiService.processPhoto(event.ownerUserId(), event.photoId());
        completionService.complete(
                event.taskId(),
                event.ownerUserId(),
                Mode.SINGLE_PHOTO,
                Map.of(
                        "photoId", event.photoId().toString(),
                        "processedItems", 1
                ),
                1L,
                0L
        );
    }

    private void executeLibraryReanalysis(PhotoAiEvent event) {
        long totalItems = photoItemRepository.countByOwnerUserId(event.ownerUserId());
        long processedItems = 0;
        long succeededItems = 0;
        long failedItems = 0;
        int pageNumber = 0;
        int lastProgress = 10;
        List<String> failedPhotoIds = new ArrayList<>();
        Page<UUID> page;
        do {
            page = photoItemRepository.findIdsByOwnerUserId(
                    event.ownerUserId(),
                    PageRequest.of(pageNumber, PAGE_SIZE, Sort.by(Sort.Direction.ASC, "id"))
            );
            for (UUID photoId : page.getContent()) {
                try {
                    photoAiService.processPhoto(event.ownerUserId(), photoId);
                    succeededItems++;
                } catch (BusinessException exception) {
                    if (isLifecycleCancellation(exception)) {
                        log.info("照片已删除或正在永久删除，跳过图像分析重分析: taskId={}, photoId={}",
                                event.taskId(), photoId);
                    } else {
                        failedItems++;
                        recordFailedPhoto(failedPhotoIds, photoId);
                        log.warn(
                                "照片图像分析重分析单项失败: taskId={}, photoId={}, error={}",
                                event.taskId(),
                                photoId,
                                errorSummary(exception)
                        );
                    }
                } catch (RuntimeException exception) {
                    failedItems++;
                    recordFailedPhoto(failedPhotoIds, photoId);
                    log.warn(
                        "照片图像分析重分析单项失败: taskId={}, photoId={}, error={}",
                            event.taskId(),
                            photoId,
                            errorSummary(exception)
                    );
                }
                processedItems++;
                int progress = progressFor(processedItems, totalItems);
                if (progress >= lastProgress + 5) {
                    taskRecordService.updateProgress(event.taskId(), progress);
                    lastProgress = progress;
                }
            }
            pageNumber++;
            taskRecordService.updateResult(
                    event.taskId(),
                    Map.of(
                            "processedItems", processedItems,
                            "succeededItems", succeededItems,
                            "failedItems", failedItems
                    )
            );
        } while (page.hasNext());

        if (failedItems > 0 && succeededItems == 0) {
            throw new IllegalStateException("照片图像分析重分析全部失败");
        }
        photoAiService.clusterFaces(event.ownerUserId());
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("processedItems", processedItems);
        result.put("succeededItems", succeededItems);
        result.put("failedItems", failedItems);
        result.put("failedPhotoIds", failedPhotoIds);
        completionService.complete(
                event.taskId(),
                event.ownerUserId(),
                Mode.LIBRARY_REANALYSIS,
                result,
                succeededItems,
                failedItems
        );
    }

    private void recordFailedPhoto(List<String> failedPhotoIds, UUID photoId) {
        if (failedPhotoIds.size() < MAX_FAILED_PHOTO_SAMPLES) {
            failedPhotoIds.add(photoId.toString());
        }
    }

    private boolean isLifecycleCancellation(BusinessException exception) {
        return ErrorCode.FILE_LIFECYCLE_CONFLICT.equals(exception.errorCode())
                || ErrorCode.FILE_NOT_FOUND.equals(exception.errorCode())
                || ErrorCode.NOT_FOUND.equals(exception.errorCode());
    }

    private void executeFaceRecluster(PhotoAiEvent event) {
        photoAiService.clusterFaces(event.ownerUserId());
        completionService.complete(
                event.taskId(),
                event.ownerUserId(),
                Mode.FACE_RECLUSTER,
                Map.of("reclustered", true),
                0L,
                0L
        );
    }

    private void executeLegacyEvent(PhotoAiEvent event) {
        if (event.photoId() == null) {
            log.warn("忽略缺少任务标识和照片标识的旧版照片图像分析消息");
            return;
        }
        photoAiService.processPhoto(event.ownerUserId(), event.photoId());
        completionService.invalidate(
                event.ownerUserId(),
                event.photoId(),
                Mode.SINGLE_PHOTO,
                1L,
                0L
        );
    }

    private void cancelDisabledTask(PhotoAiEvent event) {
        if (event.taskId() != null) {
            taskRecordService.markCancelled(event.taskId());
        }
        log.info("照片图像分析功能已关闭，取消任务: taskId={}, mode={}", event.taskId(), event.mode());
    }

    private int progressFor(long processedItems, long totalItems) {
        if (totalItems <= 0) {
            return 90;
        }
        return 10 + (int) Math.min(80L, processedItems * 80L / totalItems);
    }

    private String errorSummary(RuntimeException exception) {
        String message = exception.getMessage();
        return message == null || message.isBlank() ? exception.getClass().getSimpleName() : message;
    }

    private void enqueueAnalysisTask(PhotoAiEvent event) {
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                event.taskId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_AI_ROUTING_KEY,
                event
        );
    }
}
