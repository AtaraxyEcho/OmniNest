package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuditLog;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

/**
 * 审计日志保留清理所需的窄仓储接口。
 *
 * @author OmniNest
 */
public interface AuditLogRetentionRepository extends Repository<AuditLog, UUID> {

    /**
     * 按创建时间查询待清理审计日志标识。
     *
     * @param cutoff 截止时间
     * @param pageable 批次边界
     * @return 待清理日志标识
     */
    @Query("""
            select log.id from AuditLog log
            where log.createdAt < :cutoff
            order by log.createdAt asc
            """)
    List<UUID> findIdsCreatedBefore(@Param("cutoff") Instant cutoff, Pageable pageable);

    /**
     * 批量删除指定审计日志。
     *
     * <p>自定义 {@code @Modifying} 方法不像 {@code SimpleJpaRepository} 的
     * {@code deleteById} 那样自带事务拦截：调用方未处于事务中时，
     * Jakarta Persistence 会直接抛 {@code TransactionRequiredException}。
     * 清理任务刻意按批短事务提交，因此事务边界必须落在本方法上。</p>
     *
     * @param ids 审计日志标识
     * @return 删除记录数
     */
    @Modifying
    @Transactional
    @Query("delete from AuditLog log where log.id in :ids")
    int deleteByIds(@Param("ids") Collection<UUID> ids);
}
