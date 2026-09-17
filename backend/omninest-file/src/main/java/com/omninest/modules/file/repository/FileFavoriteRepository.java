package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileFavorite;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FileFavoriteRepository extends JpaRepository<FileFavorite, UUID> {
    List<FileFavorite> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId);

    @Query("""
            select f.fileNode.id from FileFavorite f
            where f.ownerUserId = :ownerUserId
            order by f.createdAt desc
            """)
    Page<UUID> findFavoriteNodeIds(@Param("ownerUserId") UUID ownerUserId, Pageable pageable);

    Optional<FileFavorite> findByOwnerUserIdAndFileNode_Id(UUID ownerUserId, UUID fileNodeId);

    boolean existsByOwnerUserIdAndFileNode_Id(UUID ownerUserId, UUID fileNodeId);

    void deleteByOwnerUserIdAndFileNode_IdIn(UUID ownerUserId, Collection<UUID> fileNodeIds);

    /**
     * 按 fileNodeId 删除所有用户的收藏（共享空间文件清理用）。
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM FileFavorite f WHERE f.fileNode.id IN :fileNodeIds")
    void deleteByFileNode_IdIn(@Param("fileNodeIds") Collection<UUID> fileNodeIds);
}
