package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthActiveSession;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 活跃会话仓储
 *
 * @author OmniNest
 */
public interface ActiveSessionRepository extends JpaRepository<AuthActiveSession, UUID> {

    /**
     * 查询用户未撤销的会话列表。
     */
    List<AuthActiveSession> findByUserIdAndRevokedAtIsNullOrderByCreatedAtDesc(UUID userId);

    /**
     * 查询多个用户尚未撤销的会话。
     */
    List<AuthActiveSession> findByUserIdInAndRevokedAtIsNull(Collection<UUID> userIds);

    /**
     * 查询用户指定平台未撤销的会话。
     */
    List<AuthActiveSession> findByUserIdAndClientPlatformAndRevokedAtIsNull(
            UUID userId, String clientPlatform);

    /**
     * 按创建时间从新到旧查询会话。
     *
     * @param pageable 分页参数
     * @return 会话列表
     */
    List<AuthActiveSession> findAllByOrderByCreatedAtDesc(Pageable pageable);

    /**
     * 按管理端筛选条件分页查询会话。
     *
     * @param status 会话状态，空字符串表示不限
     * @param platform 客户端平台，空字符串表示不限
     * @param searchPattern 模糊搜索模式，空字符串表示不限
     * @param now 当前时间，用于区分活跃和过期会话
     * @param pageable 分页参数
     * @return 会话分页结果
     */
    @Query(value = """
            select session from AuthActiveSession session, AuthUser user
            where user.id = session.userId
              and (
                :status = ''
                or (:status = 'ACTIVE' and session.revokedAt is null and session.expiresAt >= :now)
                or (:status = 'REVOKED' and session.revokedAt is not null)
                or (:status = 'EXPIRED' and session.revokedAt is null and session.expiresAt < :now)
              )
              and (:platform = '' or lower(session.clientPlatform) = :platform)
              and (
                :searchPattern = ''
                or lower(user.username) like :searchPattern
                or lower(coalesce(session.deviceName, '')) like :searchPattern
                or lower(coalesce(session.deviceId, '')) like :searchPattern
                or lower(coalesce(session.ipAddress, '')) like :searchPattern
              )
            """,
            countQuery = """
                    select count(session) from AuthActiveSession session, AuthUser user
                    where user.id = session.userId
                      and (
                        :status = ''
                        or (:status = 'ACTIVE' and session.revokedAt is null and session.expiresAt >= :now)
                        or (:status = 'REVOKED' and session.revokedAt is not null)
                        or (:status = 'EXPIRED' and session.revokedAt is null and session.expiresAt < :now)
                      )
                      and (:platform = '' or lower(session.clientPlatform) = :platform)
                      and (
                        :searchPattern = ''
                        or lower(user.username) like :searchPattern
                        or lower(coalesce(session.deviceName, '')) like :searchPattern
                        or lower(coalesce(session.deviceId, '')) like :searchPattern
                        or lower(coalesce(session.ipAddress, '')) like :searchPattern
                      )
                    """)
    Page<AuthActiveSession> searchAdminSessions(
            @Param("status") String status,
            @Param("platform") String platform,
            @Param("searchPattern") String searchPattern,
            @Param("now") Instant now,
            Pageable pageable
    );

    /**
     * 通过会话 ID 撤销会话。
     */
    @Modifying
    @Query("UPDATE AuthActiveSession s SET s.revokedAt = CURRENT_TIMESTAMP, s.revokeReason = :reason " +
           "WHERE s.id = :sessionId AND s.revokedAt IS NULL")
    int revokeBySessionId(@Param("sessionId") UUID sessionId, @Param("reason") String reason);

    /**
     * 撤销用户指定平台的所有会话（排除指定会话）。
     */
    @Modifying
    @Query("UPDATE AuthActiveSession s SET s.revokedAt = CURRENT_TIMESTAMP, s.revokeReason = :reason " +
           "WHERE s.userId = :userId AND s.clientPlatform = :platform " +
           "AND s.id != :excludeSessionId AND s.revokedAt IS NULL")
    int revokeByUserAndPlatformExcluding(
            @Param("userId") UUID userId,
            @Param("platform") String platform,
            @Param("excludeSessionId") UUID excludeSessionId,
            @Param("reason") String reason);

    /**
     * 批量撤销多个用户的全部活跃会话。
     */
    @Modifying
    @Query("UPDATE AuthActiveSession s SET s.revokedAt = CURRENT_TIMESTAMP, s.revokeReason = :reason " +
           "WHERE s.userId IN :userIds AND s.revokedAt IS NULL")
    int revokeByUserIdIn(
            @Param("userIds") Collection<UUID> userIds,
            @Param("reason") String reason);

    /**
     * 通过会话 ID 查询（含已撤销）。
     */
    Optional<AuthActiveSession> findByIdAndUserId(UUID sessionId, UUID userId);

    /**
     * 清理截止时间之前已撤销或已过期的会话。
     *
     * @param cutoff 截止时间
     * @return 删除数量
     */
    @Modifying
    @Query("delete from AuthActiveSession session "
            + "where (session.revokedAt is not null and session.revokedAt < :cutoff) "
            + "or session.expiresAt < :cutoff")
    int deleteInactiveBefore(@Param("cutoff") Instant cutoff);

    /**
     * 删除用户全部会话记录，供管理端物理删除空账户使用。
     *
     * @param userId 用户标识
     * @return 删除数量
     */
    @Modifying
    @Query("delete from AuthActiveSession session where session.userId = :userId")
    int deleteByUserId(@Param("userId") UUID userId);

    /**
     * 统计截止时间之前已撤销或已过期的会话数量，谓词与 deleteInactiveBefore 保持一致。
     *
     * @param cutoff 截止时间
     * @return 会话数量
     */
    @Query("select count(session) from AuthActiveSession session "
            + "where (session.revokedAt is not null and session.revokedAt < :cutoff) "
            + "or session.expiresAt < :cutoff")
    long countInactiveBefore(@Param("cutoff") Instant cutoff);
}
