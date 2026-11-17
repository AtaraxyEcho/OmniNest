package com.omninest.modules.music.service;

import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackQueueDto;
import java.util.Optional;
import java.util.UUID;

/**
 * 定义用户播放队列快照的存取契约。
 *
 * @author OmniNest
 */
public interface MusicPlaybackQueueStore {

    /**
     * 查询用户最近保存的播放队列快照。
     *
     * @param ownerUserId 所属用户标识
     * @return 播放队列快照
     */
    Optional<MusicPlaybackQueueDto> find(UUID ownerUserId);

    /**
     * 保存用户播放队列快照。
     *
     * @param ownerUserId 所属用户标识
     * @param snapshot 播放队列快照
     */
    void save(UUID ownerUserId, MusicPlaybackQueueDto snapshot);
}
