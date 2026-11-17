package com.omninest.modules.music.service;

import com.omninest.modules.media.service.MediaCoverContributor;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 音乐域封面贡献者：曲目封面优先，无封面曲目回退同专辑封面。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class MusicCoverContributor implements MediaCoverContributor {

    private final MusicTrackRepository musicTrackRepository;
    private final MusicAlbumRepository musicAlbumRepository;

    @Override
    public void contribute(UUID ownerUserId, List<UUID> fileNodeIds, Map<UUID, UUID> covers) {
        List<MusicTrack> tracks = musicTrackRepository.findByFileNodeIdIn(fileNodeIds);
        if (tracks.isEmpty()) {
            return;
        }
        Set<UUID> albumIdsNeedingFallback = new HashSet<>();
        for (MusicTrack track : tracks) {
            if (track.getCoverFileId() != null) {
                covers.put(track.getFileNodeId(), track.getCoverFileId());
            } else if (track.getAlbumId() != null) {
                albumIdsNeedingFallback.add(track.getAlbumId());
            }
        }
        if (albumIdsNeedingFallback.isEmpty()) {
            return;
        }
        Map<UUID, UUID> albumCovers = new HashMap<>();
        for (MusicAlbum album : musicAlbumRepository.findAllById(albumIdsNeedingFallback)) {
            if (album.getCoverFileId() != null) {
                albumCovers.put(album.getId(), album.getCoverFileId());
            }
        }
        for (MusicTrack track : tracks) {
            if (!covers.containsKey(track.getFileNodeId()) && track.getAlbumId() != null) {
                UUID albumCover = albumCovers.get(track.getAlbumId());
                if (albumCover != null) {
                    covers.put(track.getFileNodeId(), albumCover);
                }
            }
        }
    }
}
