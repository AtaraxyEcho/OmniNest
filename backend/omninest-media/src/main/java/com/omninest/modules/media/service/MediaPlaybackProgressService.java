package com.omninest.modules.media.service;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.domain.MediaPlaybackProgress;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.event.MediaProgressChangedEvent;
import com.omninest.modules.media.repository.MediaPlaybackProgressRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 提供跨视频与音乐模块的统一播放进度读写能力。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MediaPlaybackProgressService {
    private final MediaPlaybackProgressRepository repository;
    private final MediaSyncEventService syncEventService;
    private final ApplicationEventPublisher applicationEventPublisher;

    /**
     * 查询指定媒体进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @param mediaKey 媒体稳定键
     * @return 播放进度
     */
    @Transactional(readOnly = true)
    public Optional<MediaPlaybackProgress> find(
            UUID ownerUserId,
            MediaPlaybackType mediaType,
            String mediaKey
    ) {
        return repository.findByOwnerUserIdAndMediaTypeAndMediaKey(
                ownerUserId,
                mediaType.value(),
                mediaKey
        );
    }

    /**
     * 查询指定媒体类型的最近进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @return 最近进度列表
     */
    @Transactional(readOnly = true)
    public List<MediaPlaybackProgress> latest(UUID ownerUserId, MediaPlaybackType mediaType) {
        return repository.findTop12ByOwnerUserIdAndMediaTypeOrderByUpdatedAtDesc(
                ownerUserId,
                mediaType.value()
        );
    }

    /**
     * 统计指定用户未播完的进度总数（继续观看口径）。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @return 未完成进度总数
     */
    @Transactional(readOnly = true)
    public long countIncomplete(UUID ownerUserId, MediaPlaybackType mediaType) {
        return repository.countByOwnerUserIdAndMediaTypeAndCompletedFalse(
                ownerUserId,
                mediaType.value()
        );
    }

    /**
     * 查询指定媒体键前缀下最近的一条进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @param mediaKeyPrefix 媒体键前缀
     * @return 最近进度
     */
    @Transactional(readOnly = true)
    public Optional<MediaPlaybackProgress> latestByPrefix(
            UUID ownerUserId,
            MediaPlaybackType mediaType,
            String mediaKeyPrefix
    ) {
        return repository.findLatestByMediaKeyPrefix(
                ownerUserId,
                mediaType.value(),
                mediaKeyPrefix,
                PageRequest.of(0, 1)
        ).stream().findFirst();
    }

    /**
     * 按服务端接收顺序写入最新进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @param mediaKey 媒体稳定键
     * @param positionSeconds 播放位置秒数
     * @param durationSeconds 媒体总时长秒数
     * @param completed 是否播放完成
     * @return 保存后的进度
     */
    @Transactional(rollbackFor = Exception.class)
    public MediaPlaybackProgress save(
            UUID ownerUserId,
            MediaPlaybackType mediaType,
            String mediaKey,
            long positionSeconds,
            long durationSeconds,
            boolean completed
    ) {
        return save(
                ownerUserId,
                mediaType,
                mediaKey,
                positionSeconds,
                durationSeconds,
                completed,
                Instant.now(),
                "legacy"
        );
    }

    /**
     * 按客户端更新时间原子保存跨设备播放进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param mediaType 媒体类型
     * @param mediaKey 媒体稳定键
     * @param positionSeconds 播放位置秒数
     * @param durationSeconds 媒体总时长秒数
     * @param completed 是否播放完成
     * @param clientUpdatedAt 客户端更新时间
     * @param deviceId 稳定设备标识
     * @return 当前有效进度
     */
    @Transactional(rollbackFor = Exception.class)
    public MediaPlaybackProgress save(
            UUID ownerUserId,
            MediaPlaybackType mediaType,
            String mediaKey,
            long positionSeconds,
            long durationSeconds,
            boolean completed,
            Instant clientUpdatedAt,
            String deviceId
    ) {
        long safeDuration = Math.max(0, durationSeconds);
        long safePosition = Math.max(0, positionSeconds);
        if (safeDuration > 0) {
            safePosition = Math.min(safePosition, safeDuration);
        }
        Instant safeClientUpdatedAt = clientUpdatedAt == null ? Instant.now() : clientUpdatedAt;
        String safeDeviceId = normalizeDeviceId(deviceId);
        Optional<MediaPlaybackProgress> changed = repository.upsertIfNewer(
                UUID.randomUUID(),
                ownerUserId,
                mediaType.value(),
                mediaKey,
                safePosition,
                safeDuration,
                completed,
                safeClientUpdatedAt,
                safeDeviceId,
                Instant.now()
        );
        MediaPlaybackProgress saved = changed.orElseGet(() -> repository
                .findByOwnerUserIdAndMediaTypeAndMediaKey(ownerUserId, mediaType.value(), mediaKey)
                .orElseThrow(() -> new IllegalStateException("播放进度写入后无法读取")));
        if (changed.isPresent()) {
            syncEventService.record(
                    ownerUserId,
                    resolveScope(mediaType),
                    "MEDIA_PLAYBACK_PROGRESS",
                    mediaKey,
                    completed ? SyncAction.COMPLETED : SyncAction.PROGRESS,
                    saved.getVersion(),
                    Map.of(
                            "positionSeconds", safePosition,
                            "durationSeconds", safeDuration,
                            "completed", completed,
                            "clientUpdatedAt", safeClientUpdatedAt.toString(),
                            "deviceId", safeDeviceId
                    )
            );
            applicationEventPublisher.publishEvent(new MediaProgressChangedEvent(ownerUserId, mediaType));
        }
        return saved;
    }

    private String normalizeDeviceId(String deviceId) {
        if (deviceId == null || deviceId.isBlank()) {
            return "legacy";
        }
        String normalized = deviceId.trim();
        return normalized.length() <= 128 ? normalized : normalized.substring(0, 128);
    }

    private SyncScope resolveScope(MediaPlaybackType mediaType) {
        if (mediaType == MediaPlaybackType.MUSIC) {
            return SyncScope.MUSIC;
        }
        if (mediaType == MediaPlaybackType.VIDEO) {
            return SyncScope.VIDEO;
        }
        throw new IllegalArgumentException("不支持的媒体播放类型: " + mediaType);
    }
}
