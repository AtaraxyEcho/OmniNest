package com.omninest.modules.task.service;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.TypeReference;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.repository.TaskRecordRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 系统任务记录服务，统一创建和更新通用任务状态。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class TaskRecordService {

    private static final TypeReference<Map<String, Object>> MAP_TYPE = new TypeReference<>() {
    };

    private final TaskRecordRepository taskRecordRepository;
    private final UserSyncEventRecorder syncEventRecorder;

    /**
     * 创建通用任务记录。
     *
     * @param taskId 任务 ID
     * @param ownerUserId 所属用户 ID
     * @param taskType 任务类型
     * @param routingKey 消息路由键
     * @param payload 任务载荷
     * @return 任务记录
     */
    @Transactional(rollbackFor = Exception.class)
    public TaskRecord createQueuedTask(
            UUID taskId,
            UUID ownerUserId,
            String taskType,
            String routingKey,
            Map<String, Object> payload
    ) {
        return createQueuedTask(
                taskId,
                ownerUserId,
                taskType,
                routingKey,
                null,
                null,
                null,
                payload
        );
    }

    /**
     * 创建包含执行阶段和资源定位的通用任务记录。
     *
     * @param taskId 任务 ID
     * @param ownerUserId 所属用户 ID
     * @param taskType 任务类型
     * @param routingKey 消息路由键
     * @param phase 初始阶段
     * @param resourceType 资源类型
     * @param resourceId 资源 ID
     * @param payload 任务载荷
     * @return 任务记录
     */
    @Transactional(rollbackFor = Exception.class)
    public TaskRecord createQueuedTask(
            UUID taskId,
            UUID ownerUserId,
            String taskType,
            String routingKey,
            String phase,
            String resourceType,
            UUID resourceId,
            Map<String, Object> payload
    ) {
        TaskRecord record = new TaskRecord();
        record.setId(taskId);
        record.setOwnerUserId(ownerUserId);
        record.setTaskType(taskType);
        record.setStatus(TaskStatus.QUEUED.getValue());
        record.setProgress(0);
        record.setRoutingKey(routingKey);
        record.setPhase(phase);
        record.setResourceType(resourceType);
        record.setResourceId(resourceId);
        record.setPayload(JSON.toJSONString(payload == null ? new LinkedHashMap<>() : new LinkedHashMap<>(payload)));
        record.setResult(JSON.toJSONString(new LinkedHashMap<>()));
        record.setRetryCount(0);
        record.setMaxRetries(3);
        TaskRecord saved = taskRecordRepository.save(record);
        recordEvent(saved, SyncAction.CREATED);
        return saved;
    }

    /**
     * 标记任务开始运行。
     *
     * @param taskId 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void markRunning(UUID taskId) {
        markRunning(taskId, null);
    }

    /**
     * 标记任务开始运行并更新执行阶段。
     *
     * @param taskId 任务 ID
     * @param phase 执行阶段，为空时保持原值
     */
    @Transactional(rollbackFor = Exception.class)
    public void markRunning(UUID taskId, String phase) {
        TaskRecord record = requireTask(taskId);
        if (isTerminal(record)) {
            return;
        }
        record.setStatus(TaskStatus.RUNNING.getValue());
        if (phase != null && !phase.isBlank()) {
            record.setPhase(phase);
        }
        record.setProgress(Math.max(record.getProgress(), 10));
        record.setErrorMessage(null);
        record.setStartedAt(Instant.now());
        record.setHeartbeatAt(Instant.now());
        record.setNextRetryAt(null);
        taskRecordRepository.save(record);
        recordEvent(record, SyncAction.UPDATED);
    }

    /**
     * 按标识查找任务记录，供重试服务从任务载荷重建消息。
     *
     * @param taskId 任务 ID
     * @return 任务记录
     */
    @Transactional(readOnly = true)
    public Optional<TaskRecord> findTaskRecord(UUID taskId) {
        return taskRecordRepository.findById(taskId);
    }

    /**
     * 原子领取排队或等待重试的任务，避免重复消息并发执行。
     *
     * @param taskId 任务 ID
     * @param phase 初始执行阶段
     * @return 领取成功时返回 true
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean claimForExecution(UUID taskId, String phase) {
        TaskRecord record = taskRecordRepository.findByIdForUpdate(taskId)
                .orElseThrow(() -> new BusinessException(ErrorCode.TASK_NOT_FOUND, "任务不存在"));
        if (!TaskStatus.QUEUED.getValue().equals(record.getStatus())
                && !TaskStatus.RETRY_WAIT.getValue().equals(record.getStatus())) {
            return false;
        }
        Instant now = Instant.now();
        record.setStatus(TaskStatus.RUNNING.getValue());
        record.setPhase(phase);
        record.setProgress(Math.max(record.getProgress(), 10));
        record.setErrorMessage(null);
        record.setStartedAt(record.getStartedAt() == null ? now : record.getStartedAt());
        record.setHeartbeatAt(now);
        record.setNextRetryAt(null);
        taskRecordRepository.save(record);
        recordEvent(record, SyncAction.UPDATED);
        return true;
    }

    /**
     * 标记任务完成。
     *
     * @param taskId 任务 ID
     * @param result 任务结果
     */
    @Transactional(rollbackFor = Exception.class)
    public void markCompleted(UUID taskId, Map<String, Object> result) {
        TaskRecord record = requireTask(taskId);
        if (isTerminal(record)) {
            return;
        }
        record.setStatus(TaskStatus.COMPLETED.getValue());
        record.setProgress(100);
        record.setResult(JSON.toJSONString(result == null ? new LinkedHashMap<>() : new LinkedHashMap<>(result)));
        record.setErrorMessage(null);
        record.setCompletedAt(Instant.now());
        record.setHeartbeatAt(Instant.now());
        record.setNextRetryAt(null);
        taskRecordRepository.save(record);
        recordEvent(record, SyncAction.COMPLETED);
    }

    /**
     * 更新运行中任务的结构化结果和心跳。
     *
     * @param taskId 任务 ID
     * @param result 当前执行结果
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateResult(UUID taskId, Map<String, Object> result) {
        TaskRecord record = requireTask(taskId);
        if (isTerminal(record)) {
            return;
        }
        record.setResult(JSON.toJSONString(result == null ? new LinkedHashMap<>() : new LinkedHashMap<>(result)));
        record.setHeartbeatAt(Instant.now());
        taskRecordRepository.save(record);
    }

    /**
     * 查询任务结构化结果。
     *
     * @param taskId 任务 ID
     * @return 结构化结果，空值或非法 JSON 返回空映射
     */
    @Transactional(readOnly = true)
    public Map<String, Object> taskResult(UUID taskId) {
        return Map.copyOf(parsePayload(requireTask(taskId).getResult()));
    }

    /**
     * 查询任务结构化载荷。
     *
     * @param taskId 任务 ID
     * @return 结构化载荷，空值或非法 JSON 返回空映射
     */
    @Transactional(readOnly = true)
    public Map<String, Object> taskPayload(UUID taskId) {
        return Map.copyOf(parsePayload(requireTask(taskId).getPayload()));
    }

    /**
     * 查询任务当前执行阶段。
     *
     * @param taskId 任务 ID
     * @return 执行阶段，未设置时返回 null
     */
    @Transactional(readOnly = true)
    public String taskPhase(UUID taskId) {
        return requireTask(taskId).getPhase();
    }

    /**
     * 查询指定任务类型下处于活跃状态的任务标识（跨用户，用于全局任务去重）。
     *
     * @param taskType 任务类型
     * @param statuses 活跃状态集合
     * @return 活跃任务标识
     */
    @Transactional(readOnly = true)
    public List<UUID> findActiveTaskIdsByType(String taskType, Collection<String> statuses) {
        return taskRecordRepository.findIdsByTaskTypeAndStatusIn(taskType, statuses);
    }

    /**
     * 标记任务失败。
     *
     * @param taskId 任务 ID
     * @param errorMessage 错误摘要
     */
    @Transactional(rollbackFor = Exception.class)
    public void markFailed(UUID taskId, String errorMessage) {
        markFailed(taskId, errorMessage, null);
    }

    /**
     * 标记任务失败并记录错误与堆栈摘要。
     *
     * @param taskId 任务 ID
     * @param errorMessage 错误摘要
     * @param stackSummary 脱敏截断后的堆栈摘要，可为 null
     */
    @Transactional(rollbackFor = Exception.class)
    public void markFailed(UUID taskId, String errorMessage, String stackSummary) {
        TaskRecord record = requireTask(taskId);
        if (isTerminal(record)) {
            return;
        }
        record.setStatus(TaskStatus.FAILED.getValue());
        record.setErrorMessage(errorMessage);
        record.setStackSummary(stackSummary);
        record.setCompletedAt(Instant.now());
        taskRecordRepository.save(record);
        recordEvent(record, SyncAction.FAILED);
    }

    /**
     * 将存在的任务标记为已进入死信队列。
     *
     * @param taskId 任务 ID
     * @param errorMessage 错误摘要
     * @return 任务存在并完成更新时返回 true
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean markDeadLetter(UUID taskId, String errorMessage) {
        return markDeadLetter(taskId, errorMessage, null);
    }

    /**
     * 将任务标记为死信，并保留脱敏后的堆栈摘要。
     *
     * @param taskId 任务 ID
     * @param errorMessage 错误摘要
     * @param stackSummary 脱敏堆栈摘要，可为 null
     * @return 任务存在并完成更新时返回 true
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean markDeadLetter(UUID taskId, String errorMessage, String stackSummary) {
        TaskRecord record = taskRecordRepository.findById(taskId).orElse(null);
        if (record == null || isTerminal(record)) {
            return false;
        }
        record.setStatus(TaskStatus.DLQ.getValue());
        record.setErrorMessage(errorMessage);
        record.setStackSummary(stackSummary);
        record.setCompletedAt(Instant.now());
        record.setNextRetryAt(null);
        taskRecordRepository.save(record);
        recordEvent(record, SyncAction.FAILED);
        return true;
    }

    /**
     * 标记任务已取消。
     *
     * @param taskId 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void markCancelled(UUID taskId) {
        TaskRecord record = requireTask(taskId);
        if (isTerminal(record)) {
            return;
        }
        record.setStatus(TaskStatus.CANCELLED.getValue());
        record.setErrorMessage(null);
        record.setCompletedAt(Instant.now());
        taskRecordRepository.save(record);
        recordEvent(record, SyncAction.UPDATED);
    }

    /**
     * 判断任务是否已经被取消，供长任务在进度边界执行协作式中断。
     *
     * @param taskId 任务 ID
     * @return 任务存在且状态为已取消时返回 true
     */
    @Transactional(readOnly = true)
    public boolean isCancelled(UUID taskId) {
        return taskRecordRepository.findById(taskId)
                .map(record -> TaskStatus.CANCELLED.getValue().equals(record.getStatus()))
                .orElse(false);
    }

    /**
     * 更新任务进度。
     *
     * <p>进度写入同时刷新心跳：转码、下载、导入等长任务在耗时阶段只推进
     * 进度，若心跳冻结会被心跳恢复调度误判死亡并重投，造成同一任务双跑。</p>
     *
     * @param taskId 任务 ID
     * @param progress 进度值
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateProgress(UUID taskId, int progress) {
        TaskRecord record = requireTask(taskId);
        if (isTerminal(record)) {
            return;
        }
        int previousProgress = record.getProgress();
        int normalizedProgress = Math.max(0, Math.min(100, progress));
        record.setProgress(normalizedProgress);
        record.setHeartbeatAt(Instant.now());
        taskRecordRepository.save(record);
        if (progressBucket(previousProgress) != progressBucket(normalizedProgress) || normalizedProgress == 100) {
            recordEvent(record, SyncAction.PROGRESS);
        }
    }

    /**
     * 更新任务阶段、进度和心跳。
     *
     * @param taskId 任务 ID
     * @param phase 执行阶段
     * @param progress 进度值
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateExecution(UUID taskId, String phase, int progress) {
        TaskRecord record = requireTask(taskId);
        if (isTerminal(record)) {
            return;
        }
        record.setPhase(phase);
        record.setProgress(Math.max(0, Math.min(100, progress)));
        record.setHeartbeatAt(Instant.now());
        taskRecordRepository.save(record);
        recordEvent(record, SyncAction.PROGRESS);
    }

    /**
     * 将任务置为等待重试。
     *
     * @param taskId 任务 ID
     * @param errorMessage 错误摘要
     * @param nextRetryAt 下次重试时间
     * @return 更新后的重试次数
     */
    @Transactional(rollbackFor = Exception.class)
    public int markRetryWait(UUID taskId, String errorMessage, Instant nextRetryAt) {
        TaskRecord record = requireTask(taskId);
        if (isTerminal(record)) {
            return record.getRetryCount();
        }
        int retryCount = record.getRetryCount() + 1;
        record.setRetryCount(retryCount);
        record.setStatus(TaskStatus.RETRY_WAIT.getValue());
        record.setErrorMessage(errorMessage);
        record.setNextRetryAt(nextRetryAt);
        record.setHeartbeatAt(Instant.now());
        taskRecordRepository.save(record);
        recordEvent(record, SyncAction.UPDATED);
        return retryCount;
    }

    /**
     * 查询指定资源的活跃任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskType 任务类型
     * @param resourceType 资源类型
     * @param resourceId 资源 ID
     * @param statuses 活跃状态
     * @return 最近活跃任务
     */
    @Transactional(readOnly = true)
    public Optional<TaskRecord> findActiveResourceTask(
            UUID ownerUserId,
            String taskType,
            String resourceType,
            UUID resourceId,
            Collection<String> statuses
    ) {
        return taskRecordRepository
                .findFirstByOwnerUserIdAndTaskTypeAndResourceTypeAndResourceIdAndStatusInOrderByUpdatedAtDesc(
                        ownerUserId,
                        taskType,
                        resourceType,
                        resourceId,
                        statuses
                );
    }

    /**
     * 批量取消指定文件资源上的活跃任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param resourceType 资源类型
     * @param resourceIds 资源 ID 集合
     * @param activeStatuses 活跃状态集合
     * @param excludedTaskType 排除的任务类型
     * @return 取消的任务数量
     */
    @Transactional(rollbackFor = Exception.class)
    public int cancelActiveResourceTasks(
            UUID ownerUserId,
            String resourceType,
            Collection<UUID> resourceIds,
            Collection<String> activeStatuses,
            String excludedTaskType
    ) {
        if (resourceIds == null || resourceIds.isEmpty()) {
            return 0;
        }
        return taskRecordRepository.cancelActiveResourceTasks(
                ownerUserId,
                resourceType,
                resourceIds,
                activeStatuses,
                excludedTaskType,
                TaskStatus.CANCELLED.getValue(),
                Instant.now()
        );
    }

    /**
     * 使用独立事务更新长任务进度，使执行中的任务进度可以被其他请求及时读取。
     *
     * @param taskId 任务 ID
     * @param progress 进度值
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public void updateProgressImmediately(UUID taskId, int progress) {
        updateProgress(taskId, progress);
    }

    /**
     * 增加任务重试次数并重新置为排队。
     *
     * @param taskId 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void incrementRetryCount(UUID taskId) {
        TaskRecord record = requireTask(taskId);
        record.setRetryCount(record.getRetryCount() + 1);
        record.setStatus(TaskStatus.QUEUED.getValue());
        record.setErrorMessage(null);
        taskRecordRepository.save(record);
        recordEvent(record, SyncAction.UPDATED);
    }

    /**
     * 查询任务重试次数。
     *
     * @param taskId 任务 ID
     * @return 已重试次数
     */
    @Transactional(readOnly = true)
    public int retryCount(UUID taskId) {
        return requireTask(taskId).getRetryCount();
    }

    /**
     * 查询疑似投递断链的停滞任务：QUEUED 长时间未开始或 RETRY_WAIT 已过
     * 计划重投时间。调用方需结合投递记录存活状态裁决是否重新投递。
     *
     * @param createdAtCutoff QUEUED 创建截止时间
     * @param retryDueCutoff RETRY_WAIT 计划重投截止时间
     * @param limit 批次上限
     * @return 停滞任务记录
     */
    @Transactional(readOnly = true)
    public List<TaskRecord> listStuckTasks(Instant createdAtCutoff, Instant retryDueCutoff, int limit) {
        int safeLimit = Math.max(1, Math.min(limit, 500));
        return taskRecordRepository.findStuckTasks(
                TaskStatus.QUEUED.getValue(),
                TaskStatus.RETRY_WAIT.getValue(),
                createdAtCutoff,
                retryDueCutoff,
                PageRequest.of(0, safeLimit)
        );
    }

    /**
     * 查询心跳超时的运行任务标识。
     *
     * @param taskType 任务类型
     * @param cutoff 心跳截止时间
     * @param limit 批次上限
     * @return 超时任务标识
     */
    @Transactional(readOnly = true)
    public List<UUID> listStaleRunningTaskIds(String taskType, Instant cutoff, int limit) {
        int safeLimit = Math.max(1, Math.min(limit, 500));
        return taskRecordRepository.findStaleRunningTasks(
                        taskType,
                        TaskStatus.RUNNING.getValue(),
                        cutoff,
                        PageRequest.of(0, safeLimit)
                ).stream()
                .map(TaskRecord::getId)
                .toList();
    }

    /**
     * 对心跳超时任务执行带行锁的重试或死信裁决。
     *
     * @param taskId 任务 ID
     * @param taskType 任务类型
     * @param cutoff 心跳截止时间
     * @param now 当前时间
     * @param errorMessage 错误摘要
     * @return 恢复结果
     */
    @Transactional(rollbackFor = Exception.class)
    public StaleTaskRecovery recoverStaleTask(
            UUID taskId,
            String taskType,
            Instant cutoff,
            Instant now,
            String errorMessage
    ) {
        TaskRecord record = taskRecordRepository.findByIdForUpdate(taskId).orElse(null);
        if (record == null
                || !taskType.equals(record.getTaskType())
                || !TaskStatus.RUNNING.getValue().equals(record.getStatus())
                || (record.getHeartbeatAt() != null && !record.getHeartbeatAt().isBefore(cutoff))) {
            return StaleTaskRecovery.ignored();
        }
        if (record.getRetryCount() >= record.getMaxRetries()) {
            record.setStatus(TaskStatus.DLQ.getValue());
            record.setErrorMessage(errorMessage);
            record.setCompletedAt(now);
            record.setNextRetryAt(null);
            taskRecordRepository.save(record);
            recordEvent(record, SyncAction.FAILED);
            return new StaleTaskRecovery(
                    true,
                    true,
                    record.getOwnerUserId(),
                    record.getResourceId(),
                    record.getRetryCount(),
                    null
            );
        }
        int retryCount = record.getRetryCount() + 1;
        Instant nextRetryAt = now.plus(defaultRetryDelay(retryCount));
        record.setRetryCount(retryCount);
        record.setStatus(TaskStatus.RETRY_WAIT.getValue());
        record.setErrorMessage(errorMessage);
        record.setNextRetryAt(nextRetryAt);
        record.setHeartbeatAt(now);
        taskRecordRepository.save(record);
        recordEvent(record, SyncAction.UPDATED);
        return new StaleTaskRecovery(
                true,
                false,
                record.getOwnerUserId(),
                record.getResourceId(),
                retryCount,
                nextRetryAt
        );
    }

    private Duration defaultRetryDelay(int retryCount) {
        return switch (retryCount) {
            case 1 -> Duration.ofMinutes(1);
            case 2 -> Duration.ofMinutes(5);
            default -> Duration.ofMinutes(15);
        };
    }

    /**
     * 查询用户任务列表。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskType 任务类型
     * @param limit 返回数量上限
     * @return 任务列表
     */
    @Transactional(readOnly = true)
    public List<TaskRecord> listTasks(UUID ownerUserId, String taskType, int limit) {
        PageRequest pageRequest = PageRequest.of(0, limit);
        if (taskType == null || taskType.isBlank()) {
            return taskRecordRepository.findByOwnerUserIdOrderByUpdatedAtDesc(ownerUserId, pageRequest);
        }
        return taskRecordRepository.findByOwnerUserIdAndTaskTypeOrderByUpdatedAtDesc(
                ownerUserId,
                taskType,
                pageRequest
        );
    }

    /**
     * 按用户与任务类型白名单查询任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskTypes 任务类型白名单
     * @param limit 返回数量上限
     * @return 任务列表
     */
    @Transactional(readOnly = true)
    public List<TaskRecord> listTasksByTypes(UUID ownerUserId, Collection<String> taskTypes, int limit) {
        if (taskTypes == null || taskTypes.isEmpty()) {
            return List.of();
        }
        PageRequest pageRequest = PageRequest.of(0, limit);
        return taskRecordRepository.findByOwnerUserIdAndTaskTypeInOrderByUpdatedAtDesc(
                ownerUserId,
                taskTypes,
                pageRequest
        );
    }

    /**
     * 判断是否存在指定任务类型和载荷字段的活跃任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskType 任务类型
     * @param payloadKey 载荷字段名
     * @param payloadValue 载荷字段值
     * @param statuses 活跃状态集合
     * @return 是否存在活跃任务
     */
    @Transactional(readOnly = true)
    public boolean hasActiveTaskByPayload(
            UUID ownerUserId,
            String taskType,
            String payloadKey,
            Object payloadValue,
            Collection<String> statuses
    ) {
        String expectedValue = Objects.toString(payloadValue, null);
        if (expectedValue == null) {
            return false;
        }
        List<TaskRecord> activeTasks = taskRecordRepository
                .findByOwnerUserIdAndTaskTypeAndStatusInOrderByUpdatedAtDesc(ownerUserId, taskType, statuses);
        return activeTasks.stream()
                .map(record -> parsePayload(record.getPayload()))
                .anyMatch(payload -> expectedValue.equals(Objects.toString(payload.get(payloadKey), null)));
    }

    /**
     * 查询指定载荷字段匹配的最近任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskType 任务类型
     * @param payloadKey 载荷字段名
     * @param payloadValue 载荷字段值
     * @return 最近任务，不存在时返回空
     */
    @Transactional(readOnly = true)
    public Optional<TaskRecord> findLatestTaskByPayload(
            UUID ownerUserId,
            String taskType,
            String payloadKey,
            Object payloadValue
    ) {
        String expectedValue = Objects.toString(payloadValue, null);
        if (expectedValue == null) {
            return Optional.empty();
        }
        return listTasks(ownerUserId, taskType, 100).stream()
                .filter(record -> expectedValue.equals(
                        Objects.toString(parsePayload(record.getPayload()).get(payloadKey), null)))
                .findFirst();
    }

    /**
     * 分批删除截止时间前已进入终态的任务记录。
     *
     * @param cutoff 截止时间
     * @param batchSize 单批数量
     * @return 删除记录数
     */
    @Transactional(rollbackFor = Exception.class)
    public int deleteTerminalTaskBatchUpdatedBefore(Instant cutoff, int batchSize) {
        List<String> terminalStatuses = List.of(
                TaskStatus.COMPLETED.getValue(),
                TaskStatus.FAILED.getValue(),
                TaskStatus.CANCELLED.getValue()
        );
        int normalizedBatchSize = Math.max(1, Math.min(batchSize, 5000));
        List<UUID> taskIds = taskRecordRepository.findIdsByStatusInAndUpdatedAtBefore(
                terminalStatuses,
                cutoff,
                PageRequest.of(0, normalizedBatchSize)
        );
        if (taskIds.isEmpty()) {
            return 0;
        }
        taskRecordRepository.deleteAllByIdInBatch(taskIds);
        return taskIds.size();
    }

    private TaskRecord requireTask(UUID taskId) {
        return taskRecordRepository.findById(taskId)
                .orElseThrow(() -> new BusinessException(ErrorCode.TASK_NOT_FOUND, "系统任务不存在"));
    }

    private Map<String, Object> parsePayload(String json) {
        if (json == null || json.isBlank()) {
            return new LinkedHashMap<>();
        }
        try {
            Map<String, Object> parsed = JSON.parseObject(json, MAP_TYPE);
            return parsed == null ? new LinkedHashMap<>() : parsed;
        } catch (RuntimeException ex) {
            return new LinkedHashMap<>();
        }
    }

    private int progressBucket(int progress) {
        return Math.max(0, progress) / 5;
    }

    private boolean isTerminal(TaskRecord record) {
        return TaskStatus.fromValue(record.getStatus()).isTerminal();
    }

    private void recordEvent(TaskRecord record, SyncAction action) {
        syncEventRecorder.record(new SyncEventCommand(
                record.getOwnerUserId(),
                SyncScope.TASKS,
                "TASK_" + record.getTaskType(),
                record.getId().toString(),
                action,
                record.getVersion(),
                Map.of(
                        "taskType", record.getTaskType(),
                        "status", record.getStatus(),
                        "progress", record.getProgress()
                )
        ));
    }
}
