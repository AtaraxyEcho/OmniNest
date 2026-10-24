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
     * 判断对象是否已被其它文件节点作为历史版本引用。
     *
     * @param objectId 文件对象 ID
     * @param fileNodeId 允许持有该引用的节点 ID
     * @return 其它节点是否已引用
     */
    boolean existsByObjectIdAndFileNodeIdNot(UUID objectId, UUID fileNodeId);

    /**
     * 批量查询仍由未进入任何永久删除任务的历史版本引用的对象。
     *
     * <p>与节点引用同口径：已挂到其他 purge 任务的版本行也会被物理清理，
     * 不能在规划阶段被当作外部引用。</p>
     *
     * @param objectIds 待检查对象 ID
     * @return 仍存在未删除任务外版本引用的对象 ID
     */
    @Query("""
            select distinct version.objectId
            from FileVersion version
            where version.objectId in :objectIds
              and version.fileNodeId in (
                  select node.id from FileNode node where node.purgeTaskId is null
              )
            """)
    List<UUID> findObjectIdsReferencedByUnpurgedNodes(
            @Param("objectIds") Collection<UUID> objectIds
    );

    /**
     * 批量查询仍被任意历史版本引用的对象，用于最终清理 file_objects 行。
     *
     * @param objectIds 待检查对象 ID
     * @return 仍存在版本引用的对象 ID
     */
    @Query("""
            select distinct version.objectId
            from FileVersion version
            where version.objectId in :objectIds
            """)
    List<UUID> findObjectIdsInUse(@Param("objectIds") Collection<UUID> objectIds);

    long countByObjectId(UUID objectId);

    void deleteByFileNodeIdIn(Collection<UUID> fileNodeIds);
}
