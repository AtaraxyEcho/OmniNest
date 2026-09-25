package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileAccessRecord;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FileAccessRecordRepository extends JpaRepository<FileAccessRecord, UUID> {

    /**
     * 按最近访问时间倒序查询，并预取 FileNode，避免列表映射触发懒加载 N+1。
     */
    @EntityGraph(attributePaths = "fileNode")
    List<FileAccessRecord> findTop50ByOwnerUserIdOrderByLastAccessedAtDesc(UUID ownerUserId);

    Optional<FileAccessRecord> findByOwnerUserIdAndFileNode_Id(UUID ownerUserId, UUID fileNodeId);

    void deleteByOwnerUserIdAndFileNode_IdIn(UUID ownerUserId, Collection<UUID> fileNodeIds);

    /**
     * 按 fileNodeId 删除所有用户的访问记录（共享空间文件清理用）。
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM FileAccessRecord r WHERE r.fileNode.id IN :fileNodeIds")
    void deleteByFileNode_IdIn(@Param("fileNodeIds") Collection<UUID> fileNodeIds);
}
