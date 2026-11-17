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
            SELECT DISTINCT (started_at AT TIME ZONE :zoneId)::date
            FROM omni.reader_reading_sessions
            WHERE owner_user_id = :ownerUserId
              AND started_at >= :since
            ORDER BY 1 DESC
            """, nativeQuery = true)
    List<LocalDate> distinctReadingDaysSince(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("since") Instant since,
            @Param("zoneId") String zoneId);

    /**
     * 在数据库侧按本地日期分组计算历史最长连续阅读天数，避免把全部会话载入应用进程。
     */
    @Query(value = """
            SELECT COALESCE(MAX(streak_length), 0)
            FROM (
                SELECT COUNT(*) AS streak_length
                FROM (
                    SELECT reading_day,
                           reading_day - ROW_NUMBER() OVER (ORDER BY reading_day)::integer AS streak_group
                    FROM (
                        SELECT DISTINCT (started_at AT TIME ZONE :zoneId)::date AS reading_day
                        FROM omni.reader_reading_sessions
                        WHERE owner_user_id = :ownerUserId
                    ) daily_reading_days
                ) grouped_reading_days
                GROUP BY streak_group
            ) streaks
            """, nativeQuery = true)
    long longestReadingStreak(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("zoneId") String zoneId);

    /**
     * 按本地日聚合最近阅读分钟数。
     */
    @Query(value = """
            SELECT (started_at AT TIME ZONE :zoneId)::date AS day,
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
            @Param("zoneId") String zoneId);

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
