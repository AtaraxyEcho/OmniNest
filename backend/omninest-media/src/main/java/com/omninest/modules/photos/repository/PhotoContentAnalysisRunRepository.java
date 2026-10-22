package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoContentAnalysisRun;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

/**
 * 照片图像分析运行记录仓储。
 *
 * @author OmniNest
 */
@Repository
public interface PhotoContentAnalysisRunRepository extends JpaRepository<PhotoContentAnalysisRun, UUID> {

    List<PhotoContentAnalysisRun> findByOwnerUserIdAndPhotoIdAndStatus(
            UUID ownerUserId,
            UUID photoId,
            String status
    );

    PhotoContentAnalysisRun findTopByOwnerUserIdAndPhotoIdAndStatusOrderByCreatedAtDesc(
            UUID ownerUserId,
            UUID photoId,
            String status
    );

    Optional<PhotoContentAnalysisRun>
            findFirstByOwnerUserIdAndContentHashAndPipelineVersionAndStatusOrderByCompletedAtDesc(
                    UUID ownerUserId,
                    String contentHash,
                    String pipelineVersion,
                    String status
            );

    void deleteByPhotoIdIn(Collection<UUID> photoIds);
}
