package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuditLog;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

/**
 * 审计日志管理仓库 — 管理后台专用查询。
 *
 * @author OmniNest
 */
@Repository
public interface AuditLogAdminRepository extends JpaRepository<AuditLog, UUID> {

    /**
     * 统计指定时间之后的审计日志数量。
     *
     * @param since 起始时间
     * @return 审计日志数量
     */
    @Query("select count(a) from AuditLog a where a.createdAt >= :since")
    long countSince(@Param("since") Instant since);

    /**
     * 按创建时间从新到旧查询审计日志。
     *
     * @param pageable 分页参数
     * @return 审计日志列表
     */
    List<AuditLog> findAllByOrderByCreatedAtDesc(Pageable pageable);

    /**
     * 按管理端筛选条件分页查询操作审计日志。
     *
     * @param action 操作类型，空字符串表示不限
     * @param searchPattern 模糊搜索模式，空字符串表示不限
     * @param pageable 分页参数
     * @return 审计日志分页结果
     */
    @Query(value = """
            select audit from AuditLog audit
            where (:action = '' or audit.action = :action)
              and (
                :searchPattern = ''
                or lower(audit.action) like :searchPattern
                or lower(audit.resourceType) like :searchPattern
                or lower(coalesce(audit.ipAddress, '')) like :searchPattern
              )
            """,
            countQuery = """
                    select count(audit) from AuditLog audit
                    where (:action = '' or audit.action = :action)
                      and (
                        :searchPattern = ''
                        or lower(audit.action) like :searchPattern
                        or lower(audit.resourceType) like :searchPattern
                        or lower(coalesce(audit.ipAddress, '')) like :searchPattern
                      )
                    """)
    Page<AuditLog> searchAdminLogs(
            @Param("action") String action,
            @Param("searchPattern") String searchPattern,
            Pageable pageable
    );

    /**
     * 批量删除指定时间之前的审计日志。
     *
     * @param cutoff 截止时间
     * @return 删除数量
     */
    @Modifying
    @Query("delete from AuditLog audit where audit.createdAt < :cutoff")
    int deleteCreatedBefore(@Param("cutoff") Instant cutoff);

    /**
     * 统计指定时间之前将被清理的审计日志数量，谓词与 deleteCreatedBefore 保持一致。
     *
     * @param cutoff 截止时间
     * @return 审计日志数量
     */
    @Query("select count(audit) from AuditLog audit where audit.createdAt < :cutoff")
    long countCreatedBefore(@Param("cutoff") Instant cutoff);
}
