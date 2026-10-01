package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoAlbum;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 照片相册仓储接口
 */
public interface PhotoAlbumRepository extends JpaRepository<PhotoAlbum, UUID> {

    /**
     * 按用户查询相册列表，按更新时间倒序
     */
    List<PhotoAlbum> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);

    /**
     * 按用户分页查询相册列表，按更新时间倒序，供相册分页列表使用
     */
    Page<PhotoAlbum> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId, Pageable pageable);

    /**
     * 按用户和ID查询单个相册
     */
    Optional<PhotoAlbum> findByOwnerUserIdAndId(UUID ownerUserId, UUID id);

    /**
     * 统计用户相册数量
     */
    long countByOwnerUserId(UUID ownerUserId);

    /**
     * 按用户和 ID 列表查询相册
     */
    List<PhotoAlbum> findAllByIdInAndOwnerUserId(Collection<UUID> ids, UUID ownerUserId);

    /**
     * 按用户和 ID 列表批量删除相册
     */
    void deleteByOwnerUserIdAndIdIn(UUID ownerUserId, Collection<UUID> ids);
}
