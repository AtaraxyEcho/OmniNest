package com.omninest.modules.reader.repository;

import com.omninest.modules.reader.domain.ReaderProgress;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 阅读进度仓储。
 */
public interface ReaderProgressRepository extends JpaRepository<ReaderProgress, UUID> {

    Optional<ReaderProgress> findByOwnerUserIdAndReaderItemId(UUID ownerUserId, UUID readerItemId);

    /**
     * 批量查询用户在指定条目上的进度记录。
     */
    List<ReaderProgress> findByOwnerUserIdAndReaderItemIdIn(UUID ownerUserId, Collection<UUID> readerItemIds);

    /**
     * 统计用户已完成（进度 >= 指定值）的阅读条目数。
     */
    long countByOwnerUserIdAndProgressPercentGreaterThanEqual(UUID ownerUserId, BigDecimal percent);

    /**
     * 查询用户阅读中（low < 进度 < high）的进度记录。
     */
    List<ReaderProgress> findByOwnerUserIdAndProgressPercentGreaterThanAndProgressPercentLessThan(
            UUID ownerUserId, BigDecimal low, BigDecimal high);

    void deleteByOwnerUserIdAndReaderItemIdIn(UUID ownerUserId, Collection<UUID> readerItemIds);

    void deleteByReaderItemIdIn(Collection<UUID> readerItemIds);

    /**
     * 原生 Upsert：按客户端上报时间写入阅读进度，绕过乐观锁。
     *
     * <p>{@code ON CONFLICT} 保证并发下的幂等性；{@code WHERE} 只允许不早于已存记录的上报
     * 生效，离线排队的旧上报因此不会覆盖其他设备刚写入的位置。已存记录缺少上报时间时
     * 视为无信息并放行，避免围栏把首次写入永久挡在门外。
     *
     * @return 受影响行数；0 表示本次上报被更新的记录拒绝
     */
    @Modifying
    @Query(value = """
            INSERT INTO omni.reader_progress
                (id, owner_user_id, reader_item_id, char_offset, progress_percent,
                 reading_mode, chapter_id, page_id, page_index, page_fingerprint,
                 source_id, source_page_index, catalog_key, manifest_version, intra_page_offset,
                 client_updated_at, updated_at, version)
            VALUES
                (gen_random_uuid(), :ownerUserId, :readerItemId, :charOffset, :progressPercent,
                 :readingMode, :chapterId, :pageId, :pageIndex, :pageFingerprint,
                 :sourceId, :sourcePageIndex, :catalogKey, :manifestVersion, :intraPageOffset,
                 :clientUpdatedAt, now(), 1)
            ON CONFLICT (owner_user_id, reader_item_id)
            DO UPDATE SET char_offset         = EXCLUDED.char_offset,
                          progress_percent    = EXCLUDED.progress_percent,
                          reading_mode        = EXCLUDED.reading_mode,
                          chapter_id          = EXCLUDED.chapter_id,
                          page_id             = EXCLUDED.page_id,
                          page_index          = EXCLUDED.page_index,
                          page_fingerprint    = EXCLUDED.page_fingerprint,
                          source_id           = EXCLUDED.source_id,
                          source_page_index   = EXCLUDED.source_page_index,
                          catalog_key         = EXCLUDED.catalog_key,
                          manifest_version    = EXCLUDED.manifest_version,
                          intra_page_offset   = EXCLUDED.intra_page_offset,
                          client_updated_at   = EXCLUDED.client_updated_at,
                          updated_at          = now(),
                          version             = omni.reader_progress.version + 1
            WHERE omni.reader_progress.client_updated_at IS NULL
               OR EXCLUDED.client_updated_at >= omni.reader_progress.client_updated_at
            """, nativeQuery = true)
    int upsertProgress(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("readerItemId") UUID readerItemId,
            @Param("charOffset") long charOffset,
            @Param("progressPercent") BigDecimal progressPercent,
            @Param("readingMode") String readingMode,
            @Param("chapterId") String chapterId,
            @Param("pageId") UUID pageId,
            @Param("pageIndex") Integer pageIndex,
            @Param("pageFingerprint") String pageFingerprint,
            @Param("sourceId") UUID sourceId,
            @Param("sourcePageIndex") Integer sourcePageIndex,
            @Param("catalogKey") String catalogKey,
            @Param("manifestVersion") Integer manifestVersion,
            @Param("intraPageOffset") Double intraPageOffset,
            @Param("clientUpdatedAt") Instant clientUpdatedAt);
}

