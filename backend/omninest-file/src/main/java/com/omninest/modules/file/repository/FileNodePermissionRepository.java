package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileNodePermission;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FileNodePermissionRepository extends JpaRepository<FileNodePermission, UUID> {

    Optional<FileNodePermission> findByFileNodeIdAndGranteeUserIdIsNull(UUID fileNodeId);

    Optional<FileNodePermission> findByFileNodeIdAndGranteeUserId(UUID fileNodeId, UUID granteeUserId);

    List<FileNodePermission> findByFileNodeId(UUID fileNodeId);

    @Query("""
            SELECT p FROM FileNodePermission p
            WHERE p.fileNodeId IN :fileIds AND (p.granteeUserId = :userId OR p.granteeUserId IS NULL)
            """)
    List<FileNodePermission> findByFileIdsAndUserIdOrGlobal(
            @Param("fileIds") List<UUID> fileIds,
            @Param("userId") UUID userId);

    void deleteByFileNodeId(UUID fileNodeId);

    /**
     * 删除授予指定用户的全部细粒度权限行（用户删除时清理）。
     *
     * @param granteeUserId 被授权用户 ID
     */
    @Modifying
    @Query("DELETE FROM FileNodePermission p WHERE p.granteeUserId = :granteeUserId")
    void deleteByGranteeUserId(@Param("granteeUserId") UUID granteeUserId);

    @Modifying
    @Query("DELETE FROM FileNodePermission p WHERE p.fileNodeId IN :fileIds")
    void deleteByFileNodeIdIn(@Param("fileIds") List<UUID> fileIds);

    @Modifying
    @Query("DELETE FROM FileNodePermission p WHERE p.fileNodeId IN (SELECT n.id FROM FileNode n WHERE n.parentId = :folderId)")
    void deleteByParentFolderId(@Param("folderId") UUID folderId);
}
