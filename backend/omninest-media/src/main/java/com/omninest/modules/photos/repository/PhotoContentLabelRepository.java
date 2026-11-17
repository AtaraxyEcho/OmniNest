package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoContentLabel;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

/**
 * 照片图像分析标签仓储。
 *
 * @author OmniNest
 */
@Repository
public interface PhotoContentLabelRepository extends JpaRepository<PhotoContentLabel, UUID> {

    void deleteByRunId(UUID runId);

    void deleteByOwnerUserIdAndPhotoId(UUID ownerUserId, UUID photoId);

    void deleteByPhotoIdIn(Collection<UUID> photoIds);

    List<PhotoContentLabel> findByOwnerUserIdAndPhotoIdAndRunId(UUID ownerUserId, UUID photoId, UUID runId);

    List<PhotoContentLabel> findByOwnerUserIdAndPhotoIdAndStateOrderByNamespaceAscLabelCodeAsc(
            UUID ownerUserId,
            UUID photoId,
            String state
    );

    /**
     * 批量查询指定运行下的标签，供索引批处理避免逐张查询。
     */
    List<PhotoContentLabel> findByOwnerUserIdAndPhotoIdInAndRunIdIn(
            UUID ownerUserId,
            Collection<UUID> photoIds,
            Collection<UUID> runIds
    );

    List<PhotoContentLabel> findByOwnerUserIdAndPhotoIdInAndStateOrderByNamespaceAscLabelCodeAsc(
            UUID ownerUserId,
            Collection<UUID> photoIds,
            String state
    );
}
