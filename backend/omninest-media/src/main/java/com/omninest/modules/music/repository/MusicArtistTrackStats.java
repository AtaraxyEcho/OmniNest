package com.omninest.modules.music.repository;

import java.util.UUID;

/**
 * 艺术家存活曲目统计投影。
 *
 * @author OmniNest
 */
public interface MusicArtistTrackStats {

    UUID getArtistId();

    long getTrackCount();

    long getAlbumCount();
}
