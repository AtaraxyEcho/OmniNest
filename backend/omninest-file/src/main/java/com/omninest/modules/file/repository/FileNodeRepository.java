package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.SpaceType;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Slice;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

public interface FileNodeRepository extends JpaRepository<FileNode, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select node from FileNode node where node.id = :id and node.ownerUserId = :ownerUserId")
    Optional<FileNode> findOwnedForUpdate(@Param("id") UUID id, @Param("ownerUserId") UUID ownerUserId);

    List<FileNode> findByOwnerUserIdAndParentIdIsNullAndDeletedFalse(UUID ownerUserId);

    List<FileNode> findByOwnerUserIdAndParentIdAndDeletedFalse(UUID ownerUserId, UUID parentId);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.spaceType = :spaceType
              AND n.parentId IS NULL
              AND n.deleted = false
              AND (n.sourceType IS NULL OR n.sourceType NOT IN ('DERIVED', 'LOCAL_FILESYSTEM'))
            """)
    Page<FileNode> findVisiblePersonalRoot(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            Pageable pageable);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.parentId = :parentId
              AND n.deleted = false
              AND (n.sourceType IS NULL OR n.sourceType NOT IN ('DERIVED', 'LOCAL_FILESYSTEM'))
            """)
    Page<FileNode> findVisiblePersonalChildren(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("parentId") UUID parentId,
            Pageable pageable);

    List<FileNode> findByOwnerUserIdAndDeletedFalse(UUID ownerUserId);

    List<FileNode> findByOwnerUserIdAndDeletedTrueOrderByDeletedAtDesc(UUID ownerUserId);

    List<FileNode> findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedFalse(UUID ownerUserId, String prefix);

    List<FileNode> findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedTrue(UUID ownerUserId, String prefix);

    /**
     * 分页读取指定路径下的全部节点。
     *
     * @param ownerUserId 所属用户 ID
     * @param prefix 路径前缀
     * @param pageable 分页参数
     * @return 文件节点分页
     */
    Page<FileNode> findByOwnerUserIdAndNormalizedPathStartingWithOrderById(
            UUID ownerUserId,
            String prefix,
            Pageable pageable
    );

    /**
     * 分页读取共享空间指定路径前缀下的节点。
     *
     * @param spaceType 空间类型
     * @param prefix 路径前缀
     * @param pageable 分页参数
     * @return 文件节点分页
     */
    Page<FileNode> findBySpaceTypeAndNormalizedPathStartingWithOrderById(
            SpaceType spaceType,
            String prefix,
            Pageable pageable
    );

    /**
     * 分页读取指定路径下已软删除节点的 ID。
     *
     * @param ownerUserId 所属用户 ID
     * @param prefix 路径前缀
     * @param pageable 分页参数
     * @return 节点 ID 切片
     */
    @Query("select node.id from FileNode node where node.ownerUserId = :ownerUserId "
            + "and node.normalizedPath like concat(:prefix, '%') and node.deleted = true order by node.id")
    Slice<UUID> findDeletedIdsByPathPrefix(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("prefix") String prefix,
            Pageable pageable
    );

    /**
     * 分页读取指定路径下尚未软删除节点的 ID。
     *
     * @param ownerUserId 所属用户 ID
     * @param prefix 路径前缀
     * @param pageable 分页参数
     * @return 节点 ID 切片
     */
    @Query("select node.id from FileNode node where node.ownerUserId = :ownerUserId "
            + "and node.normalizedPath like concat(:prefix, '%') and node.deleted = false order by node.id")
    Slice<UUID> findActiveIdsByPathPrefix(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("prefix") String prefix,
            Pageable pageable
    );

    /**
     * 批量软删除文件节点。
     *
     * @param ownerUserId 所属用户 ID
     * @param ids 文件节点 ID
     * @param deletedAt 删除时间
     * @return 更新数量
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update FileNode node set node.deleted = true, node.deletedAt = :deletedAt, "
            + "node.deletedBy = :ownerUserId, node.shared = false, node.sharedAt = null "
            + "where node.ownerUserId = :ownerUserId and node.id in :ids and node.deleted = false")
    int softDeleteIds(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("ids") Collection<UUID> ids,
            @Param("deletedAt") Instant deletedAt
    );

    List<FileNode> findByOwnerUserIdAndNormalizedPathStartingWith(UUID ownerUserId, String prefix);

    Optional<FileNode> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<FileNode> findByIdAndOwnerUserIdAndDeletedFalse(UUID id, UUID ownerUserId);

    /**
     * 查询指定目录下的活动同名节点。
     *
     * @param ownerUserId 所有者用户 ID
     * @param parentId 父目录 ID，根目录时为空
     * @param name 节点名称
     * @return 活动同名节点
     */
    @Query("""
            select node
            from FileNode node
            where node.ownerUserId = :ownerUserId
              and ((:parentId is null and node.parentId is null) or node.parentId = :parentId)
              and node.name = :name
              and node.deleted = false
            """)
    Optional<FileNode> findActiveNameConflict(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("parentId") UUID parentId,
            @Param("name") String name
    );

    List<FileNode> findByOwnerUserIdAndIdInAndDeletedFalse(UUID ownerUserId, Collection<UUID> ids);

    /**
     * 批量复核个人空间搜索候选节点的当前数据库状态。
     *
     * @param ownerUserId 所属用户 ID
     * @param ids Lucene 候选文件 ID
     * @param purgeState 永久删除状态
     * @param spaceType 空间类型
     * @param derivedSource 派生文件来源编码
     * @return 当前仍可搜索的节点
     */
    @Query("""
            select node
            from FileNode node
            where node.ownerUserId = :ownerUserId
              and node.id in :ids
              and node.deleted = false
              and node.purgeState = :purgeState
              and node.spaceType = :spaceType
              and (node.sourceType is null or node.sourceType <> :derivedSource)
            """)
    List<FileNode> findSearchablePersonalNodes(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("ids") Collection<UUID> ids,
            @Param("purgeState") FilePurgeState purgeState,
            @Param("spaceType") SpaceType spaceType,
            @Param("derivedSource") String derivedSource
    );

    @Query("""
            select node
            from FileNode node
            where node.ownerUserId = :ownerUserId
              and node.normalizedPath = :path
              and node.deleted = false
            """)
    Optional<FileNode> findActivePath(@Param("ownerUserId") UUID ownerUserId, @Param("path") String path);

    List<FileNode> findByOwnerUserIdAndSourceTypeAndNormalizedPathStartingWithAndDeletedFalse(
            UUID ownerUserId, String sourceType, String normalizedPathPrefix);

    @Query("""
            select distinct node.ownerUserId
            from FileNode node
            where node.sourceType = :sourceType
              and node.deleted = false
              and node.normalizedPath like concat(:normalizedPathPrefix, '%')
            """)
    List<UUID> findOwnerIdsBySourceTypeAndNormalizedPathPrefix(
            @Param("sourceType") String sourceType,
            @Param("normalizedPathPrefix") String normalizedPathPrefix);

    boolean existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(UUID ownerUserId, String name);

    boolean existsByOwnerUserIdAndParentIdAndNameAndDeletedFalse(UUID ownerUserId, UUID parentId, String name);

    Optional<FileNode> findByOwnerUserIdAndParentIdIsNullAndNameAndDeletedTrue(UUID ownerUserId, String name);

    Optional<FileNode> findByOwnerUserIdAndParentIdAndNameAndDeletedTrue(UUID ownerUserId, UUID parentId, String name);

    @Query("select n from FileNode n where n.deleted = true and n.deletedAt < :cutoff")
    List<FileNode> findExpiredDeletedNodes(@Param("cutoff") Instant cutoff);

    @Query("""
            select count(n)
            from FileNode n
            where n.ownerUserId = :ownerUserId and n.deleted = false and n.nodeType = 'FOLDER'
            """)
    long countFoldersByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    @Query("""
            select count(n)
            from FileNode n
            where n.ownerUserId = :ownerUserId and n.deleted = false and n.nodeType = 'FILE'
            """)
    long countFilesByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    @Query("""
            select n.mimeType, count(n), coalesce(sum(n.sizeBytes), 0)
            from FileNode n
            where n.ownerUserId = :ownerUserId and n.deleted = false and n.nodeType = 'FILE'
            group by n.mimeType
            """)
    List<Object[]> aggregateFileStatsByMimeType(@Param("ownerUserId") UUID ownerUserId);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.shared = true AND n.ownerUserId != :userId AND n.deleted = false
            """)
    List<FileNode> findSharedFilesVisibleToUser(@Param("userId") UUID userId);

    Optional<FileNode> findByIdAndDeletedFalse(UUID id);

    long countByCurrentObjectIdAndIdNotIn(UUID objectId, Collection<UUID> excludedIds);

    long countByCurrentObjectId(UUID objectId);

    /**
     * 批量查询仍由永久删除任务外节点引用的对象。
     *
     * @param objectIds 待检查对象 ID
     * @param taskId 永久删除任务 ID
     * @return 仍存在任务外节点引用的对象 ID
     */
    @Query("""
            select distinct node.currentObjectId
            from FileNode node
            where node.currentObjectId in :objectIds
              and (node.purgeTaskId is null or node.purgeTaskId <> :taskId)
            """)
    List<UUID> findCurrentObjectIdsReferencedOutsidePurgeTask(
            @Param("objectIds") Collection<UUID> objectIds,
            @Param("taskId") UUID taskId
    );

    List<FileNode> findByPurgeTaskId(UUID purgeTaskId);

    /**
     * 分页读取任务关联节点。
     *
     * @param purgeTaskId 永久删除任务 ID
     * @param pageable 分页参数
     * @return 节点分页
     */
    Page<FileNode> findByPurgeTaskIdOrderById(UUID purgeTaskId, Pageable pageable);

    /**
     * 分页读取任务关联节点 ID。
     *
     * @param purgeTaskId 永久删除任务 ID
     * @param pageable 分页参数
     * @return 节点 ID 分页
     */
    @Query("select node.id from FileNode node where node.purgeTaskId = :purgeTaskId order by node.id")
    Page<UUID> findIdsByPurgeTaskId(@Param("purgeTaskId") UUID purgeTaskId, Pageable pageable);

    long countByPurgeTaskId(UUID purgeTaskId);

    /**
     * 将已软删除目录后代关联到永久删除任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param prefix 路径前缀
     * @param taskId 任务 ID
     * @param state 生命周期状态
     * @param requestedAt 请求时间
     * @return 更新数量
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update FileNode node set node.purgeTaskId = :taskId, node.purgeState = :state, "
            + "node.purgeRequestedAt = :requestedAt where node.ownerUserId = :ownerUserId "
            + "and node.normalizedPath like concat(:prefix, '%') and node.deleted = true")
    int assignDeletedDescendantsToPurge(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("prefix") String prefix,
            @Param("taskId") UUID taskId,
            @Param("state") FilePurgeState state,
            @Param("requestedAt") Instant requestedAt
    );

    /**
     * 将业务参与者贡献的文件节点关联到永久删除任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param ids 文件节点 ID
     * @param taskId 任务 ID
     * @param state 生命周期状态
     * @param requestedAt 请求时间
     * @return 更新数量
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update FileNode node set node.deleted = true, node.deletedAt = coalesce(node.deletedAt, :requestedAt), "
            + "node.deletedBy = :ownerUserId, node.purgeTaskId = :taskId, node.purgeState = :state, "
            + "node.purgeRequestedAt = coalesce(node.purgeRequestedAt, :requestedAt) "
            + "where node.ownerUserId = :ownerUserId and node.id in :ids "
            + "and (node.purgeTaskId is null or node.purgeTaskId = :taskId)")
    int assignIdsToPurge(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("ids") Collection<UUID> ids,
            @Param("taskId") UUID taskId,
            @Param("state") FilePurgeState state,
            @Param("requestedAt") Instant requestedAt
    );

    /**
     * 批量更新任务节点生命周期状态。
     *
     * @param taskId 任务 ID
     * @param state 目标状态
     * @return 更新数量
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update FileNode node set node.purgeState = :state where node.purgeTaskId = :taskId")
    int updatePurgeStateByTaskId(
            @Param("taskId") UUID taskId,
            @Param("state") FilePurgeState state
    );

    /**
     * 统计仍由任务外节点引用的对象。
     *
     * @param objectId 对象 ID
     * @param taskId 永久删除任务 ID
     * @return 引用数量
     */
    @Query("select count(node) from FileNode node where node.currentObjectId = :objectId "
            + "and (node.purgeTaskId is null or node.purgeTaskId <> :taskId)")
    long countObjectReferencesOutsidePurgeTask(
            @Param("objectId") UUID objectId,
            @Param("taskId") UUID taskId
    );

    /**
     * 使用行锁查询永久删除任务关联节点。
     *
     * @param purgeTaskId 永久删除任务 ID
     * @return 关联节点
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select node from FileNode node where node.purgeTaskId = :purgeTaskId order by node.id")
    List<FileNode> findByPurgeTaskIdForUpdate(@Param("purgeTaskId") UUID purgeTaskId);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId AND n.currentObjectId = :objectId AND n.deleted = false
            """)
    Optional<FileNode> findActiveByOwnerUserIdAndObjectId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("objectId") UUID objectId
    );

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.normalizedPath LIKE CONCAT(:prefix, '%')
              AND n.deleted = false
            ORDER BY n.normalizedPath ASC
            """)
    List<FileNode> findDescendantsByPrefixOrdered(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("prefix") String prefix
    );

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND n.sourceType <> 'DERIVED'
              AND n.mimeType LIKE 'image/%'
            """)
    List<FileNode> findImageFilesByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.shared = true
              AND n.ownerUserId != :userId
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND n.sourceType <> 'DERIVED'
              AND n.mimeType LIKE 'image/%'
            """)
    List<FileNode> findSharedImageFilesVisibleToUser(@Param("userId") UUID userId);

    // ============================================================
    // 共享空间查询
    // ============================================================

    /**
     * 按空间类型查询用户的根目录文件（用于个人空间根目录过滤 space_type）
     */
    List<FileNode> findByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndDeletedFalse(UUID ownerUserId, SpaceType spaceType);

    /**
     * 按空间类型查询用户的所有非删除文件（用于批量扫描）
     */
    List<FileNode> findByOwnerUserIdAndSpaceTypeAndDeletedFalse(UUID ownerUserId, SpaceType spaceType);

    /**
     * 共享空间根目录
     */
    List<FileNode> findBySpaceTypeAndParentIdIsNullAndDeletedFalse(SpaceType spaceType);

    /**
     * 共享空间子目录
     */
    List<FileNode> findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType spaceType, UUID parentId);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.spaceType = :spaceType
              AND n.parentId IS NULL
              AND n.deleted = false
              AND (n.sourceType IS NULL OR n.sourceType <> 'DERIVED')
            """)
    Page<FileNode> findVisibleSharedRoot(
            @Param("spaceType") SpaceType spaceType,
            Pageable pageable);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.spaceType = :spaceType
              AND n.parentId = :parentId
              AND n.deleted = false
              AND (n.sourceType IS NULL OR n.sourceType <> 'DERIVED')
            """)
    Page<FileNode> findVisibleSharedChildren(
            @Param("spaceType") SpaceType spaceType,
            @Param("parentId") UUID parentId,
            Pageable pageable);

    /**
     * 按 ID + 空间类型查找
     */
    Optional<FileNode> findByIdAndSpaceTypeAndDeletedFalse(UUID id, SpaceType spaceType);

    /**
     * 共享空间同名检查
     */
    boolean existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(SpaceType spaceType, UUID parentId, String name);

    /**
     * 按空间类型查询回收站文件（个人空间用 ownerUserId，共享空间用 deletedBy）
     */
    List<FileNode> findByOwnerUserIdAndSpaceTypeAndDeletedTrueOrderByDeletedAtDesc(
            UUID ownerUserId,
            SpaceType spaceType
    );

    /**
     * 按删除者和空间类型查询回收站文件（共享空间专用）。
     */
    List<FileNode> findByDeletedByAndSpaceTypeAndDeletedTrueOrderByDeletedAtDesc(UUID deletedBy, SpaceType spaceType);

    /**
     * 查询指定空间类型的所有未删除文件（不限 owner，用于共享空间文件发现）。
     */
    List<FileNode> findBySpaceTypeAndDeletedFalse(SpaceType spaceType);
}
