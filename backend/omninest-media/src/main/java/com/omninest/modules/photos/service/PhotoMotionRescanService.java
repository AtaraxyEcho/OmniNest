package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.event.PhotoMotionRescanEvent;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

/**
 * 动态照片存量回扫任务服务：创建回扫任务、分批检测并就地提取运动视频。
 *
 * <p>回扫只处理尚无运动状态的可解码 JPEG；重启与重试天然幂等，
 * 已置 DETECTED/READY 的照片会被候选查询排除。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoMotionRescanService {

    /** 任务类型标识。 */
    public static final String TASK_TYPE = "PHOTO_MOTION_RESCAN";
    private static final String PHASE_SCANNING = "SCANNING";
    private static final int BATCH_SIZE = 50;
    private static final int MAX_RETRIES = 3;

    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final PhotoItemRepository photoItemRepository;
    private final PhotoSourceFileService photoSourceFileService;
    private final PhotoMotionVideoService photoMotionVideoService;

    /**
     * 创建动态照片回扫任务；同一用户已有进行中的回扫任务时返回既有任务。
     *
     * @param ownerUserId 照片所有者
     * @return 任务 ID
     */
    public UUID enqueueRescan(UUID ownerUserId) {
        Optional<TaskRecord> active = taskRecordService.findActiveResourceTask(
                ownerUserId,
                TASK_TYPE,
                "USER",
                ownerUserId,
                List.of("QUEUED", "RUNNING", "RETRY_WAIT")
        );
        if (active.isPresent()) {
            return active.get().getId();
        }
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                TASK_TYPE,
                QueueNames.PHOTO_MOTION_RESCAN_ROUTING_KEY,
                "PENDING",
                "USER",
                ownerUserId,
                Map.of("ownerUserId", ownerUserId.toString())
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_MOTION_RESCAN_ROUTING_KEY,
                new PhotoMotionRescanEvent(taskId, ownerUserId)
        );
        return taskId;
    }

    /**
     * 执行回扫任务（由 Worker 消费者调用）。
     *
     * @param taskId 任务 ID
     */
    public void executeRescanTask(UUID taskId) {
        Map<String, Object> payload = taskRecordService.taskPayload(taskId);
        UUID ownerUserId = uuid(payload.get("ownerUserId"));
        if (ownerUserId == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "回扫任务缺少所有者");
        }
        if (!taskRecordService.claimForExecution(taskId, PHASE_SCANNING)) {
            return;
        }
        long total = Math.max(photoItemRepository.countMotionRescanCandidates(ownerUserId), 1);
        UUID cursor = null;
        long scanned = 0;
        long detected = 0;
        try {
            while (true) {
                if (taskRecordService.isCancelled(taskId)) {
                    taskRecordService.markCancelled(taskId);
                    log.info("动态照片回扫任务已取消: taskId={}", taskId);
                    return;
                }
                List<PhotoItem> batch = photoItemRepository.findMotionRescanCandidates(
                        ownerUserId, cursor, PageRequest.of(0, BATCH_SIZE));
                if (batch.isEmpty()) {
                    break;
                }
                for (PhotoItem photo : batch) {
                    cursor = photo.getId();
                    scanned++;
                    if (processPhoto(ownerUserId, photo.getFileNodeId())) {
                        detected++;
                    }
                }
                taskRecordService.updateExecution(
                        taskId,
                        PHASE_SCANNING,
                        (int) Math.min(99, scanned * 100 / total)
                );
                if (batch.size() < BATCH_SIZE) {
                    break;
                }
            }
            taskRecordService.markCompleted(taskId, Map.of("scanned", scanned, "detected", detected));
            log.info("动态照片回扫完成: taskId={}, scanned={}, detected={}", taskId, scanned, detected);
        } catch (RuntimeException ex) {
            handleRescanFailure(taskId, ownerUserId, ex);
        }
    }

    private boolean processPhoto(UUID ownerUserId, UUID fileNodeId) {
        try (PhotoSourceFileService.StagedPhotoFile source =
                     photoSourceFileService.stageReadable(ownerUserId, fileNodeId)) {
            if (!photoMotionVideoService.detectAndMark(ownerUserId, fileNodeId, source.path())) {
                return false;
            }
            photoMotionVideoService.extractAndStore(ownerUserId, fileNodeId, source.path());
            return true;
        } catch (BusinessException ex) {
            log.warn("动态照片回扫单张失败，跳过: fileNodeId={}, error={}", fileNodeId, ex.getMessage());
            return false;
        } catch (Exception ex) {
            log.warn("动态照片回扫单张异常，跳过: fileNodeId={}", fileNodeId, ex);
            return false;
        }
    }

    private void handleRescanFailure(UUID taskId, UUID ownerUserId, RuntimeException exception) {
        String errorSummary = exception instanceof BusinessException businessException
                ? businessException.errorCode().name()
                : exception.getClass().getSimpleName();
        if (taskRecordService.retryCount(taskId) >= MAX_RETRIES) {
            taskRecordService.markDeadLetter(taskId, errorSummary);
            log.error("动态照片回扫任务达到最大重试次数并进入死信: taskId={}", taskId);
            return;
        }
        Duration delay = switch (taskRecordService.retryCount(taskId) + 1) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
        Instant nextRetryAt = Instant.now().plus(delay);
        taskRecordService.markRetryWait(taskId, errorSummary, nextRetryAt);
        taskDispatchService.enqueueAt(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_MOTION_RESCAN_ROUTING_KEY,
                new PhotoMotionRescanEvent(taskId, ownerUserId),
                nextRetryAt
        );
        log.warn("动态照片回扫任务等待重试: taskId={}, nextRetryAt={}, errorType={}",
                taskId, nextRetryAt, errorSummary);
    }

    private UUID uuid(Object value) {
        if (value instanceof String text && !text.isBlank()) {
            try {
                return UUID.fromString(text);
            } catch (IllegalArgumentException ignored) {
                // 载荷格式异常按空处理
            }
        }
        return null;
    }
}
