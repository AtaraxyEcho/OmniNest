package com.omninest.modules.music.service;

import java.util.Optional;

/**
 * 音乐播放短期会话存储。
 *
 * @author OmniNest
 */
public interface MusicPlaybackSessionStore {

    /**
     * 保存播放会话。
     *
     * @param session 播放会话
     */
    void save(MusicPlaybackSession session);

    /**
     * 查询播放会话。
     *
     * @param sessionId 会话标识
     * @return 播放会话
     */
    Optional<MusicPlaybackSession> find(String sessionId);

    /**
     * 删除播放会话。
     *
     * @param sessionId 会话标识
     */
    void delete(String sessionId);
}
