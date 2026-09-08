package com.omninest.modules.reader.repository;

import com.omninest.modules.reader.domain.ReaderReadingSession;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 阅读会话仓储。
 */
public interface ReaderReadingSessionRepository extends JpaRepository<ReaderReadingSession, UUID> {

    boolean existsByOwnerUserIdAndClientSessionId(UUID ownerUserId, String clientSessionId);

    @Query(value = """
            SELECT COALESCE(SUM(duration_seconds), 0)
            FROM omni.reader_reading_sessions
            WHERE owner_user_id = :ownerUserId
              AND started_at >= :since
            """, nativeQuery = true)
    long sumDurationSecondsSince(@Param("ownerUserId") UUID ownerUserId, @Param("since") Instant since);

    @Query(value = """
            SELECT DISTINCT (started_at + CAST(:offset AS INTERVAL))::date
            FROM omni.reader_reading_sessions
            WHERE owner_user_id = :ownerUserId
              AND started_at >= :since
            ORDER BY 1 DESC
            """, nativeQuery = true)
    List<LocalDate> distinctReadingDaysSince(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("since") Instant since,
            @Param("offset") String utcOffset);

    /**
     * 按本地日聚合最近阅读分钟数。
     */
    @Query(value = """
            SELECT (started_at + CAST(:offset AS INTERVAL))::date AS day,
                   COALESCE(SUM(duration_seconds), 0) / 60 AS minutes
            FROM omni.reader_reading_sessions
            WHERE owner_user_id = :ownerUserId
              AND started_at >= :since
            GROUP BY 1
            ORDER BY 1
            """, nativeQuery = true)
    List<DailyMinutesView> sumDailyMinutesSince(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("since") Instant since,
            @Param("offset") String utcOffset);

    /**
     * 每日阅读分钟数聚合行。
     */
    interface DailyMinutesView {
        LocalDate getDay();

        long getMinutes();
    }

    /**
     * 删除指定条目的所有阅读会话记录。
     */
    @Modifying
    @Query(value = """
            DELETE FROM omni.reader_reading_sessions
            WHERE reader_item_id IN :readerItemIds
            """, nativeQuery = true)
    void deleteByReaderItemIdIn(@Param("readerItemIds") Collection<UUID> readerItemIds);
}
