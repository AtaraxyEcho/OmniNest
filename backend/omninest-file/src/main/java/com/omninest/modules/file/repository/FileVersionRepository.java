package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileVersion;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 文件版本仓储。
 *
 * @author OmniNest
 */
public interface FileVersionRepository extends JpaRepository<FileVersion, UUID> {
    List<FileVersion> findByFileNodeIdIn(Collection<UUID> fileNodeIds);

    List<FileVersion> findByFileNodeIdOrderByVersionNoDesc(UUID fileNodeId);

    long countByFileNodeId(UUID fileNodeId);

    @Query("select coalesce(max(v.versionNo), 0) from FileVersion v where v.fileNodeId = :fileNodeId")
    int findMaxVersionNo(@Param("fileNodeId") UUID fileNodeId);

    long countByObjectIdAndFileNodeIdNotIn(UUID objectId, Collection<UUID> excludedFileNodeIds);

    /**
     * 批量查询仍由永久删除任务外历史版本引用的对象。
     *
     * @param objectIds 待检查对象 ID
     * @param taskId 永久删除任务 ID
     * @return 仍存在任务外版本引用的对象 ID
     */
    @Query("""
            select distinct version.objectId
            from FileVersion version
            where version.objectId in :objectIds
              and version.fileNodeId not in (
                  select node.id from FileNode node where node.purgeTaskId = :taskId
              )
            """)
    List<UUID> findObjectIdsReferencedOutsidePurgeTask(
            @Param("objectIds") Collection<UUID> objectIds,
            @Param("taskId") UUID taskId
    );

    /**
     * 统计仍由永久删除任务外版本引用的对象。
     *
     * @param objectId 对象 ID
     * @param taskId 永久删除任务 ID
     * @return 引用数量
     */
    @Query("select count(version) from FileVersion version where version.objectId = :objectId "
            + "and version.fileNodeId not in "
            + "(select node.id from FileNode node where node.purgeTaskId = :taskId)")
    long countObjectReferencesOutsidePurgeTask(
            @Param("objectId") UUID objectId,
            @Param("taskId") UUID taskId
    );

    long countByObjectId(UUID objectId);

    void deleteByFileNodeIdIn(Collection<UUID> fileNodeIds);
}
