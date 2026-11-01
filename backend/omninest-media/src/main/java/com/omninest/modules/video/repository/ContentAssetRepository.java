package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.ContentAsset;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ContentAssetRepository extends JpaRepository<ContentAsset, UUID> {
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
