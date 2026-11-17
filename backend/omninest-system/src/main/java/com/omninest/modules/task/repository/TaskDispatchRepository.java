package com.omninest.modules.task.repository;

import com.omninest.modules.task.domain.TaskDispatch;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 任务 Outbox 仓储。
 *
 * @author OmniNest
 */
public interface TaskDispatchRepository extends JpaRepository<TaskDispatch, UUID> {

    /**
     * 查询任务最近一次投递记录（心跳恢复重投原始消息用）。
     *
     * @param taskId 任务 ID
     * @return 最近一次投递记录
     */
    Optional<TaskDispatch> findFirstByTaskIdOrderByCreatedAtDesc(UUID taskId);

    /**
     * 批量查询多个任务的全部投递记录，按任务分组、创建时间倒序。
     *
     * <p>清扫器一轮处理上百个停滞任务，逐个查最近投递会退化成上百次单行查询。</p>
     *
     * @param taskIds 任务 ID 集合
     * @return 投递记录，同一任务内按创建时间倒序
     */
    List<TaskDispatch> findByTaskIdInOrderByTaskIdAscCreatedAtDesc(Collection<UUID> taskIds);

    /**
     * 领取超过保留期的已发布记录 ID，供历史清理分批删除。
     *
     * @param cutoff 发布时间截止点
     * @param pageable 批次大小
     * @return 记录 ID 列表
     */
    @Query("""
            select dispatch.id from TaskDispatch dispatch
            where dispatch.status = 'PUBLISHED' and dispatch.publishedAt < :cutoff
            order by dispatch.publishedAt asc
            """)
    List<UUID> findPublishedIdsBefore(@Param("cutoff") Instant cutoff, Pageable pageable);

    /**
     * 悲观锁领取可发布记录。
     *
     * @param now 当前时间
     * @param limit 批次限制
     * @return 可领取记录
     */
    @Query(value = """
            SELECT dispatch.id,
                   dispatch.task_id,
                   dispatch.exchange_name,
                   dispatch.routing_key,
                   dispatch.payload,
                   dispatch.status,
                   dispatch.attempt_count,
                   dispatch.next_attempt_at,
                   dispatch.locked_by,
                   dispatch.locked_until,
                   dispatch.published_at,
                   dispatch.last_error_code,
                   dispatch.created_at,
                   dispatch.updated_at,
                   dispatch.version
            FROM omni.sys_task_dispatches dispatch
            WHERE (dispatch.status = 'PENDING' AND dispatch.next_attempt_at <= :now)
               OR (dispatch.status = 'PUBLISHING' AND dispatch.locked_until < :now)
            ORDER BY dispatch.created_at ASC
            LIMIT :limit
            FOR UPDATE SKIP LOCKED
            """, nativeQuery = true)
    List<TaskDispatch> findClaimable(@Param("now") Instant now, @Param("limit") int limit);

    /**
     * 将当前实例租约内的一批记录标记为已发布。
     *
     * <p>整批共用一次事务：逐条更新会让 100 条消息产生 100 次连接获取与提交，
     * 在调度周期内直接吃掉连接池配额。</p>
     *
     * @param dispatchIds 投递记录 ID 集合
     * @param instanceId 实例 ID
     * @param publishedAt 发布时间
     * @return 更新行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update TaskDispatch dispatch
            set dispatch.status = 'PUBLISHED',
                dispatch.publishedAt = :publishedAt,
                dispatch.lockedBy = null,
                dispatch.lockedUntil = null,
                dispatch.lastErrorCode = null,
                dispatch.updatedAt = :publishedAt,
                dispatch.version = dispatch.version + 1
            where dispatch.id in :dispatchIds
            and dispatch.status = 'PUBLISHING'
            and dispatch.lockedBy = :instanceId
            """)
    int markPublishedBatch(
            @Param("dispatchIds") Collection<UUID> dispatchIds,
            @Param("instanceId") String instanceId,
            @Param("publishedAt") Instant publishedAt
    );

    /**
     * 将发布失败记录恢复为待发布状态。
     *
     * @param dispatchId 投递记录 ID
     * @param instanceId 实例 ID
     * @param attempts 尝试次数
     * @param nextAttemptAt 下次发布时间
     * @param errorCode 错误码
     * @param updatedAt 更新时间
     * @return 更新行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update TaskDispatch dispatch
            set dispatch.status = 'PENDING',
                dispatch.attemptCount = :attempts,
                dispatch.nextAttemptAt = :nextAttemptAt,
                dispatch.lockedBy = null,
                dispatch.lockedUntil = null,
                dispatch.lastErrorCode = :errorCode,
                dispatch.updatedAt = :updatedAt,
                dispatch.version = dispatch.version + 1
            where dispatch.id = :dispatchId
            and dispatch.status = 'PUBLISHING'
            and dispatch.lockedBy = :instanceId
            """)
    int markFailed(
            @Param("dispatchId") UUID dispatchId,
            @Param("instanceId") String instanceId,
            @Param("attempts") int attempts,
            @Param("nextAttemptAt") Instant nextAttemptAt,
            @Param("errorCode") String errorCode,
            @Param("updatedAt") Instant updatedAt
    );

    /**
     * 在死信获得确认后结束原投递记录并保留原始错误码。
     *
     * @param dispatchId 投递记录 ID
     * @param instanceId 实例 ID
     * @param attempts 总尝试次数
     * @param publishedAt 死信发布时间
     * @param errorCode 原始错误码
     * @return 更新行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update TaskDispatch dispatch
            set dispatch.status = 'PUBLISHED',
                dispatch.attemptCount = :attempts,
                dispatch.publishedAt = :publishedAt,
                dispatch.lockedBy = null,
                dispatch.lockedUntil = null,
                dispatch.lastErrorCode = :errorCode,
                dispatch.updatedAt = :publishedAt,
                dispatch.version = dispatch.version + 1
            where dispatch.id = :dispatchId
            and dispatch.status = 'PUBLISHING'
            and dispatch.lockedBy = :instanceId
            """)
    int markDeadLetterPublished(
            @Param("dispatchId") UUID dispatchId,
            @Param("instanceId") String instanceId,
            @Param("attempts") int attempts,
            @Param("publishedAt") Instant publishedAt,
            @Param("errorCode") String errorCode
    );
}
