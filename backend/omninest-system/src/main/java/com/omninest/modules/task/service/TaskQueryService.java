package com.omninest.modules.task.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.dto.TaskDto;
import com.omninest.modules.task.dto.TaskSummaryDto;
import com.omninest.modules.task.repository.TaskRecordRepository;
import java.time.Duration;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 任务查询服务
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TaskQueryService {

    /** 单用户主动重试的额度：窗口内允许的次数。 */
    private static final int RETRY_LIMIT = 10;
    private static final Duration RETRY_LIMIT_WINDOW = Duration.ofMinutes(5);
    private static final String RETRY_LIMIT_KEY_PREFIX = "task:retry:";

    private final TaskRecordRepository taskRecordRepository;
    private final TaskRedispatchService taskRedispatchService;
    private final RateLimitService rateLimitService;

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
        Pageable ordered = withDefaultOrder(pageable);
        Page<TaskRecord> page;
        if (status != null && !status.isBlank()) {
            page = taskRecordRepository.findByOwnerUserIdAndStatus(ownerUserId, status, ordered);
        } else {
            page = taskRecordRepository.findByOwnerUserId(ownerUserId, ordered);
        }
        return page.map(TaskDto::from);
    }

    /**
     * 请求未指定排序时按创建时间倒序。
     *
     * <p>数据库不分页有序会让同一查询两次翻页的结果抖动，摘要里的"优先展示任务"
     * 也会取到物理页顺序上的任意旧任务而不是最近任务。</p>
     */
    private Pageable withDefaultOrder(Pageable pageable) {
        if (pageable.getSort().isSorted()) {
            return pageable;
        }
        return PageRequest.of(pageable.getPageNumber(), pageable.getPageSize(),
                Sort.by(Sort.Direction.DESC, "createdAt"));
    }

    /**
     * 本人任务轻量摘要：统计进行中/失败数量并选出优先展示任务。
     *
     * <p>不返回堆栈；用于 Portal 角标，GUEST 等无 task:read 的角色可调用。</p>
     */
    @Transactional(readOnly = true)
    public TaskSummaryDto summaryOwned(UUID ownerUserId) {
        List<String> activeStatuses = List.of(
                TaskStatus.QUEUED.getValue(),
                TaskStatus.RUNNING.getValue(),
                TaskStatus.RETRY_WAIT.getValue()
        );
        List<String> failedStatuses = List.of(
                TaskStatus.FAILED.getValue(),
                TaskStatus.DLQ.getValue()
        );
        long active = taskRecordRepository.countByOwnerUserIdAndStatusIn(ownerUserId, activeStatuses);
        long failed = taskRecordRepository.countByOwnerUserIdAndStatusIn(ownerUserId, failedStatuses);
        List<TaskDto> recent = listOwned(ownerUserId, null, PageRequest.of(0, 50))
                .getContent();
        TaskDto priority = recent.stream()
                .filter(task -> failedStatuses.contains(task.status()))
                .findFirst()
                .orElseGet(() -> recent.stream()
                        .filter(task -> TaskStatus.RUNNING.getValue().equals(task.status()))
                        .findFirst()
                        .orElseGet(() -> recent.stream()
                                .filter(task -> activeStatuses.contains(task.status()))
                                .findFirst()
                                .orElse(null)));
        return new TaskSummaryDto(active, failed, priority);
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
     * @param operatorUserId 当前管理员 ID，用于判断是否需要脱敏
     * @return 死信任务列表
     */
    @Transactional(readOnly = true)
    public List<TaskDto> listDlq(int limit, UUID operatorUserId) {
        return taskRecordRepository.findByStatusOrderByCreatedAtDesc(
                        TaskStatus.DLQ.getValue(), PageRequest.of(0, limit))
                .stream()
                .map(record -> TaskDto.fromForAdmin(record, operatorUserId))
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

    /**
     * 本人任务重试。
     *
     * <p>仅允许当前用户对本人 FAILED 任务重新入队；死信（DLQ）仍走管理端
     * {@link #retryDlqEntry(UUID)}。除重置状态外必须经 Outbox 重新投递。</p>
     *
     * @param ownerUserId 所属用户 ID
     * @param taskId 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void retryOwned(UUID ownerUserId, UUID taskId) {
        requireRetryBudget(ownerUserId);
        TaskRecord task = taskRecordRepository.findById(taskId)
                .filter(record -> ownerUserId.equals(record.getOwnerUserId()))
                .orElseThrow(() -> new BusinessException(ErrorCode.TASK_NOT_FOUND, "任务不存在"));
        if (!TaskStatus.FAILED.getValue().equals(task.getStatus())) {
            throw new BusinessException(ErrorCode.TASK_STATUS_ILLEGAL, "仅可重试失败状态的本人任务");
        }
        task.setStatus(TaskStatus.QUEUED.getValue());
        task.setRetryCount(0);
        task.setErrorMessage(null);
        task.setStackSummary(null);
        taskRecordRepository.save(task);
        taskRedispatchService.redispatch(task);
        log.info("本人任务重试并重新投递: taskId={}, taskType={}", taskId, task.getTaskType());
    }

    /**
     * 限制单个用户的主动重试频率。
     *
     * <p>重试会把 {@code retryCount} 归零并重新投递，等于绕开"默认最多 3 次重试"的重试阶梯；
     * 转码/刮削/解析都是高成本任务，没频率闸门就能被无限重放。AGENTS 要求这类入口走
     * Redis + Lua 限流，额度与登录档同量级。
     */
    private void requireRetryBudget(UUID ownerUserId) {
        if (!rateLimitService.tryAcquire(
                RETRY_LIMIT_KEY_PREFIX + ownerUserId, RETRY_LIMIT, RETRY_LIMIT_WINDOW)) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "任务重试过于频繁，请稍后再试");
        }
    }
}
