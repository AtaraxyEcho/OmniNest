package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthActiveSession;
import com.omninest.modules.user.domain.AuthLoginAudit;
import com.omninest.modules.user.domain.SessionRevocationEntity;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * 认证历史表保留清理所需的窄仓储接口。
 *
 * <p>三张表随登录、登出、同端互斥与角色变更持续增长，且每次受保护请求都要查
 * {@code auth_session_revocations}，不能无限膨胀。按"先取一批 ID、再按 ID 删"的
 * 方式分批提交，避免一次性大删除长时间持锁。</p>
 *
 * @author OmniNest
 */
public interface AuthHistoryRetentionRepository
        extends Repository<SessionRevocationEntity, UUID> {

    /**
     * 查询早于截止时间的会话撤销记录标识。
     *
     * @param cutoff 截止时间
     * @param pageable 批次边界
     * @return 待清理记录标识
     */
    @Query("select r.id from SessionRevocationEntity r where r.revokedAt < :cutoff order by r.revokedAt asc")
    List<UUID> findRevocationIdsBefore(@Param("cutoff") Instant cutoff, Pageable pageable);

    /**
     * 批量删除会话撤销记录。
     *
     * @param ids 记录标识
     * @return 删除行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from SessionRevocationEntity r where r.id in :ids")
    int deleteRevocationsByIds(@Param("ids") Collection<UUID> ids);

    /**
     * 查询过期时间早于截止时间的会话标识。
     *
     * @param cutoff 截止时间
     * @param pageable 批次边界
     * @return 待清理会话标识
     */
    @Query("select s.id from AuthActiveSession s where s.expiresAt < :cutoff order by s.expiresAt asc")
    List<UUID> findSessionIdsExpiredBefore(@Param("cutoff") Instant cutoff, Pageable pageable);

    /**
     * 批量删除过期会话。
     *
     * @param ids 会话标识
     * @return 删除行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from AuthActiveSession s where s.id in :ids")
    int deleteSessionsByIds(@Param("ids") Collection<UUID> ids);

    /**
     * 查询早于截止时间的登录审计标识。
     *
     * @param cutoff 截止时间
     * @param pageable 批次边界
     * @return 待清理审计标识
     */
    @Query("select a.id from AuthLoginAudit a where a.createdAt < :cutoff order by a.createdAt asc")
    List<UUID> findLoginAuditIdsBefore(@Param("cutoff") Instant cutoff, Pageable pageable);

    /**
     * 批量删除登录审计。
     *
     * @param ids 审计标识
     * @return 删除行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from AuthLoginAudit a where a.id in :ids")
    int deleteLoginAuditByIds(@Param("ids") Collection<UUID> ids);
}
