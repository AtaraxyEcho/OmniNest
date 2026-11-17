package com.omninest.modules.media.repository;

import com.omninest.modules.media.domain.MediaPlaybackProgress;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 统一媒体播放进度仓储。
 *
 * @author OmniNest
 */
public interface MediaPlaybackProgressRepository extends JpaRepository<MediaPlaybackProgress, UUID> {
    /**
     * 查询指定用户和媒体类型最近更新的进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @return 最近进度列表
     */
    List<MediaPlaybackProgress> findTop12ByOwnerUserIdAndMediaTypeOrderByUpdatedAtDesc(
            UUID ownerUserId,
            String mediaType
    );

    /**
     * 查询指定媒体的唯一进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @param mediaKey 媒体稳定键
     * @return 播放进度
     */
    Optional<MediaPlaybackProgress> findByOwnerUserIdAndMediaTypeAndMediaKey(
            UUID ownerUserId,
            String mediaType,
            String mediaKey
    );

    /**
     * 按客户端更新时间原子写入进度，旧事件不会覆盖新进度。
     *
     * @param id 新记录 ID
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @param mediaKey 媒体稳定键
     * @param positionSeconds 播放位置
     * @param durationSeconds 媒体时长
     * @param completed 是否完成
     * @param clientUpdatedAt 客户端更新时间
     * @param deviceId 稳定设备标识
     * @param serverUpdatedAt 服务端接收时间
     * @return 成功插入或更新后的记录；旧事件被忽略时为空
     */
    @Query(value = """
            INSERT INTO omni.media_playback_progresses (
                id, owner_user_id, position_seconds, duration_seconds, completed,
                created_at, updated_at, client_updated_at, device_id, version, media_type, media_key
            ) VALUES (
                :id, :ownerUserId, :positionSeconds, :durationSeconds, :completed,
                :serverUpdatedAt, :serverUpdatedAt, :clientUpdatedAt, :deviceId, 0, :mediaType, :mediaKey
            )
            ON CONFLICT (owner_user_id, media_type, media_key) DO UPDATE SET
                position_seconds = EXCLUDED.position_seconds,
                duration_seconds = EXCLUDED.duration_seconds,
                completed = EXCLUDED.completed,
                updated_at = EXCLUDED.updated_at,
                client_updated_at = EXCLUDED.client_updated_at,
                device_id = EXCLUDED.device_id,
                version = media_playback_progresses.version + 1
            WHERE EXCLUDED.client_updated_at > media_playback_progresses.client_updated_at
               OR (
                    EXCLUDED.client_updated_at = media_playback_progresses.client_updated_at
                    AND EXCLUDED.device_id > media_playback_progresses.device_id
               )
            RETURNING id, owner_user_id, video_item_id, position_seconds, duration_seconds,
                completed, created_at, updated_at, client_updated_at, device_id, version,
                media_type, media_key
            """, nativeQuery = true)
    Optional<MediaPlaybackProgress> upsertIfNewer(
            @Param("id") UUID id,
            @Param("ownerUserId") UUID ownerUserId,
            @Param("mediaType") String mediaType,
            @Param("mediaKey") String mediaKey,
            @Param("positionSeconds") long positionSeconds,
            @Param("durationSeconds") long durationSeconds,
            @Param("completed") boolean completed,
            @Param("clientUpdatedAt") Instant clientUpdatedAt,
            @Param("deviceId") String deviceId,
            @Param("serverUpdatedAt") Instant serverUpdatedAt
    );

    /**
     * 统计用户未播完的进度条目数（继续观看口径）。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @return 未完成进度总数
     */
    long countByOwnerUserIdAndMediaTypeAndCompletedFalse(UUID ownerUserId, String mediaType);

    /**
     * 按稳定键前缀查询最近进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @param mediaKeyPrefix 媒体键前缀
     * @param pageable 分页限制
     * @return 匹配进度
     */
    @Query("""
            SELECT p FROM MediaPlaybackProgress p
            WHERE p.ownerUserId = :ownerUserId
              AND p.mediaType = :mediaType
              AND p.mediaKey LIKE CONCAT(:mediaKeyPrefix, '%')
            ORDER BY p.updatedAt DESC
            """)
    List<MediaPlaybackProgress> findLatestByMediaKeyPrefix(
            @Param("ownerUserId") UUID ownerUserId,
            @Param("mediaType") String mediaType,
            @Param("mediaKeyPrefix") String mediaKeyPrefix,
            Pageable pageable
    );

    /**
     * 删除当前用户指定媒体键的进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @param mediaKeys 媒体稳定键
     */
    void deleteByOwnerUserIdAndMediaTypeAndMediaKeyIn(
            UUID ownerUserId,
            String mediaType,
            Collection<String> mediaKeys
    );

    /**
     * 按媒体类型和稳定键批量删除所有用户的进度。
     *
     * @param mediaType 媒体类型
     * @param mediaKeys 媒体稳定键
     */
    @Modifying(clearAutomatically = true)
    @Query("DELETE FROM MediaPlaybackProgress p WHERE p.mediaType = :mediaType AND p.mediaKey IN :mediaKeys")
    void deleteByMediaTypeAndMediaKeyIn(
            @Param("mediaType") String mediaType,
            @Param("mediaKeys") Collection<String> mediaKeys
    );
}
