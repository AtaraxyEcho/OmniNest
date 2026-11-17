package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoScanJob;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 照片扫描任务仓储接口
 */
public interface PhotoScanJobRepository extends JpaRepository<PhotoScanJob, UUID> {

    /**
     * 按ID和用户查询扫描任务
     */
    Optional<PhotoScanJob> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);
}
