package com.omninest.modules.task.repository;

import com.omninest.modules.task.domain.TaskRecord;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 系统任务记录仓储
 *
 * @author OmniNest
 */
public interface TaskRecordRepository extends JpaRepository<TaskRecord, UUID> {

    /**
     * 使用行锁查询任务。
     *
     * @param id 任务 ID
     * @return 任务记录
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select task from TaskRecord task where task.id = :id")
    Optional<TaskRecord> findByIdForUpdate(@Param("id") UUID id);

    List<TaskRecord> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId, Pageable pageable);

    List<TaskRecord> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId, Pageable pageable);

    List<TaskRecord> findByOwnerUserIdAndTaskTypeOrderByUpdatedAtDesc(
            UUID ownerUserId,
            String taskType,
            Pageable pageable
    );

    List<TaskRecord> findByOwnerUserIdAndTaskTypeAndStatusInOrderByUpdatedAtDesc(
            UUID ownerUserId,
            String taskType,
            Collection<String> statuses
    );

    List<TaskRecord> findByStatusAndOwnerUserIdOrderByCreatedAtDesc(String status, UUID ownerUserId, Pageable pageable);

    List<TaskRecord> findAllByOrderByCreatedAtDesc(Pageable pageable);

    List<TaskRecord> findByStatusOrderByCreatedAtDesc(String status, Pageable pageable);

    /** 按状态分页查询任务 */
    Page<TaskRecord> findByStatus(String status, Pageable pageable);

    /**
     * 分页查询用户任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param pageable 分页参数
     * @return 用户任务分页
     */
    Page<TaskRecord> findByOwnerUserId(UUID ownerUserId, Pageable pageable);

    /**
     * 按状态分页查询用户任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param status 任务状态
     * @param pageable 分页参数
     * @return 用户任务分页
     */
    Page<TaskRecord> findByOwnerUserIdAndStatus(UUID ownerUserId, String status, Pageable pageable);

    /**
     * 按终态和更新时间查询待清理任务标识。
     *
     * @param statuses 终态集合
     * @param cutoff 截止时间
     * @param pageable 批次边界
     * @return 待清理任务标识
     */
    @Query("""
            select t.id from TaskRecord t
            where t.status in :statuses
            and t.updatedAt < :cutoff
            order by t.updatedAt asc
            """)
    List<UUID> findIdsByStatusInAndUpdatedAtBefore(
            @Param("statuses") Collection<String> statuses,
            @Param("cutoff") Instant cutoff,
            Pageable pageable
    );

    @Query("""
            select t from TaskRecord t
            where t.ownerUserId = :ownerUserId
            and t.taskType = :taskType
            and t.status in :statuses
            order by t.updatedAt desc
            """)
    List<TaskRecord> findActiveByOwnerUserIdAndTaskType(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("taskType") String taskType,
            @Param("statuses") Collection<String> statuses
    );

    /**
     * 查询指定任务类型下处于活跃状态的任务标识（跨用户，用于全局任务去重）。
     *
     * @param taskType 任务类型
     * @param statuses 活跃状态集合
     * @return 活跃任务标识
     */
    @Query("""
            select t.id from TaskRecord t
            where t.taskType = :taskType
            and t.status in :statuses
            """)
    List<UUID> findIdsByTaskTypeAndStatusIn(
            @Param("taskType") String taskType,
            @Param("statuses") Collection<String> statuses
    );

    /**
     * 查询资源当前活跃任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param taskType 任务类型
     * @param resourceType 资源类型
     * @param resourceId 资源 ID
     * @param statuses 活跃状态
     * @return 最近活跃任务
     */
    Optional<TaskRecord> findFirstByOwnerUserIdAndTaskTypeAndResourceTypeAndResourceIdAndStatusInOrderByUpdatedAtDesc(
            UUID ownerUserId,
            String taskType,
            String resourceType,
            UUID resourceId,
            Collection<String> statuses
    );

    /**
     * 批量取消指定文件资源上的活跃任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param resourceType 资源类型
     * @param resourceIds 资源 ID 集合
     * @param activeStatuses 活跃状态集合
     * @param excludedTaskType 排除的任务类型
     * @param cancelledStatus 取消状态
     * @param completedAt 完成时间
     * @return 更新数量
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update TaskRecord task
               set task.status = :cancelledStatus,
                   task.errorMessage = null,
                   task.completedAt = :completedAt,
                   task.updatedAt = :completedAt
             where task.ownerUserId = :ownerUserId
               and task.resourceType = :resourceType
               and task.resourceId in :resourceIds
               and task.status in :activeStatuses
               and task.taskType <> :excludedTaskType
            """)
    int cancelActiveResourceTasks(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("resourceType") String resourceType,
            @Param("resourceIds") Collection<UUID> resourceIds,
            @Param("activeStatuses") Collection<String> activeStatuses,
            @Param("excludedTaskType") String excludedTaskType,
            @Param("cancelledStatus") String cancelledStatus,
            @Param("completedAt") Instant completedAt
    );

    /**
     * 查询心跳超时的运行任务。
     *
     * @param taskType 任务类型
     * @param status 运行状态
     * @param cutoff 心跳截止时间
     * @param pageable 批次限制
     * @return 超时任务
     */
    @Query("""
            select task from TaskRecord task
            where task.taskType = :taskType
              and task.status = :status
              and (task.heartbeatAt is null or task.heartbeatAt < :cutoff)
            order by task.updatedAt asc
            """)
    List<TaskRecord> findStaleRunningTasks(
            @Param("taskType") String taskType,
            @Param("status") String status,
            @Param("cutoff") Instant cutoff,
            Pageable pageable
    );

    /**
     * 查询疑似投递断链的停滞任务：QUEUED 长时间未开始，或 RETRY_WAIT 的
     * 计划重投时间早已过期且无存活投递记录。
     *
     * @param queuedStatus 排队状态值
     * @param retryWaitStatus 等待重试状态值
     * @param createdAtCutoff QUEUED 创建截止时间
     * @param retryDueCutoff RETRY_WAIT 计划重投截止时间
     * @param pageable 批次限制
     * @return 停滞任务
     */
    @Query("""
            select task from TaskRecord task
            where (task.status = :queuedStatus and task.createdAt < :createdAtCutoff)
               or (task.status = :retryWaitStatus and task.nextRetryAt < :retryDueCutoff)
            order by task.createdAt asc
            """)
    List<TaskRecord> findStuckTasks(
            @Param("queuedStatus") String queuedStatus,
            @Param("retryWaitStatus") String retryWaitStatus,
            @Param("createdAtCutoff") Instant createdAtCutoff,
            @Param("retryDueCutoff") Instant retryDueCutoff,
            Pageable pageable
    );
}
