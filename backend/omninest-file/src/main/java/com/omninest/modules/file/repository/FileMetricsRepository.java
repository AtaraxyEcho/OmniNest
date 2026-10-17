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
            group by n.mimeType
            """)
    List<Object[]> aggregateFileStatsByMimeTypeAndSpaceType(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType
    );

    /**
     * 按指定用户汇总个人空间的实际存储用量，口径与配额账本一致。
     * 回收站节点在彻底删除前仍然占用配额，历史版本在上传时按新对象全额加计，
     * 两者都必须计入重算基数；与节点当前对象同引用的版本行不重复计，
     * 因为恢复只在当前对象与版本行之间换位，不产生新的加计。
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
            ),
            version_usage as (
                select distinct v.file_node_id as node_id, v.object_id as object_id
                from omni.file_versions v
                join omni.file_nodes n on n.id = v.file_node_id
                where n.space_type = 'PERSONAL'
                  and n.owner_user_id in (:ownerUserIds)
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
}
