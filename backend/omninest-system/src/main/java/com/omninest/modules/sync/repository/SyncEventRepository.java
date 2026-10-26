package com.omninest.modules.sync.repository;

import com.omninest.modules.sync.domain.SyncEvent;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 用户同步事件仓储。
 *
 * @author OmniNest
 */
public interface SyncEventRepository extends JpaRepository<SyncEvent, UUID> {

    /**
     * 查询指定全局游标区间内当前用户可见的事件。
     *
     * @param recipientUserId 接收用户标识
     * @param after 起始游标，不包含
     * @param latest 截止游标，包含
     * @param pageable 分页限制
     * @return 按全局序号升序排列的事件
     */
    @Query("""
            select event from SyncEvent event
            where event.recipientUserId = :recipientUserId
            and event.sequenceNo > :after
            and event.sequenceNo <= :latest
            order by event.sequenceNo asc
            """)
    List<SyncEvent> findVisibleEvents(
            @Param("recipientUserId") UUID recipientUserId,
            @Param("after") long after,
            @Param("latest") long latest,
            Pageable pageable
    );

    /**
     * 查询当前同步事件全局高水位。
     *
     * @return 全局最新序号，无事件时为零
     */
    @Query("select coalesce(max(event.sequenceNo), 0) from SyncEvent event")
    long findLatestSequenceNo();

    /**
     * 跳过其他实例已锁定的记录，获取当前可认领的待发布事件。
     *
     * @param now 当前时间
     * @param limit 批次限制
     * @return 可认领事件
     */
    @Query(value = """
            SELECT event.id,
                   event.sequence_no,
                   event.recipient_user_id,
                   event.scope,
                   event.resource_type,
                   event.resource_id,
                   event.action,
                   event.resource_version,
                   event.payload,
                   event.publish_status,
                   event.publish_attempts,
                   event.available_at,
                   event.locked_by,
                   event.locked_until,
                   event.published_at,
                   event.created_at,
                   event.updated_at,
                   event.version
            FROM omni.sync_events event
            WHERE (event.publish_status = 'PENDING' AND event.available_at <= :now)
               OR (event.publish_status = 'PUBLISHING' AND event.locked_until < :now)
            ORDER BY event.sequence_no ASC
            LIMIT :limit
            FOR UPDATE SKIP LOCKED
            """, nativeQuery = true)
    List<SyncEvent> findClaimableEvents(@Param("now") Instant now, @Param("limit") int limit);

    /**
     * 将指定实例持有租约的事件标记为已发布。
     *
     * @param eventId 事件标识
     * @param instanceId 实例标识
     * @param publishedAt 发布时间
     * @return 更新行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update SyncEvent event
            set event.publishStatus = 'PUBLISHED',
                event.publishedAt = :publishedAt,
                event.lockedBy = null,
                event.lockedUntil = null,
                event.updatedAt = :publishedAt,
                event.version = event.version + 1
            where event.id = :eventId
            and event.publishStatus = 'PUBLISHING'
            and event.lockedBy = :instanceId
            """)
    int markPublished(
            @Param("eventId") UUID eventId,
            @Param("instanceId") String instanceId,
            @Param("publishedAt") Instant publishedAt
    );

    /**
     * 将发布失败事件恢复为待发布状态并设置退避时间。
     *
     * @param eventId 事件标识
     * @param instanceId 实例标识
     * @param attempts 发布尝试次数
     * @param availableAt 下次可发布时间
     * @param updatedAt 更新时间
     * @return 更新行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update SyncEvent event
            set event.publishStatus = 'PENDING',
                event.publishAttempts = :attempts,
                event.availableAt = :availableAt,
                event.lockedBy = null,
                event.lockedUntil = null,
                event.updatedAt = :updatedAt,
                event.version = event.version + 1
            where event.id = :eventId
            and event.publishStatus = 'PUBLISHING'
            and event.lockedBy = :instanceId
            """)
    int markPublishFailed(
            @Param("eventId") UUID eventId,
            @Param("instanceId") String instanceId,
            @Param("attempts") int attempts,
            @Param("availableAt") Instant availableAt,
            @Param("updatedAt") Instant updatedAt
    );

    /**
     * 查询首个不能清理的事件序号，用于限制连续清理前缀。
     *
     * @param cutoff 保留截止时间
     * @return 首个受保护序号，无记录时为空
     */
    @Query("""
            select min(event.sequenceNo) from SyncEvent event
            where event.publishStatus <> 'PUBLISHED'
            or event.createdAt >= :cutoff
            """)
    Long findFirstProtectedSequence(@Param("cutoff") Instant cutoff);

    /**
     * 批量删除达到保留期限的已发布事件。
     *
     * @param cutoff 保留截止时间
     * @param cleanupFloor 本次允许清理的最大序号
     * @return 删除行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            delete from SyncEvent event
            where event.publishStatus = 'PUBLISHED'
            and event.createdAt < :cutoff
            and event.sequenceNo <= :cleanupFloor
            """)
    int deletePublishedBefore(
            @Param("cutoff") Instant cutoff,
            @Param("cleanupFloor") long cleanupFloor
    );
}
