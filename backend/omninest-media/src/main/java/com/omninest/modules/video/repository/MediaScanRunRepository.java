package com.omninest.modules.video.repository;

import com.omninest.modules.video.domain.MediaScanRun;
import java.util.Collection;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 媒体发现运行仓储。 */
public interface MediaScanRunRepository extends JpaRepository<MediaScanRun, UUID> {

    Optional<MediaScanRun> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<MediaScanRun> findFirstByOwnerUserIdAndLibrarySourceIdOrderByCreatedAtDesc(
            UUID ownerUserId,
            UUID librarySourceId
    );

    Optional<MediaScanRun> findFirstByLibrarySourceIdOrderByCreatedAtDesc(UUID librarySourceId);

    boolean existsByLibrarySourceIdAndStatusIn(UUID librarySourceId, Collection<String> statuses);

    boolean existsByOwnerUserIdAndLibrarySourceIdAndStatusIn(
            UUID ownerUserId,
            UUID librarySourceId,
            Collection<String> statuses
    );

    /**
     * 按来源批量删除运行记录。
     *
     * <p>派生删除会逐行读出再逐条 DELETE，删除来源时行数不可控。</p>
     *
     * @param librarySourceId 影视库来源 ID
     * @return 删除行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from MediaScanRun run where run.librarySourceId = :librarySourceId")
    int deleteByLibrarySourceId(@Param("librarySourceId") UUID librarySourceId);
}
