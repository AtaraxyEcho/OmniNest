package com.omninest.modules.media.service;

import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.repository.MediaPlaybackProgressRepository;
import java.util.Collection;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 统一媒体播放进度清理服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MediaPlaybackCleanupService {
    private final MediaPlaybackProgressRepository playbackProgressRepository;

    /**
     * 删除指定用户和媒体键的播放进度。
     *
     * @param ownerUserId 所有者用户 ID
     * @param mediaType 媒体类型
     * @param mediaKeys 媒体稳定键集合
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteOwned(UUID ownerUserId, MediaPlaybackType mediaType, Collection<String> mediaKeys) {
        if (mediaKeys == null || mediaKeys.isEmpty()) {
            return;
        }
        playbackProgressRepository.deleteByOwnerUserIdAndMediaTypeAndMediaKeyIn(
                ownerUserId,
                mediaType.value(),
                mediaKeys
        );
    }

    /**
     * 删除所有用户指定媒体键的播放进度。
     *
     * @param mediaType 媒体类型
     * @param mediaKeys 媒体稳定键集合
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteAllUsers(MediaPlaybackType mediaType, Collection<String> mediaKeys) {
        if (mediaKeys == null || mediaKeys.isEmpty()) {
            return;
        }
        playbackProgressRepository.deleteByMediaTypeAndMediaKeyIn(mediaType.value(), mediaKeys);
    }
}
