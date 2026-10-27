package com.omninest.modules.reader.repository;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.reader.domain.ReaderItem;
import jakarta.persistence.LockModeType;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 阅读条目仓储。
 */
public interface ReaderItemRepository extends JpaRepository<ReaderItem, UUID> {

    /**
     * 获取阅读条目并加写锁，用于串行化同一条目的来源创建与状态迁移。
     *
     * @param id 阅读条目 ID
     * @return 已加写锁的阅读条目
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT item FROM ReaderItem item WHERE item.id = :id")
    Optional<ReaderItem> findByIdForUpdate(@Param("id") UUID id);

    List<ReaderItem> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);

    List<ReaderItem> findByOwnerUserIdAndItemTypeOrderByUpdatedAtDesc(UUID ownerUserId, String itemType);

    Optional<ReaderItem> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    List<ReaderItem> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    List<ReaderItem> findByOwnerUserIdAndCoverFileIdIn(UUID ownerUserId, Collection<UUID> coverFileIds);

    /**
     * 按封面文件批量查询全部阅读条目。
     *
     * @param coverFileIds 封面文件节点 ID
     * @return 阅读条目
     */
    List<ReaderItem> findByCoverFileIdIn(Collection<UUID> coverFileIds);

    /**
     * 判断除指定条目外是否还有条目引用同一封面，用于安全回收派生封面。
     *
     * @param coverFileId 封面文件节点 ID
     * @param id 需要排除的条目 ID
     * @return 仍被其他条目引用时返回 true
     */
    boolean existsByCoverFileIdAndIdNot(UUID coverFileId, UUID id);

    /**
     * 按内容哈希查找已有条目（用于内容级去重）。
     */
    List<ReaderItem> findByContentHash(String contentHash);

    Optional<ReaderItem> findFirstByOwnerUserIdAndContentHashOrderByUpdatedAtDesc(
            UUID ownerUserId, String contentHash);

    /**
     * 对用户与内容摘要加事务级数据库锁，串行化并发重复导入。
     */
    @Query(value = """
            SELECT pg_advisory_xact_lock(
                hashtextextended(CAST(:ownerUserId AS text) || ':' || :contentHash, 0)
            )
            """, nativeQuery = true)
    void lockContentHash(@Param("ownerUserId") UUID ownerUserId, @Param("contentHash") String contentHash);

    /**
     * 统计用户可见条目数（个人空间 + 可选共享空间）。
     */
    @Query("""
            SELECT COUNT(ri) FROM ReaderItem ri
            JOIN FileNode f ON ri.fileNodeId = f.id
            WHERE f.deleted = false
              AND (ri.ownerUserId = :userId
                   OR (:sharedType IS NOT NULL AND f.spaceType = :sharedType))
            """)
    long countVisibleItems(@Param("userId") UUID userId, @Param("sharedType") SpaceType sharedType);

    /**
     * 分页查询用户可见的阅读条目。
     *
     * <p>可见性、条目类型、内容类型、关键词与书架过滤全部下推到 SQL，
     * 只回当前页实体，避免每翻一页都加载并转换整库。</p>
     *
     * @param userId 当前用户标识
     * @param sharedType 共享空间类型
     * @param itemType 条目类型过滤，空串表示不限
     * @param contentKind 内容类型过滤，空串表示不限
     * @param query 标题或作者关键词，空串表示不限
     * @param bookshelfOnly 是否只返回已加入书架的条目
     * @param pageable 分页参数
     * @return 阅读条目分页
     */
    @Query(value = """
            SELECT ri FROM ReaderItem ri
            JOIN FileNode f ON ri.fileNodeId = f.id
            WHERE f.deleted = false
              AND (ri.ownerUserId = :userId
                   OR (:sharedType IS NOT NULL AND f.spaceType = :sharedType))
              AND (:itemType IS NULL OR :itemType = '' OR UPPER(ri.itemType) = UPPER(:itemType))
              AND (:contentKind IS NULL OR :contentKind = '' OR UPPER(ri.contentKind) = UPPER(:contentKind))
              AND (:query IS NULL OR :query = ''
                   OR LOWER(ri.title) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\'
                   OR LOWER(COALESCE(ri.authorName, '')) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\')
              AND (:bookshelfOnly = false OR EXISTS (
                   SELECT b.id FROM ReaderBookshelf b
                   WHERE b.ownerUserId = :userId AND b.readerItemId = ri.id))
            ORDER BY ri.updatedAt DESC, ri.createdAt DESC, ri.id ASC
            """,
            countQuery = """
            SELECT COUNT(ri) FROM ReaderItem ri
            JOIN FileNode f ON ri.fileNodeId = f.id
            WHERE f.deleted = false
              AND (ri.ownerUserId = :userId
                   OR (:sharedType IS NOT NULL AND f.spaceType = :sharedType))
              AND (:itemType IS NULL OR :itemType = '' OR UPPER(ri.itemType) = UPPER(:itemType))
              AND (:contentKind IS NULL OR :contentKind = '' OR UPPER(ri.contentKind) = UPPER(:contentKind))
              AND (:query IS NULL OR :query = ''
                   OR LOWER(ri.title) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\'
                   OR LOWER(COALESCE(ri.authorName, '')) LIKE LOWER(CONCAT('%', :query, '%')) ESCAPE '\\')
              AND (:bookshelfOnly = false OR EXISTS (
                   SELECT b.id FROM ReaderBookshelf b
                   WHERE b.ownerUserId = :userId AND b.readerItemId = ri.id))
            """)
    Page<ReaderItem> findVisibleItemsPage(
            @Param("userId") UUID userId,
            @Param("sharedType") SpaceType sharedType,
            @Param("itemType") String itemType,
            @Param("contentKind") String contentKind,
            @Param("query") String query,
            @Param("bookshelfOnly") boolean bookshelfOnly,
            Pageable pageable);

    /**
     * 按主文件节点查找对当前用户可见的已有条目，共享空间的同一文件对其他用户同样算已导入。
     */
    @Query("""
            SELECT ri FROM ReaderItem ri
            JOIN FileNode f ON ri.fileNodeId = f.id
            WHERE ri.fileNodeId = :fileNodeId
              AND f.deleted = false
              AND (ri.ownerUserId = :userId
                   OR (:sharedType IS NOT NULL AND f.spaceType = :sharedType))
            ORDER BY ri.updatedAt DESC
            """)
    List<ReaderItem> findAccessibleByFileNodeId(
            @Param("userId") UUID userId,
            @Param("fileNodeId") UUID fileNodeId,
            @Param("sharedType") SpaceType sharedType);

    /**
     * 查询共享空间漫画条目作为分卷合并候选。
     *
     * <p>共享漫画的成员来自不同用户，候选不能按条目创建者过滤；空间归属由主文件节点决定。
     */
    @Query("""
            SELECT ri FROM ReaderItem ri
            JOIN FileNode f ON ri.fileNodeId = f.id
            WHERE f.deleted = false
              AND f.spaceType = :sharedType
              AND ri.contentKind = :contentKind
            ORDER BY ri.updatedAt DESC
            """)
    List<ReaderItem> findSharedComicCandidates(
            @Param("sharedType") SpaceType sharedType,
            @Param("contentKind") String contentKind);

    /**
     * 查询当前用户个人空间的漫画条目作为分卷合并候选。
     *
     * <p>私有分卷只并入本人拥有且主文件仍在个人空间的条目，避免把私密文件挂进共享作品。
     */
    @Query("""
            SELECT ri FROM ReaderItem ri
            JOIN FileNode f ON ri.fileNodeId = f.id
            WHERE f.deleted = false
              AND f.spaceType = :personalType
              AND ri.ownerUserId = :ownerUserId
              AND ri.contentKind = :contentKind
            ORDER BY ri.updatedAt DESC
            """)
    List<ReaderItem> findPersonalComicCandidates(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("personalType") SpaceType personalType,
            @Param("contentKind") String contentKind);

    /**
     * 查询用户可见条目（个人空间 + 共享空间）的全部非空内容哈希，用于候选列表去重。
     */
    @Query("""
            SELECT DISTINCT ri.contentHash FROM ReaderItem ri
            JOIN FileNode f ON ri.fileNodeId = f.id
            WHERE f.deleted = false
              AND ri.contentHash IS NOT NULL
              AND (ri.ownerUserId = :userId
                   OR (:sharedType IS NOT NULL AND f.spaceType = :sharedType))
            """)
    List<String> findVisibleContentHashes(
            @Param("userId") UUID userId,
            @Param("sharedType") SpaceType sharedType);

    /**
     * 在给定文件节点中筛出已作为可见条目主文件导入的节点，一次查询完成候选去重。
     */
    @Query("""
            SELECT ri.fileNodeId FROM ReaderItem ri
            JOIN FileNode f ON ri.fileNodeId = f.id
            WHERE f.deleted = false
              AND (ri.ownerUserId = :userId
                   OR (:sharedType IS NOT NULL AND f.spaceType = :sharedType))
              AND ri.fileNodeId IN :fileNodeIds
            """)
    List<UUID> findVisibleMainFileNodeIds(
            @Param("userId") UUID userId,
            @Param("fileNodeIds") Collection<UUID> fileNodeIds,
            @Param("sharedType") SpaceType sharedType);

    /**
     * 对空间作用域与规范化系列名加事务级咨询锁，串行化同一系列并发分卷导入。
     *
     * <p>不同分卷的内容哈希必然不同，{@link #lockContentHash} 挡不住两个人同时把第 1 卷和第 2 卷
     * 各自建条目，只能在系列名维度加锁。
     */
    @Query(value = """
            SELECT pg_advisory_xact_lock(
                hashtextextended(:lockScope || ':' || lower(:seriesName), 0)
            )
            """, nativeQuery = true)
    void lockComicSeries(@Param("lockScope") String lockScope, @Param("seriesName") String seriesName);
}
