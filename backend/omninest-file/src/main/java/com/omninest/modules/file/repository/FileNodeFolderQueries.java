package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.SpaceType;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 文件目录与共享筛选查询片段；由 {@link FileNodeRepository} 组合后对外暴露。
 *
 * <p>不标注 {@code @NoRepositoryBean}，保持与 {@code RepositoryFragmentArchitectureTest}
 * 及 Spring Data 片段解析契约一致。</p>
 *
 * @author OmniNest
 */
public interface FileNodeFolderQueries {

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.spaceType = :spaceType
              AND n.parentId IS NULL
              AND n.deleted = false
              AND n.nodeType = 'FOLDER'
              AND (n.sourceType IS NULL OR n.sourceType NOT IN ('DERIVED', 'LOCAL_FILESYSTEM'))
            """)
    Page<FileNode> findVisiblePersonalRootFolders(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("spaceType") SpaceType spaceType,
            Pageable pageable);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.ownerUserId = :ownerUserId
              AND n.parentId = :parentId
              AND n.deleted = false
              AND n.nodeType = 'FOLDER'
              AND (n.sourceType IS NULL OR n.sourceType NOT IN ('DERIVED', 'LOCAL_FILESYSTEM'))
            """)
    Page<FileNode> findVisiblePersonalChildFolders(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("parentId") UUID parentId,
            Pageable pageable);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.spaceType = :spaceType
              AND n.parentId IS NULL
              AND n.deleted = false
              AND n.nodeType = 'FOLDER'
              AND (n.sourceType IS NULL OR n.sourceType <> 'DERIVED')
            """)
    Page<FileNode> findVisibleSharedRootFolders(
            @Param("spaceType") SpaceType spaceType,
            Pageable pageable);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.spaceType = :spaceType
              AND n.parentId = :parentId
              AND n.deleted = false
              AND n.nodeType = 'FOLDER'
              AND (n.sourceType IS NULL OR n.sourceType <> 'DERIVED')
            """)
    Page<FileNode> findVisibleSharedChildFolders(
            @Param("spaceType") SpaceType spaceType,
            @Param("parentId") UUID parentId,
            Pageable pageable);

    @Query("""
            SELECT n FROM FileNode n
            WHERE n.spaceType = :spaceType
              AND n.deleted = false
              AND (n.sourceType IS NULL OR n.sourceType <> 'DERIVED')
              AND (:onlyFolders = false OR n.nodeType = 'FOLDER')
              AND (:onlyFiles = false OR n.nodeType = 'FILE')
              AND (:uploadedBy IS NULL OR n.uploadedBy = :uploadedBy)
              AND (:parentId IS NULL OR n.parentId = :parentId)
            """)
    Page<FileNode> findVisibleSharedFiltered(
            @Param("spaceType") SpaceType spaceType,
            @Param("parentId") UUID parentId,
            @Param("onlyFolders") boolean onlyFolders,
            @Param("onlyFiles") boolean onlyFiles,
            @Param("uploadedBy") UUID uploadedBy,
            Pageable pageable);
}
