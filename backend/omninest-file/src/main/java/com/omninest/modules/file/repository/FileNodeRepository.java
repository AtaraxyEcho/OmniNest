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
              AND n.spaceType = :spaceType
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND n.category = :category
              AND (n.sourceType IS NULL OR n.sourceType NOT IN ('DERIVED', 'LOCAL_FILESYSTEM'))
            """)
    Page<FileNode> findVisiblePersonalCategoryPage(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            @Param("category") String category,
            Pageable pageable);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND n.category = :category
              AND (n.sourceType IS NULL OR n.sourceType NOT IN ('DERIVED', 'LOCAL_FILESYSTEM'))
              AND n.normalizedPath LIKE concat(:pathPrefix, '%') escape '\\'
            """)
    Page<FileNode> findVisibleSubtreeCategoryPage(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("pathPrefix") String pathPrefix,
            @Param("category") String category,
            Pageable pageable);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.nodeType = :nodeType
              AND n.category IS NULL
            ORDER BY n.id
            """)
    Slice<FileNode> findMissingCategoryPage(@Param("nodeType") String nodeType, Pageable pageable);

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

    /**
     * 按类型查询用户未删除节点。
     *
     * <p>面向"只需要文件"的批量候选场景：把类型判定下推数据库，目录行不再进入内存。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param nodeType 节点类型
     * @return 匹配节点
     */
    List<FileNode> findByOwnerUserIdAndNodeTypeAndDeletedFalse(UUID ownerUserId, String nodeType);

    List<FileNode> findByOwnerUserIdAndDeletedTrueOrderByDeletedAtDesc(UUID ownerUserId);

    /**
     * 按路径前缀读取指定空间内的活动节点。前缀是真实目录名的字面量，调用方必须转义，本查询声明 {@code escape '\'}。
     *
     * <p>必须带 spaceType：个人与共享空间允许同名目录（例如两侧都有 {@code /Reader}），
     * 只按 owner + 前缀会把另一空间的子树一起圈进软删、改名与共享级联。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀
     * @return 活动节点列表
     */
    @Query("select node from FileNode node where node.ownerUserId = :ownerUserId "
            + "and node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' and node.deleted = false")
    List<FileNode> findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix
    );

    /**
     * 按路径前缀读取指定空间内的已软删除节点，口径同上。
     *
     * @param ownerUserId 所有者用户 ID
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀
     * @return 已软删除节点列表
     */
    @Query("select node from FileNode node where node.ownerUserId = :ownerUserId "
            + "and node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' and node.deleted = true")
    List<FileNode> findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix
    );

    /**
     * 按空间收集子树内的已软删除节点，不限制所有者。
     *
     * <p>共享空间同一目录树里的节点 {@code owner_user_id} 是各自上传者。恢复父目录若仍按
     * 单个所有者取子节点，别人上传的子文件会留在回收站，形成"父目录已恢复、子文件不可见"
     * 的悬挂节点，而共享配额按整棵子树补记，账实不符。永久删除同理。</p>
     *
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀
     * @return 已软删除节点列表
     */
    @Query("select node from FileNode node where node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' and node.deleted = true")
    List<FileNode> findDeletedBySpaceTypeAndNormalizedPathStartingWith(
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix
    );

    /**
     * 分页读取指定空间与路径下的全部节点。
     *
     * <p>由 derived 方法改为显式查询：派生属性的 {@code StartingWith} 生成的 LIKE 挂不上
     * ESCAPE 子句；排序保留在查询里，因为部分调用方传的是不带 Sort 的 PageRequest。</p>
     *
     * @param ownerUserId 所属用户 ID
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀
     * @param pageable 分页参数
     * @return 文件节点分页
     */
    @Query("select node from FileNode node where node.ownerUserId = :ownerUserId "
            + "and node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' order by node.id asc")
    Page<FileNode> findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithOrderById(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix,
            Pageable pageable
    );

    /**
     * 按 ID 游标读取指定空间与路径前缀下的节点。
     *
     * <p>该查询驱动共享空间改名时的子树路径重写。被改写的 normalizedPath 正是过滤条件列，
     * 用 OFFSET 翻页会让改写后的记录退出结果集、后续页整体前移，从而跳过未改写的一半节点，
     * 因此必须按主键游标推进。</p>
     *
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀
     * @param afterId 上一页最大节点 ID，首页传最小 UUID
     * @param limit 单批数量
     * @return 按 ID 升序的节点批次
     */
    @Query("select node from FileNode node where node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' "
            + "and node.id > :afterId order by node.id asc")
    List<FileNode> findSubtreeBySpaceTypeAfterId(
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix,
            @Param("afterId") UUID afterId,
            Pageable limit
    );

    /**
     * 读取指定空间与路径前缀下所有活动节点 ID（不区分所有者）。
     *
     * <p>共享空间目录可能包含多个成员上传的子项，按所有者过滤会漏掉其他成员的文件。</p>
     *
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀（含结尾分隔符）
     * @return 活动节点 ID
     */
    @Query("select node.id from FileNode node where node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' and node.deleted = false")
    List<UUID> findActiveIdsUnderPathInSpace(
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix
    );

    /**
     * 读取指定空间与路径前缀下活动节点的所有者与 ID，用于按上传者分组投递索引事件。
     *
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀（含结尾分隔符）
     * @return 每行二元组：所有者 ID、节点 ID
     */
    @Query("select node.ownerUserId, node.id from FileNode node where node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' and node.deleted = false")
    List<Object[]> findActiveIdOwnerPairsUnderPathInSpace(
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix
    );

    /**
     * 按空间与路径前缀批量软删除整棵子树。
     *
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀（含结尾分隔符）
     * @param deletedAt 删除时间
     * @param deletedBy 删除操作者
     * @return 更新行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update FileNode node set node.deleted = true, node.deletedAt = :deletedAt, "
            + "node.deletedBy = :deletedBy, node.updatedAt = :deletedAt, node.version = node.version + 1 "
            + "where node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' and node.deleted = false")
    int softDeleteSubtreeInSpace(
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix,
            @Param("deletedAt") Instant deletedAt,
            @Param("deletedBy") UUID deletedBy
    );

    /**
     * 分页读取指定空间与路径下尚未软删除节点的 ID。
     *
     * @param ownerUserId 所属用户 ID
     * @param spaceType 空间类型
     * @param prefix 路径前缀
     * @param pageable 分页参数
     * @return 节点 ID 切片
     */
    @Query("select node.id from FileNode node where node.ownerUserId = :ownerUserId "
            + "and node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' and node.deleted = false order by node.id")
    Slice<UUID> findActiveIdsByPathPrefix(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
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

    Optional<FileNode> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<FileNode> findByIdAndOwnerUserIdAndDeletedFalse(UUID id, UUID ownerUserId);

    /**
     * 查询指定空间与目录下的活动同名节点。
     *
     * <p>必须带 spaceType 过滤：共享空间节点同样保留 owner_user_id，只按 owner 判断会把
     * 共享空间同名根节点误判为个人空间冲突。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param spaceType 目标空间类型
     * @param parentId 父目录 ID，根目录时为空
     * @param name 节点名称
     * @return 活动同名节点
     */
    @Query("""
            select node
            from FileNode node
            where node.ownerUserId = :ownerUserId
              and node.spaceType = :spaceType
              and ((:parentId is null and node.parentId is null) or node.parentId = :parentId)
              and node.name = :name
              and node.deleted = false
            """)
    Optional<FileNode> findActiveNameConflict(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
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

    /**
     * 批量复核共享空间搜索候选节点的当前数据库状态。
     *
     * <p>共享空间可见性由角色权限单独判定，这里不按 owner_user_id 过滤；
     * 节点仍须活动、未进入永久删除且非系统派生。</p>
     *
     * @param ids Lucene 候选文件 ID
     * @param purgeState 永久删除状态
     * @param spaceType 空间类型
     * @param derivedSource 派生文件来源编码
     * @return 当前仍可搜索的共享空间节点
     */
    @Query("""
            select node
            from FileNode node
            where node.id in :ids
              and node.deleted = false
              and node.purgeState = :purgeState
              and node.spaceType = :spaceType
              and (node.sourceType is null or node.sourceType <> :derivedSource)
            """)
    List<FileNode> findSearchableSharedNodes(
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

    /**
     * 按来源类型与路径前缀读取活动节点，口径同上。
     *
     * <p>派生资产前缀里的下划线是 {@code segment()} 规范化出来的（如
     * {@code /.metadata/READER_ITEM/}），不是通配符意图。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param sourceType 来源类型编码
     * @param normalizedPathPrefix 已转义的路径前缀
     * @return 节点列表
     */
    @Query("select node from FileNode node where node.ownerUserId = :ownerUserId "
            + "and node.sourceType = :sourceType "
            + "and node.normalizedPath like concat(:normalizedPathPrefix, '%') escape '\\' "
            + "and node.deleted = false")
    List<FileNode> findByOwnerUserIdAndSourceTypeAndNormalizedPathStartingWithAndDeletedFalse(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("sourceType") String sourceType,
            @Param("normalizedPathPrefix") String normalizedPathPrefix
    );

    @Query("""
            select distinct node.ownerUserId
            from FileNode node
            where node.sourceType = :sourceType
              and node.deleted = false
              and node.normalizedPath like concat(:normalizedPathPrefix, '%') escape '\\'
            """)
    List<UUID> findOwnerIdsBySourceTypeAndNormalizedPathPrefix(
            @Param("sourceType") String sourceType,
            @Param("normalizedPathPrefix") String normalizedPathPrefix);

    /**
     * 指定空间内是否存在同名活动节点。
     *
     * <p>必须带 spaceType 过滤：共享空间节点同样保留 owner_user_id，只按 owner 判断会把
     * 共享空间同名根节点误判为个人空间冲突。</p>
     */
    boolean existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
            UUID ownerUserId, SpaceType spaceType, String name);

    boolean existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
            UUID ownerUserId, SpaceType spaceType, UUID parentId, String name);

    Optional<FileNode> findByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedTrue(
            UUID ownerUserId, SpaceType spaceType, String name);

    Optional<FileNode> findByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedTrue(
            UUID ownerUserId, SpaceType spaceType, UUID parentId, String name);

    @Query("select n from FileNode n where n.deleted = true and n.deletedAt < :cutoff")
    List<FileNode> findExpiredDeletedNodes(@Param("cutoff") Instant cutoff);

    @Query("""
            select n from FileNode n
            where n.deleted = true and n.deletedAt < :cutoff
              and n.id > :afterId
            order by n.id
            """)
    List<FileNode> findExpiredDeletedNodesAfter(
            @Param("cutoff") Instant cutoff,
            @Param("afterId") UUID afterId,
            Pageable pageable);

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

    /**
     * 汇总个人空间某目录子树内的活跃文件字节数与文件数。
     *
     * <p>个人空间的规范化路径只在该用户名下唯一，不同用户可以持有同名前缀，
     * 因此必须带 ownerUserId 过滤。</p>
     *
     * @param ownerUserId 空间所有者
     * @param spaceType 空间类型
     * @param prefix 已转义的父目录路径前缀（含结尾分隔符）
     * @return 单行二元组：总字节数、文件数
     */
    @Query("""
            select coalesce(sum(n.sizeBytes), 0), count(n.id)
            from FileNode n
            where n.ownerUserId = :ownerUserId and n.spaceType = :spaceType
              and n.nodeType = 'FILE' and n.deleted = false
              and n.normalizedPath like concat(:prefix, '%') escape '\\'
            """)
    List<Object[]> sumActiveFilesUnderPathByOwner(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix
    );

    /**
     * 汇总共享空间某目录子树内的活跃文件字节数与文件数。
     *
     * <p>共享空间是一棵全体成员共用的树，目录内文件的所有者各不相同，
     * 按创建者过滤会漏掉其他成员上传的字节，因此这里只按空间与前缀统计。</p>
     *
     * @param spaceType 空间类型
     * @param prefix 已转义的父目录路径前缀（含结尾分隔符）
     * @return 单行二元组：总字节数、文件数
     */
    @Query("""
            select coalesce(sum(n.sizeBytes), 0), count(n.id)
            from FileNode n
            where n.spaceType = :spaceType
              and n.nodeType = 'FILE' and n.deleted = false
              and n.normalizedPath like concat(:prefix, '%') escape '\\'
            """)
    List<Object[]> sumActiveFilesUnderPathInSpace(
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix
    );

    /**
     * 汇总共享空间某目录子树内已软删除文件的字节数与文件数。
     *
     * <p>恢复共享空间文件夹时整棵子树仍处于删除状态，活跃口径的汇总只能得到零；
     * 这里与 {@link #sumActiveFilesUnderPathInSpace} 对称，只把 deleted 条件反过来。</p>
     *
     * @param spaceType 空间类型
     * @param prefix 已转义的父目录路径前缀（含结尾分隔符）
     * @return 单行二元组：总字节数、文件数
     */
    @Query("""
            select coalesce(sum(n.sizeBytes), 0), count(n.id)
            from FileNode n
            where n.spaceType = :spaceType
              and n.nodeType = 'FILE' and n.deleted = true
              and n.normalizedPath like concat(:prefix, '%') escape '\\'
            """)
    List<Object[]> sumDeletedFilesUnderPathInSpace(
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix
    );

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
     * <p>必须带 spaceType：这条 update 直接决定哪些节点会被物理清除，而个人与共享空间
     * 允许同名目录，另一空间的同名子树不能被子树前缀认领。</p>
     *
     * @param ownerUserId 所属用户 ID
     * @param spaceType 空间类型
     * @param prefix 路径前缀
     * @param taskId 任务 ID
     * @param state 生命周期状态
     * @param requestedAt 请求时间
     * @return 更新数量
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update FileNode node set node.purgeTaskId = :taskId, node.purgeState = :state, "
            + "node.purgeRequestedAt = :requestedAt where node.ownerUserId = :ownerUserId "
            + "and node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' and node.deleted = true")
    int assignDeletedDescendantsToPurge(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix,
            @Param("taskId") UUID taskId,
            @Param("state") FilePurgeState state,
            @Param("requestedAt") Instant requestedAt
    );

    /**
     * 按空间把子树内的已软删除节点挂到粉碎任务上，不限制所有者。
     *
     * <p>共享空间里父目录由 A 粉碎时，B 上传的子文件也必须进物理清除清单；仍按
     * 单个所有者过滤就会留下永久悬挂节点：列表与回收站都看不到，字节却一直占着桶。</p>
     *
     * @param spaceType 空间类型
     * @param prefix 路径前缀
     * @param taskId 任务 ID
     * @param state 生命周期状态
     * @param requestedAt 请求时间
     * @return 更新数量
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update FileNode node set node.purgeTaskId = :taskId, node.purgeState = :state, "
            + "node.purgeRequestedAt = :requestedAt where node.spaceType = :spaceType "
            + "and node.normalizedPath like concat(:prefix, '%') escape '\\' and node.deleted = true")
    int assignDeletedDescendantsToPurgeInSpace(
            @Param("spaceType") SpaceType spaceType,
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
              AND n.normalizedPath LIKE CONCAT(:prefix, '%') escape '\\'
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
     * 按 ID 游标读取需要重建全文索引的文件节点。
     *
     * <p>排除回收站节点与派生资产：派生缩略图、海报与元数据侧车文件不是用户内容，
     * 重建时把它们卷进来会让搜索结果混入内部资产。</p>
     *
     * @param nodeType 节点类型字面量（FILE）
     * @param afterId 上一页最大节点 ID，首页传最小 UUID
     * @param limit 单批数量
     * @return 按 ID 升序的文件节点批次
     */
    @Query("""
            SELECT n FROM FileNode n
            WHERE n.nodeType = :nodeType
              AND n.deleted = false
              AND n.currentObjectId IS NOT NULL
              AND (n.sourceType IS NULL OR n.sourceType <> 'DERIVED')
              AND n.id > :afterId
            ORDER BY n.id ASC
            """)
    List<FileNode> findIndexableFilesAfterId(
            @Param("nodeType") String nodeType,
            @Param("afterId") UUID afterId,
            Pageable limit);

    /**
     * 统计需要重建全文索引的文件节点总数，用于换算任务进度。
     *
     * @param nodeType 节点类型字面量（FILE）
     * @return 待重建文件数
     */
    @Query("""
            SELECT COUNT(n) FROM FileNode n
            WHERE n.nodeType = :nodeType
              AND n.deleted = false
              AND n.currentObjectId IS NOT NULL
              AND (n.sourceType IS NULL OR n.sourceType <> 'DERIVED')
            """)
    long countIndexableFiles(@Param("nodeType") String nodeType);

    /**
     * 按 ID + 空间类型查找
     */
    Optional<FileNode> findByIdAndSpaceTypeAndDeletedFalse(UUID id, SpaceType spaceType);

    /**
     * 共享空间同名检查
     */
    boolean existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(SpaceType spaceType, UUID parentId, String name);

    /**
     * 共享空间根目录同名检查
     */
    boolean existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(SpaceType spaceType, String name);

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
     * 查询指定空间类型的所有未删除文件节点（不限 owner，用于共享空间文件发现）。
     *
     * <p>类型下推数据库：只需要文件的候选场景不必把整个空间的目录行读进内存。</p>
     */
    List<FileNode> findBySpaceTypeAndNodeTypeAndDeletedFalse(SpaceType spaceType, String nodeType);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.spaceType = :spaceType
              AND n.deleted = true
              AND n.purgeState = 'NONE'
              AND (n.sourceType IS NULL OR n.sourceType NOT IN ('DERIVED', 'LOCAL_FILESYSTEM'))
              AND (n.parentId IS NULL OR NOT EXISTS (
                  SELECT p.id FROM FileNode p WHERE p.id = n.parentId AND p.deleted = true
              ))
            ORDER BY n.deletedAt DESC
            """)
    Page<FileNode> findPersonalRecyclePage(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            Pageable pageable);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.deletedBy = :deletedBy
              AND n.spaceType = :spaceType
              AND n.deleted = true
              AND n.purgeState = 'NONE'
              AND (n.sourceType IS NULL OR n.sourceType NOT IN ('DERIVED', 'LOCAL_FILESYSTEM'))
              AND (n.parentId IS NULL OR NOT EXISTS (
                  SELECT p.id FROM FileNode p WHERE p.id = n.parentId AND p.deleted = true
              ))
            ORDER BY n.deletedAt DESC
            """)
    Page<FileNode> findSharedRecyclePage(
            @Param("deletedBy") UUID deletedBy,
            @Param("spaceType") SpaceType spaceType,
            Pageable pageable);

    /**
     * 分页查询共享空间中当前用户可查看的文件。
     *
     * <p>可见性必须与 {@code FilePermissionService.resolvePermissions} 同口径下推到 SQL：
     * 用户级覆盖优先于全局默认，两者都没有记录时按拒绝处理。先分页再在内存过滤
     * 会让 totalElements 虚高，前端触底续载永远取不到更多数据。</p>
     *
     * @param userId 当前用户标识
     * @param pageable 分页参数
     * @return 可见共享文件分页
     */
    @Query("""
            SELECT n FROM FileNode n
            WHERE n.shared = true
              AND n.ownerUserId != :userId
              AND n.deleted = false
              AND (
                  EXISTS (
                      SELECT p.id FROM FileNodePermission p
                      WHERE p.fileNodeId = n.id
                        AND p.granteeUserId = :userId
                        AND p.allowView = true
                  )
                  OR (
                      NOT EXISTS (
                          SELECT own.id FROM FileNodePermission own
                          WHERE own.fileNodeId = n.id
                            AND own.granteeUserId = :userId
                      )
                      AND EXISTS (
                          SELECT globalPerm.id FROM FileNodePermission globalPerm
                          WHERE globalPerm.fileNodeId = n.id
                            AND globalPerm.granteeUserId IS NULL
                            AND globalPerm.allowView = true
                      )
                  )
              )
            """)
    Page<FileNode> findSharedFilesVisiblePage(@Param("userId") UUID userId, Pageable pageable);

}
