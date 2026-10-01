package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthLoginAudit;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 登录审计仓储
 *
 * @author OmniNest
 */
public interface AuthLoginAuditRepository extends JpaRepository<AuthLoginAudit, UUID> {

    /**
     * 查询指定用户最近的登录审计记录。
     *
     * @param userId 用户 ID
     * @param pageable 分页参数
     * @return 登录审计记录列表
     */
    List<AuthLoginAudit> findByUserIdOrderByCreatedAtDesc(UUID userId, Pageable pageable);

    /**
     * 按创建时间从新到旧查询登录审计记录。
     *
     * @param pageable 分页参数
     * @return 登录审计记录列表
     */
    List<AuthLoginAudit> findAllByOrderByCreatedAtDesc(Pageable pageable);

    /**
     * 按管理端筛选条件分页查询登录审计记录。
     *
     * @param loginResult 登录结果，空字符串表示不限
     * @param platform 客户端平台，空字符串表示不限
     * @param searchPattern 模糊搜索模式，空字符串表示不限
     * @param pageable 分页参数
     * @return 登录审计分页结果
     */
    @Query(value = """
            select audit from AuthLoginAudit audit
            where (:loginResult = '' or audit.loginResult = :loginResult)
              and (:platform = '' or lower(audit.clientPlatform) = :platform)
              and (
                :searchPattern = ''
                or lower(audit.username) like :searchPattern
                or lower(coalesce(audit.ipAddress, '')) like :searchPattern
                or lower(coalesce(audit.deviceName, '')) like :searchPattern
                or lower(coalesce(audit.userAgent, '')) like :searchPattern
              )
            """,
            countQuery = """
                    select count(audit) from AuthLoginAudit audit
                    where (:loginResult = '' or audit.loginResult = :loginResult)
                      and (:platform = '' or lower(audit.clientPlatform) = :platform)
                      and (
                        :searchPattern = ''
                        or lower(audit.username) like :searchPattern
                        or lower(coalesce(audit.ipAddress, '')) like :searchPattern
                        or lower(coalesce(audit.deviceName, '')) like :searchPattern
                        or lower(coalesce(audit.userAgent, '')) like :searchPattern
                      )
                    """)
    Page<AuthLoginAudit> searchAdminAudits(
            @Param("loginResult") String loginResult,
            @Param("platform") String platform,
            @Param("searchPattern") String searchPattern,
            Pageable pageable
    );

    /**
     * 批量删除指定时间之前的登录审计记录。
     *
     * @param cutoff 截止时间
     * @return 删除数量
     */
    @Modifying
    @Query("delete from AuthLoginAudit audit where audit.createdAt < :cutoff")
    int deleteCreatedBefore(@Param("cutoff") Instant cutoff);

    /**
     * 统计指定时间之前将被清理的登录审计数量，谓词与 deleteCreatedBefore 保持一致。
     *
     * @param cutoff 截止时间
     * @return 登录审计数量
     */
    @Query("select count(audit) from AuthLoginAudit audit where audit.createdAt < :cutoff")
    long countCreatedBefore(@Param("cutoff") Instant cutoff);
}
