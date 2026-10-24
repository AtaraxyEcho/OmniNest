package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileAccessRecord;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.SpaceType;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FileAccessRecordRepository extends JpaRepository<FileAccessRecord, UUID> {

    /**
     * 查询用户个人空间内的最近访问节点。
     *
     * <p>空间与删除过滤必须下推数据库：先取 Top N 再在内存剔除共享记录，会让
     * 大量共享空间访问把个人记录挤出查询窗口，最近列表假性清空。</p>
     *
     * @param ownerUserId 用户 ID
     * @param spaceType 目标空间类型
     * @param pageable 分页参数
     * @return 最近访问节点
     */
    @Query("""
            select record.fileNode from FileAccessRecord record
            where record.ownerUserId = :ownerUserId
              and record.fileNode.deleted = false
              and record.fileNode.spaceType = :spaceType
            order by record.lastAccessedAt desc
            """)
    List<FileNode> findRecentNodes(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            Pageable pageable);

    /**
     * 原子累加访问次数。
     *
     * <p>先查后改在并发下载同一文件时会丢失计数；改用唯一键冲突更新，
     * 由数据库在一次语句内完成「首次插入或累加」。</p>
     *
     * @param ownerUserId 用户 ID
     * @param fileNodeId 文件节点 ID
     * @param now 访问时间
     * @return 影响行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            INSERT INTO omni.file_access_records AS existing
                (id, owner_user_id, file_node_id, last_accessed_at, access_count, created_at, updated_at)
            VALUES (gen_random_uuid(), :ownerUserId, :fileNodeId, :now, 1, :now, :now)
            ON CONFLICT (owner_user_id, file_node_id)
            DO UPDATE SET access_count = existing.access_count + 1,
                          last_accessed_at = EXCLUDED.last_accessed_at,
                          updated_at = EXCLUDED.updated_at
            """, nativeQuery = true)
    int upsertAccess(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("fileNodeId") UUID fileNodeId,
            @Param("now") Instant now);

    void deleteByOwnerUserIdAndFileNode_IdIn(UUID ownerUserId, Collection<UUID> fileNodeIds);

    /**
     * 按 fileNodeId 删除所有用户的访问记录（物理删除清理用）。
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM FileAccessRecord r WHERE r.fileNode.id IN :fileNodeIds")
    void deleteByFileNode_IdIn(@Param("fileNodeIds") Collection<UUID> fileNodeIds);
}
