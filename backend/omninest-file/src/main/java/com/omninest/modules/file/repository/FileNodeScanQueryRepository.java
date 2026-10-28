package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.SpaceType;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * 全库扫描类任务的文件候选查询。
 *
 * <p>与 {@link FileNodeRepository} 分开维护：分类过滤、派生资产排除、按 ID 游标分页
 * 与歌词放行都是批量扫描专用谓词，独立接口避免通用仓储继续膨胀。所有分页查询按
 * {@code id} 升序游标推进，调用方每批处理完即可释放，不随库规模整表加载。</p>
 *
 * @author OmniNest
 */
public interface FileNodeScanQueryRepository extends Repository<FileNode, UUID> {

    /**
     * 按业务分类与 ID 游标查询用户自有未删除文件。
     *
     * @param ownerUserId 所有者用户 ID
     * @param categories 业务分类集合，不可为空
     * @param afterId 上一批最后一个节点 ID，首批传全零 UUID
     * @param pageable 分页参数
     * @return 匹配节点
     */
    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND (n.sourceType IS NULL OR n.sourceType != 'DERIVED')
              AND n.category IN :categories
              AND n.id > :afterId
            ORDER BY n.id ASC
            """)
    List<FileNode> findOwnedActiveFilesByCategoriesAfterId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("categories") Collection<String> categories,
            @Param("afterId") UUID afterId,
            Pageable pageable);

    /**
     * 统计用户自有、指定业务分类的未删除文件数量，供扫描进度估算。
     *
     * @param ownerUserId 所有者用户 ID
     * @param categories 业务分类集合，不可为空
     * @return 文件数量
     */
    @Query("""
            SELECT count(n) FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND (n.sourceType IS NULL OR n.sourceType != 'DERIVED')
              AND n.category IN :categories
            """)
    long countOwnedActiveFilesByCategories(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("categories") Collection<String> categories);

    /**
     * 按业务分类与 ID 游标查询共享给当前用户且不属于其本人的未删除文件。
     *
     * @param userId 当前用户 ID
     * @param categories 业务分类集合，不可为空
     * @param afterId 上一批最后一个节点 ID，首批传全零 UUID
     * @param pageable 分页参数
     * @return 匹配节点
     */
    @Query("""
            SELECT n FROM FileNode n
            WHERE n.shared = true
              AND n.ownerUserId != :userId
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND (n.sourceType IS NULL OR n.sourceType != 'DERIVED')
              AND n.category IN :categories
              AND n.id > :afterId
            ORDER BY n.id ASC
            """)
    List<FileNode> findSharedFilesByCategoriesAfterId(
            @Param("userId") UUID userId,
            @Param("categories") Collection<String> categories,
            @Param("afterId") UUID afterId,
            Pageable pageable);

    /**
     * 统计共享给当前用户、指定业务分类的未删除文件数量，供扫描进度估算。
     *
     * @param userId 当前用户 ID
     * @param categories 业务分类集合，不可为空
     * @return 文件数量
     */
    @Query("""
            SELECT count(n) FROM FileNode n
            WHERE n.shared = true
              AND n.ownerUserId != :userId
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND (n.sourceType IS NULL OR n.sourceType != 'DERIVED')
              AND n.category IN :categories
            """)
    long countSharedFilesByCategories(
            @Param("userId") UUID userId,
            @Param("categories") Collection<String> categories);

    /**
     * 按路径前缀、业务分类与 ID 游标查询用户自有未删除文件。
     *
     * @param ownerUserId 所有者用户 ID
     * @param spaceType 空间类型
     * @param prefix 已转义的字面量路径前缀
     * @param categories 业务分类集合，不可为空
     * @param afterId 上一批最后一个节点 ID，首批传全零 UUID
     * @param pageable 分页参数
     * @return 匹配节点
     */
    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.spaceType = :spaceType
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND (n.sourceType IS NULL OR n.sourceType != 'DERIVED')
              AND n.category IN :categories
              AND n.normalizedPath LIKE CONCAT(:prefix, '%') escape '\\'
              AND n.id > :afterId
            ORDER BY n.id ASC
            """)
    List<FileNode> findOwnedActiveFilesByPathPrefixAndCategoriesAfterId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix,
            @Param("categories") Collection<String> categories,
            @Param("afterId") UUID afterId,
            Pageable pageable);

    /**
     * 统计用户指定空间与路径前缀下、指定业务分类的未删除文件数量。
     *
     * @param ownerUserId 所有者用户 ID
     * @param spaceType 空间类型
     * @param prefix 已转义的字面量路径前缀
     * @param categories 业务分类集合，不可为空
     * @return 文件数量
     */
    @Query("""
            SELECT count(n) FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.spaceType = :spaceType
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND (n.sourceType IS NULL OR n.sourceType != 'DERIVED')
              AND n.category IN :categories
              AND n.normalizedPath LIKE CONCAT(:prefix, '%') escape '\\'
            """)
    long countOwnedActiveFilesByPathPrefixAndCategories(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            @Param("prefix") String prefix,
            @Param("categories") Collection<String> categories);

    /**
     * 查询用户自有的 {@code .lrc} 歌词文件。
     *
     * <p>歌词无业务分类，单独查询；数量级远小于音频，可与分页音频流并行使用。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @return 歌词文件
     */
    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND (n.sourceType IS NULL OR n.sourceType != 'DERIVED')
              AND lower(n.name) LIKE '%.lrc'
            """)
    List<FileNode> findOwnedLyricFiles(@Param("ownerUserId") UUID ownerUserId);

    /**
     * 查询共享给当前用户且不属于其本人的 {@code .lrc} 歌词文件。
     *
     * @param userId 当前用户 ID
     * @return 歌词文件
     */
    @Query("""
            SELECT n FROM FileNode n
            WHERE n.shared = true
              AND n.ownerUserId != :userId
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND (n.sourceType IS NULL OR n.sourceType != 'DERIVED')
              AND lower(n.name) LIKE '%.lrc'
            """)
    List<FileNode> findSharedLyricFiles(@Param("userId") UUID userId);

    /**
     * 按创建时间倒序取用户自有、指定业务分类的未删除文件，用于有上限的候选列表。
     *
     * @param ownerUserId 所有者用户 ID
     * @param categories 业务分类集合，不可为空
     * @param pageable 分页参数（上限即 pageSize）
     * @return 匹配节点
     */
    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND (n.sourceType IS NULL OR n.sourceType != 'DERIVED')
              AND n.category IN :categories
            ORDER BY n.createdAt DESC, n.id ASC
            """)
    List<FileNode> findOwnedActiveFilesByCategoriesLimited(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("categories") Collection<String> categories,
            Pageable pageable);

    /**
     * 按创建时间倒序取指定空间内、指定业务分类的未删除文件，用于有上限的候选列表。
     *
     * @param spaceType 空间类型
     * @param categories 业务分类集合，不可为空
     * @param pageable 分页参数（上限即 pageSize）
     * @return 匹配节点
     */
    @Query("""
            SELECT n FROM FileNode n
            WHERE n.spaceType = :spaceType
              AND n.deleted = false
              AND n.nodeType = 'FILE'
              AND (n.sourceType IS NULL OR n.sourceType != 'DERIVED')
              AND n.category IN :categories
            ORDER BY n.createdAt DESC, n.id ASC
            """)
    List<FileNode> findSpaceFilesByCategoriesLimited(
            @Param("spaceType") SpaceType spaceType,
            @Param("categories") Collection<String> categories,
            Pageable pageable);
}
