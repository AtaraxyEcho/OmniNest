package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaScanBatch;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 自适应媒体批次仓储。 */
public interface MediaScanBatchRepository extends JpaRepository<MediaScanBatch, UUID> {

    Optional<MediaScanBatch> findFirstByOwnerUserIdAndScanRunIdAndPhaseOrderByBatchNoDesc(
            UUID ownerUserId,
            UUID scanRunId,
            String phase
    );

    void deleteByOwnerUserIdAndScanRunIdAndPhase(UUID ownerUserId, UUID scanRunId, String phase);

    /**
     * 按来源批量删除批次统计。
     *
     * <p>批次表只有运行 ID，用子查询一次删完，避免先读出全部运行再逐轮删除。</p>
     *
     * @param librarySourceId 影视库来源 ID
     * @return 删除行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            delete from MediaScanBatch batch
            where batch.scanRunId in (
                select run.id from MediaScanRun run where run.librarySourceId = :librarySourceId
            )
            """)
    int deleteByLibrarySourceId(@Param("librarySourceId") UUID librarySourceId);
}
