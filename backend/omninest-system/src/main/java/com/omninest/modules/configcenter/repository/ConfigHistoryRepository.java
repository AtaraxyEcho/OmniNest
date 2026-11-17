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
     * 查询可清理的历史标识：每配置键保留最近 minimumVersions 个版本，其余早于 cutoff 的删除。
     *
     * <p>分区排名在库内一次算完，避免逐配置键查保护集再查过期集。只对存在过期记录的键排名，
     * 使窗口函数的输入规模由"有历史需要清理的配置键"决定，而不是整张历史表。</p>
     *
     * @param cutoff 截止时间
     * @param minimumVersions 每个配置键保留的版本数
     * @param batchSize 单批删除上限
     * @return 待删除历史标识
     */
    @Query(value = """
            with expired_keys as (
                select distinct config_key from omni.config_histories where created_at < :cutoff
            ), ranked as (
                select history.id, history.created_at,
                       row_number() over (
                           partition by history.config_key
                           order by history.created_at desc, history.id desc
                       ) as version_rank
                from omni.config_histories history
                where history.config_key in (select config_key from expired_keys)
            )
            select id from ranked
            where version_rank > :minimumVersions and created_at < :cutoff
            order by created_at asc, id asc
            limit :batchSize
            """, nativeQuery = true)
    List<UUID> findRetentionCandidateIds(
            @Param("cutoff") Instant cutoff,
            @Param("minimumVersions") int minimumVersions,
            @Param("batchSize") int batchSize
    );
}
