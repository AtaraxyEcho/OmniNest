package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoEditVersion;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 照片编辑版本仓储。
 */
public interface PhotoEditVersionRepository extends JpaRepository<PhotoEditVersion, UUID> {

    List<PhotoEditVersion> findByPhotoIdOrderByVersionNumberDesc(UUID photoId);

    Optional<PhotoEditVersion> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    long countByPhotoId(UUID photoId);

    Optional<PhotoEditVersion> findFirstByPhotoIdOrderByVersionNumberDesc(UUID photoId);

    List<PhotoEditVersion> findByPhotoIdIn(Collection<UUID> photoIds);

    /**
     * 按照片 ID 列表批量删除编辑版本
     */
    void deleteByPhotoIdIn(Collection<UUID> photoIds);
}
