package com.omninest.modules.configcenter.repository;

import com.omninest.modules.configcenter.domain.ConfigHistory;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 配置变更历史仓储。
 *
 * @author OmniNest
 */
public interface ConfigHistoryRepository extends JpaRepository<ConfigHistory, UUID> {

    /**
     * 按配置键查询历史记录，按创建时间倒序排列。
     *
     * @param configKey 配置键
     * @param pageable 分页参数
     * @return 历史记录列表
     */
    List<ConfigHistory> findByConfigKeyOrderByCreatedAtDesc(String configKey, Pageable pageable);

    /**
     * 查询指定配置键的全部历史记录。
     *
     * @param configKey 配置键
     * @return 历史记录列表
     */
    List<ConfigHistory> findByConfigKey(String configKey);

    /**
     * 批量查询多个配置键的历史记录，供启动期敏感值迁移避免逐键查询。
     *
     * @param configKeys 配置键集合
     * @return 历史记录列表
     */
    List<ConfigHistory> findByConfigKeyIn(Collection<String> configKeys);

    /**
     * 分页查询存在过期历史的配置键。
     *
     * @param cutoff 截止时间
     * @param pageable 配置键分页参数
     * @return 配置键列表
     */
    @Query("""
            select distinct history.configKey from ConfigHistory history
            where history.createdAt < :cutoff
            order by history.configKey
            """)
    List<String> findDistinctConfigKeysCreatedBefore(
            @Param("cutoff") Instant cutoff,
            Pageable pageable
    );

    /**
     * 查询配置键需要保留的最近历史标识。
     *
     * @param configKey 配置键
     * @param pageable 最小保留版本边界
     * @return 最近历史标识
     */
    @Query("""
            select history.id from ConfigHistory history
            where history.configKey = :configKey
            order by history.createdAt desc, history.id desc
            """)
    List<UUID> findRecentIdsByConfigKey(
            @Param("configKey") String configKey,
            Pageable pageable
    );

    /**
     * 查询过期且不在保护集合中的历史标识。
     *
     * @param configKey 配置键
     * @param cutoff 截止时间
     * @param protectedIds 受保护的最近历史标识
     * @param pageable 删除批次边界
     * @return 待删除历史标识
     */
    @Query("""
            select history.id from ConfigHistory history
            where history.configKey = :configKey
            and history.createdAt < :cutoff
            and history.id not in :protectedIds
            order by history.createdAt asc, history.id asc
            """)
    List<UUID> findExpiredIdsExcluding(
            @Param("configKey") String configKey,
            @Param("cutoff") Instant cutoff,
            @Param("protectedIds") List<UUID> protectedIds,
            Pageable pageable
    );
}
