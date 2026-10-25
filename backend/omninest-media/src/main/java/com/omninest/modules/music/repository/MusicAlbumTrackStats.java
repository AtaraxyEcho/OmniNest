package com.omninest.modules.music.repository;

import java.util.UUID;

/**
 * 专辑存活曲目统计投影。
 *
 * @author OmniNest
 */
public interface MusicAlbumTrackStats {

    UUID getAlbumId();

    long getTrackCount();

    long getTotalDuration();
}
