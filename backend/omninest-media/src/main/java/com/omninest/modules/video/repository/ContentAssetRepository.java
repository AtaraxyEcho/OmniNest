package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.ContentAsset;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

public interface ContentAssetRepository extends JpaRepository<ContentAsset, UUID> {

    /**
     * 原子写入资源的主资产。
     *
     * <p>主资产受部分唯一索引 {@code idx_content_assets_primary_unique} 约束
     * （{@code resource_type, resource_id, asset_type} where {@code is_primary}）。
     * 先查后插在并发刮削同一资源时会撞唯一键并抛 500，且冲突发生在事务内时
     * 后续写入整体回滚，重试同一条消息会反复失败。</p>
     *
     * <p>必须自带 {@code @Transactional}：调用方会在子虚拟线程里直接调用本方法
     * （{@code TransactionSynchronizationManager} 基于 ThreadLocal，父线程的事务
     * 不会传播过去），自定义 {@code @Modifying} 查询又没有内置的事务拦截，
     * 缺注解时执行期必定 {@code TransactionRequiredException}。</p>
     *
     * @param id 新行标识；冲突时保留原行 id
     * @param ownerUserId 所属用户
     * @param resourceType 业务资源类型
     * @param resourceId 业务资源 ID
     * @param assetType 资产类型
     * @param fileNodeId 已入库文件节点 ID
     * @param externalUrl 外部地址
     * @param provider 来源提供方
     * @param sortOrder 排序
     * @param metadataJson 扩展元数据 JSON 文本
     * @param timestamp 写入时间
     * @return 插入或更新的行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query(value = """
            INSERT INTO omni.content_assets (
                id, owner_user_id, resource_type, resource_id, asset_type, file_node_id,
                external_url, provider, sort_order, is_primary, metadata,
                created_at, updated_at, version
            ) VALUES (
                :id, :ownerUserId, :resourceType, :resourceId, :assetType, :fileNodeId,
                :externalUrl, :provider, :sortOrder, true, CAST(:metadataJson AS jsonb),
                :timestamp, :timestamp, 0
            )
            ON CONFLICT (resource_type, resource_id, asset_type) WHERE is_primary DO UPDATE SET
                owner_user_id = EXCLUDED.owner_user_id,
                file_node_id = EXCLUDED.file_node_id,
                external_url = EXCLUDED.external_url,
                provider = EXCLUDED.provider,
                sort_order = EXCLUDED.sort_order,
                metadata = EXCLUDED.metadata,
                updated_at = EXCLUDED.updated_at,
                version = content_assets.version + 1
            """, nativeQuery = true)
    int upsertPrimary(
            @Param("id") UUID id,
            @Param("ownerUserId") UUID ownerUserId,
            @Param("resourceType") String resourceType,
            @Param("resourceId") UUID resourceId,
            @Param("assetType") String assetType,
            @Param("fileNodeId") UUID fileNodeId,
            @Param("externalUrl") String externalUrl,
            @Param("provider") String provider,
            @Param("sortOrder") int sortOrder,
            @Param("metadataJson") String metadataJson,
            @Param("timestamp") Instant timestamp
    );

    @Query("""
            select asset
            from ContentAsset asset
            where asset.ownerUserId = :ownerUserId
              and asset.resourceType = :resourceType
              and asset.resourceId = :resourceId
              and asset.assetType = :assetType
              and asset.primary = true
            """)
    Optional<ContentAsset> findPrimaryAsset(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("resourceType") String resourceType,
            @Param("resourceId") UUID resourceId,
            @Param("assetType") String assetType
    );

    @Query("""
            select asset
            from ContentAsset asset
            where asset.ownerUserId = :ownerUserId
              and asset.resourceType = :resourceType
              and asset.resourceId in :resourceIds
              and asset.assetType in :assetTypes
              and asset.primary = true
            order by asset.resourceId asc, asset.assetType asc, asset.sortOrder asc
            """)
    List<ContentAsset> listPrimaryAssets(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("resourceType") String resourceType,
            @Param("resourceIds") Collection<UUID> resourceIds,
            @Param("assetTypes") Collection<String> assetTypes
    );

    List<ContentAsset> findAllByOwnerUserIdAndResourceTypeAndResourceId(
            UUID ownerUserId,
            String resourceType,
            UUID resourceId
    );

    List<ContentAsset> findByOwnerUserIdAndFileNodeId(UUID ownerUserId, UUID fileNodeId);

    /**
     * 按内容文件节点批量查询资产行。
     *
     * <p>云盘侧永久删除自定义海报/背景图时用来回收指向已删节点的资产记录。</p>
     *
     * @param fileNodeIds 文件节点 ID
     * @return 引用这些节点的资产行
     */
    List<ContentAsset> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    /**
     * 批量查询 ContentAsset（避免 N+1）。
     */
    List<ContentAsset> findAllByOwnerUserIdAndResourceTypeAndResourceIdIn(
            UUID ownerUserId,
            String resourceType,
            Collection<UUID> resourceIds
    );

    @Query("""
            select asset
            from ContentAsset asset
            where asset.ownerUserId = :ownerUserId
              and asset.resourceType = :resourceType
              and asset.resourceId = :resourceId
              and asset.assetType = :assetType
            order by asset.sortOrder asc
            """)
    List<ContentAsset> findByOwnerUserIdAndResourceTypeAndResourceIdAndAssetType(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("resourceType") String resourceType,
            @Param("resourceId") UUID resourceId,
            @Param("assetType") String assetType
    );
}
