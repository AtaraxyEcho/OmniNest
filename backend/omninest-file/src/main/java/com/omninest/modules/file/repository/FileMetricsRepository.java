package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.SpaceType;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

/**
 * 文件存储指标仓储，负责文件节点和对象的聚合查询。
 *
 * @author OmniNest
 */
@Repository
public interface FileMetricsRepository extends JpaRepository<FileObject, UUID> {

    /**
     * 按节点类型统计未删除节点数。
     *
     * @param nodeType 节点类型
     * @return 节点数
     */
    @Query("select count(n) from FileNode n where n.nodeType = :nodeType and n.deleted = false")
    long countFileNodesByType(@Param("nodeType") String nodeType);

    /**
     * 统计文件对象数。
     *
     * @return 对象数
     */
    @Query("select count(f) from FileObject f")
    long countFileObjects();

    /**
     * 汇总文件对象字节数。
     *
     * @return 总字节数
     */
    @Query("select coalesce(sum(f.sizeBytes), 0) from FileObject f")
    long sumFileObjectSizeBytes();

    /**
     * 按用户和空间类型统计文件夹数。
     *
     * @param ownerUserId 所有者用户 ID
     * @param spaceType 空间类型
     * @return 文件夹数
     */
    @Query("""
            select count(n)
            from FileNode n
            where n.ownerUserId = :ownerUserId
              and n.spaceType = :spaceType
              and n.deleted = false
              and n.nodeType = 'FOLDER'
              and (n.sourceType is null or n.sourceType not in ('DERIVED', 'LOCAL_FILESYSTEM'))
            """)
    long countFoldersByOwnerUserIdAndSpaceType(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType
    );

    /**
     * 按用户和空间类型统计文件数。
     *
     * @param ownerUserId 所有者用户 ID
     * @param spaceType 空间类型
     * @return 文件数
     */
    @Query("""
            select count(n)
            from FileNode n
            where n.ownerUserId = :ownerUserId
              and n.spaceType = :spaceType
              and n.deleted = false
              and n.nodeType = 'FILE'
              and (n.sourceType is null or n.sourceType not in ('DERIVED', 'LOCAL_FILESYSTEM'))
            """)
    long countFilesByOwnerUserIdAndSpaceType(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType
    );

    /**
     * 按用户和空间类型统计 MIME 类型分布。
     *
     * @param ownerUserId 所有者用户 ID
     * @param spaceType 空间类型
     * @return MIME 类型、文件数和字节数
     */
    @Query("""
            select n.mimeType, count(n), coalesce(sum(n.sizeBytes), 0)
            from FileNode n
            where n.ownerUserId = :ownerUserId
              and n.spaceType = :spaceType
              and n.deleted = false
              and n.nodeType = 'FILE'
              and (n.sourceType is null or n.sourceType not in ('DERIVED', 'LOCAL_FILESYSTEM'))
            group by n.mimeType
            """)
    List<Object[]> aggregateFileStatsByMimeTypeAndSpaceType(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType
    );

    /**
     * 按指定用户汇总个人空间的实际存储用量，口径与配额写入侧一致。
     *
     * <p>写入侧只对用户内容加计配额（上传、转存、复制、背景图原片、照片编辑版本），
     * 系统可重建的派生资产与只读本地影视库索引节点从不加计，因此重算基数必须同样排除，
     * 否则一次夜间对账就会把缩略图、转码与挂载影片全额塞进个人已用配额。</p>
     *
     * <p>两个例外按派生资源路径识别，它们写入时已全额加计：背景图原片
     * {@code /.metadata/BACKDROP/{id}/ORIGINAL/...} 与照片编辑版本
     * {@code /.metadata/PHOTO_ITEM/{id}/EDIT_VERSION/...}。排除它们会让已计费字节在
     * 夜间被抹去，而淘汰/删除时还会再次扣减。谓词与
     * {@code FilePurgeStateService#isQuotaCountedNode} 必须保持同一口径。</p>
     *
     * <p>回收站节点在彻底删除前仍然占用配额，历史版本在上传时按新对象全额加计，
     * 两者都必须计入重算基数；与节点当前对象同引用的版本行不重复计，
     * 因为恢复只在当前对象与版本行之间换位，不产生新的加计。</p>
     *
     * @param ownerUserIds 用户标识集合
     * @return 用户存储用量投影列表
     */
    @Query(value = """
            with node_usage as (
                select n.owner_user_id as user_id, n.size_bytes as bytes
                from omni.file_nodes n
                where n.node_type = 'FILE'
                  and n.space_type = 'PERSONAL'
                  and n.owner_user_id in (:ownerUserIds)
                  and (n.source_type is null
                       or n.source_type not in ('DERIVED', 'LOCAL_FILESYSTEM')
                       or (n.source_type = 'DERIVED' and (
                              n.normalized_path like '/.metadata/BACKDROP/%/ORIGINAL/%'
                           or n.normalized_path like '/.metadata/PHOTO_ITEM/%/EDIT_VERSION/%')))
            ),
            version_usage as (
                select distinct v.file_node_id as node_id, v.object_id as object_id
                from omni.file_versions v
                join omni.file_nodes n on n.id = v.file_node_id
                where n.space_type = 'PERSONAL'
                  and n.owner_user_id in (:ownerUserIds)
                  and (n.source_type is null
                       or n.source_type not in ('DERIVED', 'LOCAL_FILESYSTEM')
                       or (n.source_type = 'DERIVED' and (
                              n.normalized_path like '/.metadata/BACKDROP/%/ORIGINAL/%'
                           or n.normalized_path like '/.metadata/PHOTO_ITEM/%/EDIT_VERSION/%')))
                  and (n.current_object_id is null or n.current_object_id <> v.object_id)
            )
            select u.user_id as "userId", coalesce(sum(u.bytes), 0) as "totalBytes"
            from (
                select user_id, bytes from node_usage
                union all
                select n.owner_user_id, coalesce(f.size_bytes, 0)
                from version_usage vu
                join omni.file_nodes n on n.id = vu.node_id
                left join omni.file_objects f on f.id = vu.object_id
            ) u
            group by u.user_id
            """, nativeQuery = true)
    List<FileUserUsageProjection> sumFileSizeForUsers(
            @Param("ownerUserIds") Collection<UUID> ownerUserIds
    );

    /**
     * 汇总共享空间账本应有的字节数与文件数，口径与个人侧重算一致。
     *
     * <p>未删除的共享文件节点按自身字节计一个文件，历史版本按新版本对象字节加计，
     * 与节点当前对象同引用的版本行不重复计；派生资产与只读本地影视库索引节点从不加计，
     * 背景图原片与照片编辑版本两类不可重建派生写入例外。</p>
     *
     * <p>与 {@code sumFileSizeForUsers} 的唯一差别是回收站：共享账本在软删除时即扣减，
     * 因此重算只看未删除节点，而个人配额在彻底删除前仍然占用。</p>
     *
     * @return 共享空间实际字节数与文件数投影
     */
    @Query(value = """
            with quota_nodes as (
                select n.id, n.size_bytes, n.current_object_id
                from omni.file_nodes n
                where n.node_type = 'FILE'
                  and n.space_type = 'SHARED'
                  and n.is_deleted = false
                  and (n.source_type is null
                       or n.source_type not in ('DERIVED', 'LOCAL_FILESYSTEM')
                       or (n.source_type = 'DERIVED' and (
                              n.normalized_path like '/.metadata/BACKDROP/%/ORIGINAL/%'
                           or n.normalized_path like '/.metadata/PHOTO_ITEM/%/EDIT_VERSION/%')))
            ),
            version_usage as (
                select distinct v.file_node_id, v.object_id
                from omni.file_versions v
                join quota_nodes q on q.id = v.file_node_id
                where q.current_object_id is null or q.current_object_id <> v.object_id
            ),
            usage_bytes as (
                select q.size_bytes as bytes from quota_nodes q
                union all
                select coalesce(f.size_bytes, 0)
                from version_usage vu
                left join omni.file_objects f on f.id = vu.object_id
            )
            select coalesce(sum(bytes), 0) as "totalBytes",
                   (select count(*) from quota_nodes) as "totalFiles"
            from usage_bytes
            """, nativeQuery = true)
    SharedSpaceUsageProjection aggregateSharedSpaceUsage();

    /**
     * 汇总指定空间某路径前缀下历史版本对象的字节数。
     *
     * <p>配额账本按"当前对象 + 非当前版本对象"计字节，移动、删除与重算必须同一口径。
     * 回收站节点的账本已在软删除时扣减，因此这里按 deleted 参数选择活动或已删除节点。</p>
     *
     * @param spaceType 空间类型
     * @param prefix 已转义的路径前缀（含结尾分隔符）
     * @param deleted 统计已软删除还是活动节点
     * @return 历史版本对象字节数
     */
    @Query(value = """
            select coalesce(sum(f.size_bytes), 0)
            from omni.file_versions v
            join omni.file_nodes n on n.id = v.file_node_id
            join omni.file_objects f on f.id = v.object_id
            where n.space_type = :spaceType
              and n.is_deleted = :deleted
              and n.normalized_path like concat(:prefix, '%') escape '\\'
              and (n.current_object_id is null or n.current_object_id <> v.object_id)
            """, nativeQuery = true)
    long sumVersionBytesUnderPathInSpace(
            @Param("spaceType") String spaceType,
            @Param("prefix") String prefix,
            @Param("deleted") boolean deleted);

    /**
     * 汇总指定用户个人空间某路径前缀下历史版本对象的字节数。
     *
     * @param ownerUserId 所有者用户 ID
     * @param prefix 已转义的路径前缀（含结尾分隔符）
     * @param deleted 统计已软删除还是活动节点
     * @return 历史版本对象字节数
     */
    @Query(value = """
            select coalesce(sum(f.size_bytes), 0)
            from omni.file_versions v
            join omni.file_nodes n on n.id = v.file_node_id
            join omni.file_objects f on f.id = v.object_id
            where n.owner_user_id = :ownerUserId
              and n.space_type = 'PERSONAL'
              and n.is_deleted = :deleted
              and n.normalized_path like concat(:prefix, '%') escape '\\'
              and (n.current_object_id is null or n.current_object_id <> v.object_id)
            """, nativeQuery = true)
    long sumVersionBytesUnderPathByOwner(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("prefix") String prefix,
            @Param("deleted") boolean deleted);

    /**
     * 汇总单个文件节点除当前对象外的历史版本字节数。
     *
     * @param fileNodeId 文件节点 ID
     * @param spaceType 空间类型
     * @param deleted 统计已软删除还是活动节点
     * @return 历史版本对象字节数
     */
    @Query(value = """
            select coalesce(sum(f.size_bytes), 0)
            from omni.file_versions v
            join omni.file_nodes n on n.id = v.file_node_id
            join omni.file_objects f on f.id = v.object_id
            where n.id = :fileNodeId
              and n.space_type = :spaceType
              and n.is_deleted = :deleted
              and (n.current_object_id is null or n.current_object_id <> v.object_id)
            """, nativeQuery = true)
    long sumVersionBytesForNode(
            @Param("fileNodeId") UUID fileNodeId,
            @Param("spaceType") String spaceType,
            @Param("deleted") boolean deleted);
}
