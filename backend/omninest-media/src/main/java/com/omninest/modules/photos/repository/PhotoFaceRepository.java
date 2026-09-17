package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoFace;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

/**
 * 照片人脸检测数据访问层。
 */
@Repository
public interface PhotoFaceRepository extends JpaRepository<PhotoFace, UUID> {

    List<PhotoFace> findByPhotoId(UUID photoId);

    List<PhotoFace> findByOwnerUserId(UUID ownerUserId);

    List<PhotoFace> findByClusterId(UUID clusterId);

    long countByClusterId(UUID clusterId);

    /**
     * 查询多张照片的人脸检测数据。
     *
     * @param photoIds 照片 ID 集合
     * @return 人脸检测数据
     */
    List<PhotoFace> findByPhotoIdIn(Collection<UUID> photoIds);

    /**
     * 批量清空用户人脸的聚类归属，避免重建时 saveAll 全表。
     *
     * @param ownerUserId 用户标识
     * @return 影响行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update PhotoFace face set face.clusterId = null where face.ownerUserId = :ownerUserId")
    int clearClusterIdsByOwnerUserId(@Param("ownerUserId") UUID ownerUserId);
}
