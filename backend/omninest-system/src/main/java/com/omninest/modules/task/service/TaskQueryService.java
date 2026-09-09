package com.omninest.modules.task.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.dto.TaskDto;
import com.omninest.modules.task.repository.TaskRecordRepository;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 任务查询服务
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TaskQueryService {

    private final TaskRecordRepository taskRecordRepository;
    private final TaskRedispatchService taskRedispatchService;

    /**
     * 查询最近任务列表
     */
    @Transactional(readOnly = true)
    public List<TaskDto> recentTasks() {
        return taskRecordRepository.findAllByOrderByCreatedAtDesc(PageRequest.of(0, 50))
                .stream()
                .map(TaskDto::from)
                .toList();
    }

    /**
     * 按状态查询任务
     */
    @Transactional(readOnly = true)
    public List<TaskDto> tasksByStatus(String status) {
        return taskRecordRepository.findByStatusOrderByCreatedAtDesc(status, PageRequest.of(0, 50))
                .stream()
                .map(TaskDto::from)
                .toList();
    }

    /**
     * 分页查询任务列表，支持可选的状态过滤
     *
     * @param ownerUserId 所属用户 ID
     * @param status 任务状态过滤条件，为 null 或空则查询全部
     * @param pageable 分页参数
     * @return 任务分页结果
     */
    @Transactional(readOnly = true)
    public Page<TaskDto> listOwned(UUID ownerUserId, String status, Pageable pageable) {
        Page<TaskRecord> page;
        if (status != null && !status.isBlank()) {
            page = taskRecordRepository.findByOwnerUserIdAndStatus(ownerUserId, status, pageable);
        } else {
            page = taskRecordRepository.findByOwnerUserId(ownerUserId, pageable);
        }
        return page.map(TaskDto::from);
    }

    /**
     * 查询当前用户拥有的指定任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskId 任务 ID
     * @return 任务信息
     */
    @Transactional(readOnly = true)
    public TaskDto getOwned(UUID ownerUserId, UUID taskId) {
        TaskRecord task = taskRecordRepository.findById(taskId)
                .filter(record -> ownerUserId.equals(record.getOwnerUserId()))
                .orElseThrow(() -> new BusinessException(ErrorCode.TASK_NOT_FOUND, "任务不存在"));
        return TaskDto.from(task);
    }

    /**
     * 查询死信队列中的任务
     *
     * @param limit 最大返回数量
     * @return 死信任务列表
     */
    @Transactional(readOnly = true)
    public List<TaskDto> listDlq(int limit) {
        return taskRecordRepository.findByStatusOrderByCreatedAtDesc(
                        TaskStatus.DLQ.getValue(), PageRequest.of(0, limit))
                .stream()
                .map(TaskDto::from)
                .toList();
    }

    /**
     * 重试死信队列中的任务。
     *
     * <p>除重置状态外，还必须按记录重建载荷并经 Outbox 重新投递；只改状态
     * 不投递会让任务永远停留在 QUEUED。</p>
     *
     * @param taskId 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void retryDlqEntry(UUID taskId) {
        TaskRecord task = taskRecordRepository.findById(taskId)
                .orElseThrow(() -> new BusinessException(ErrorCode.TASK_NOT_FOUND, "任务不存在"));
        if (!TaskStatus.DLQ.getValue().equals(task.getStatus())) {
            throw new BusinessException(ErrorCode.TASK_STATUS_ILLEGAL, "仅可重试死信队列中的任务");
        }
        task.setStatus(TaskStatus.QUEUED.getValue());
        task.setRetryCount(0);
        task.setErrorMessage(null);
        taskRecordRepository.save(task);
        taskRedispatchService.redispatch(task);
        log.info("重试死信任务并重新投递: taskId={}, taskType={}", taskId, task.getTaskType());
    }
}
