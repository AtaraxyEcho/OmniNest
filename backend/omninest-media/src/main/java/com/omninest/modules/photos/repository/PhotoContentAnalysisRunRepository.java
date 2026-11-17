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

    /**
     * 批量查询一页照片的分析运行记录，按创建时间倒序，供索引批处理取每张的最新成功运行。
     */
    List<PhotoContentAnalysisRun> findByOwnerUserIdAndPhotoIdInAndStatusOrderByCreatedAtDesc(
            UUID ownerUserId,
            Collection<UUID> photoIds,
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
