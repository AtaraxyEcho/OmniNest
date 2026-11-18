package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoItem;
import jakarta.persistence.LockModeType;
import java.time.Instant;
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
 * 照片条目仓储接口。
 *
 * <p>查询按浏览、时间线、回收站与关系图谱拆到独立片段接口，
 * 由本接口组合后对业务服务保持原方法集不变。</p>
 *
 * <p>片段接口一律不加 {@code @NoRepositoryBean}：Spring Data 的片段探测会排除带该注解的接口，
 * 其方法随之退回派生查询解析，像 {@link PhotoItemImportLockQuery} 这种依赖
 * {@code *Impl} 自定义实现的方法会直接让上下文启动失败。该约定由
 * {@code RepositoryFragmentArchitectureTest} 守护。</p>
 *
 * @author OmniNest
 */
public interface PhotoItemRepository extends JpaRepository<PhotoItem, UUID>,
        PhotoItemBrowseQueries,
        PhotoItemTimelineQueries,
        PhotoItemTrashQueries,
        PhotoItemRelationQueries,
        PhotoItemImportLockQuery {

    /**
     * 按用户查询照片列表，按创建时间倒序
     */
    @Query("""
            SELECT photo FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId AND file.deleted = false
              AND photo.deletedAt IS NULL
            ORDER BY photo.createdAt DESC
            """)
    List<PhotoItem> findByOwnerUserIdOrderByCreatedAtDesc(@Param("ownerUserId") UUID ownerUserId);

    /**
     * 按用户和ID查询单张照片
     */
    @Query("""
            SELECT photo FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId AND photo.id = :id AND file.deleted = false
              AND photo.deletedAt IS NULL
            """)
    Optional<PhotoItem> findByOwnerUserIdAndId(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("id") UUID id
    );

    /**
     * 编辑版本落库前重新加载照片并加行锁。
     *
     * <p>编辑解码与对象存储写入都在事务外完成，跨事务传入的实体已游离；
     * 必须在写事务内重新读取受管实例，否则 {@code save} 走 merge 后版本号不会回写。
     * 行锁同时串行化同一照片的版本号分配。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param id 照片 ID
     * @return 受管照片实体
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            SELECT photo FROM PhotoItem photo
            WHERE photo.ownerUserId = :ownerUserId AND photo.id = :id
              AND photo.deletedAt IS NULL
            """)
    Optional<PhotoItem> findForVersionUpdate(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("id") UUID id
    );

    /**
     * 批量查询用户拥有的活动照片。
     *
     * @param ownerUserId 用户标识
     * @param ids 照片标识
     * @return 活动照片
     */
    @Query("""
            SELECT photo FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId AND photo.id IN :ids AND file.deleted = false
              AND photo.deletedAt IS NULL
            """)
    List<PhotoItem> findActiveByOwnerUserIdAndIdIn(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("ids") Collection<UUID> ids
    );

    /**
     * 批量查询用户拥有的照片，含已在回收站的照片（批量移入回收站需要逐项判定幂等）。
     *
     * @param ownerUserId 用户标识
     * @param ids 照片标识
     * @return 该用户拥有的照片
     */
    List<PhotoItem> findByOwnerUserIdAndIdIn(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("ids") Collection<UUID> ids
    );

    /**
     * 按用户和文件节点ID查询照片
     */
    Optional<PhotoItem> findByOwnerUserIdAndFileNodeId(UUID ownerUserId, UUID fileNodeId);

    /**
     * 判断用户是否已有同内容的有效媒体条目。
     *
     * @param ownerUserId 媒体所有者
     * @param contentHash 内容 SHA-256
     * @return 已存在时返回 true
     */
    @Query(value = """
            SELECT EXISTS (
                SELECT 1
                  FROM omni.photo_items p
                  JOIN omni.file_nodes f ON f.id = p.file_node_id
                 WHERE p.owner_user_id = :ownerUserId
                   AND f.is_deleted = false
                   AND p.deleted_at IS NULL
                   AND LOWER(p.provider_metadata ->> 'contentHash') = LOWER(:contentHash)
            )
            """, nativeQuery = true)
    boolean existsActiveByOwnerUserIdAndContentHash(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("contentHash") String contentHash
    );

    /**
     * 查询用户所有照片的文件节点ID列表
     */
    @Query("""
            SELECT p.fileNodeId FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
            """)
    List<UUID> findFileNodeIdsByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    /**
     * 按用户和文件节点ID批量查询照片
     */
    List<PhotoItem> findByOwnerUserIdAndFileNodeIdIn(UUID ownerUserId, List<UUID> fileNodeIds);

    /**
     * 按文件节点批量查询全部照片。
     *
     * @param fileNodeIds 文件节点 ID
     * @return 照片
     */
    List<PhotoItem> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    /**
     * 按用户和封面文件ID批量查询照片
     */
    List<PhotoItem> findByOwnerUserIdAndCoverFileIdIn(UUID ownerUserId, Collection<UUID> coverFileIds);

    /**
     * 按封面文件批量查询全部照片。
     *
     * @param coverFileIds 封面文件节点 ID
     * @return 照片
     */
    List<PhotoItem> findByCoverFileIdIn(Collection<UUID> coverFileIds);

    /**
     * 按当前活动文件批量查询照片，供永久删除后的编辑产物引用清理。
     *
     * @param activeFileIds 活动文件节点 ID
     * @return 照片
     */
    List<PhotoItem> findByActiveFileIdIn(Collection<UUID> activeFileIds);

    /**
     * 按运动视频节点批量查询照片，供永久删除后的动态照片引用清理。
     *
     * @param motionVideoFileNodeIds 运动视频文件节点 ID
     * @return 照片
     */
    List<PhotoItem> findByMotionVideoFileNodeIdIn(Collection<UUID> motionVideoFileNodeIds);

    /**
     * 统计用户照片数量
     */
    @Query("""
            SELECT COUNT(photo) FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId AND file.deleted = false
              AND photo.deletedAt IS NULL
            """)
    long countByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    @Query("""
            SELECT COUNT(photo) FROM PhotoItem photo
            JOIN FileNode file ON photo.fileNodeId = file.id
            WHERE photo.ownerUserId = :ownerUserId
              AND file.deleted = false
              AND photo.deletedAt IS NULL
              AND photo.createdAt >= :since
              AND (photo.format IS NULL OR LOWER(photo.format) NOT IN :videoFormats)
            """)
    long countActivePhotosCreatedSince(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("videoFormats") Collection<String> videoFormats,
            @Param("since") Instant since
    );

    /** 按文件扩展名统计用户导入到 Photos 的视频条目。 */
    long countByOwnerUserIdAndFormatIn(UUID ownerUserId, Collection<String> formats);

    /**
     * 分页查询用户照片标识，供长时间批处理控制单批内存占用。
     *
     * @param ownerUserId 用户标识
     * @param pageable 分页参数
     * @return 照片标识分页
     */
    @Query("""
            SELECT p.id FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
              AND p.deletedAt IS NULL
            """)
    Page<UUID> findIdsByOwnerUserId(
            @Param("ownerUserId") UUID ownerUserId,
            Pageable pageable
    );

    /**
     * 查询用户近期拍摄的照片（按拍摄时间倒序）
     */
    @Query("""
            SELECT p FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
              AND p.deletedAt IS NULL
              AND p.dateTaken IS NOT NULL
            ORDER BY p.dateTaken DESC
            """)
    List<PhotoItem> findRecentByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);

    /**
     * 按拍摄时间范围查询用户照片
     */
    @Query("""
            SELECT p FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
              AND p.deletedAt IS NULL
              AND p.dateTaken >= :from AND p.dateTaken < :to
            ORDER BY p.dateTaken DESC
            """)
    List<PhotoItem> findByOwnerUserIdAndDateTakenBetween(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("from") Instant from,
            @Param("to") Instant to);

    /**
     * 查询用户最新的N张照片
     */
    @Query("""
            SELECT p FROM PhotoItem p
            JOIN FileNode file ON p.fileNodeId = file.id
            WHERE p.ownerUserId = :ownerUserId AND file.deleted = false
              AND p.deletedAt IS NULL
            ORDER BY p.createdAt DESC
            LIMIT :limit
            """)
    List<PhotoItem> findTopNByOwnerUserIdOrderByCreatedAtDesc(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("limit") int limit);
}
