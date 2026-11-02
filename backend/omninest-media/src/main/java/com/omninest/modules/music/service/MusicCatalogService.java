package com.omninest.modules.music.service;

import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicArtist;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicArtistRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class MusicCatalogService {
    private final MusicTrackRepository trackRepository;
    private final MusicAlbumRepository albumRepository;
    private final MusicArtistRepository artistRepository;

    @Transactional(rollbackFor = Exception.class)
    public MusicArtist resolveArtist(
            UUID ownerUserId,
            String artistName,
            String musicBrainzArtistId,
            Map<String, Object> providerMetadata
    ) {
        Optional<MusicArtist> existingArtist = findArtist(ownerUserId, musicBrainzArtistId, artistName);
        MusicArtist artist = existingArtist.orElseGet(() -> {
            log.debug("解析艺术家: name={} (新建)", artistName);
            return new MusicArtist();
        });
        artist.setOwnerUserId(ownerUserId);
        if (hasText(artistName)) {
            artist.setName(artistName.trim());
        } else if (!hasText(artist.getName())) {
            artist.setName("Unknown Artist");
        }
        mergeExternalId(artist.getExternalIds(), "musicbrainzArtistId", musicBrainzArtistId);
        mergeProviderMetadata(artist.getProviderMetadata(), providerMetadata);
        return artistRepository.save(artist);
    }

    @Transactional(rollbackFor = Exception.class)
    public MusicAlbum resolveAlbum(
            UUID ownerUserId,
            String albumTitle,
            String artistName,
            LocalDate releaseDate,
            String musicBrainzReleaseId,
            String musicBrainzReleaseGroupId,
            Map<String, Object> providerMetadata
    ) {
        Optional<MusicAlbum> existingAlbum = findAlbum(
                ownerUserId, musicBrainzReleaseId, musicBrainzReleaseGroupId, albumTitle, artistName);
        MusicAlbum album = existingAlbum.orElseGet(() -> {
            log.debug("解析专辑（新建）");
            return new MusicAlbum();
        });
        album.setOwnerUserId(ownerUserId);
        if (hasText(albumTitle)) {
            album.setTitle(albumTitle.trim());
        } else if (!hasText(album.getTitle())) {
            album.setTitle("Unknown Album");
        }
        if (hasText(artistName)) {
            album.setArtistName(artistName.trim());
        } else if (!hasText(album.getArtistName())) {
            album.setArtistName("Various Artists");
        }
        if (releaseDate != null) {
            album.setReleaseDate(releaseDate);
        }
        mergeExternalId(album.getExternalIds(), "musicbrainzReleaseId", musicBrainzReleaseId);
        mergeExternalId(album.getExternalIds(), "musicbrainzReleaseGroupId", musicBrainzReleaseGroupId);
        mergeProviderMetadata(album.getProviderMetadata(), providerMetadata);
        return albumRepository.save(album);
    }

    @Transactional(rollbackFor = Exception.class)
    public void refreshStatistics(UUID ownerUserId, UUID previousArtistId, UUID previousAlbumId, MusicTrack track) {
        refreshArtist(ownerUserId, previousArtistId);
        refreshArtist(ownerUserId, track.getArtistId());
        refreshAlbum(ownerUserId, previousAlbumId);
        refreshAlbum(ownerUserId, track.getAlbumId());
    }

    /**
     * 带缓存的艺术家解析。同一 ownerUserId 下同名艺术家只查库一次。
     * 缓存 key: ownerUserId + "|" + artistName.toLowerCase()
     */
    @Transactional(rollbackFor = Exception.class)
    public MusicArtist resolveArtistCached(
            UUID ownerUserId,
            String artistName,
            String musicBrainzArtistId,
            Map<String, Object> providerMetadata,
            Map<String, MusicArtist> cache
    ) {
        String cacheKey = ownerUserId + "|" + (artistName == null ? "" : artistName.trim().toLowerCase());
        if (cache.containsKey(cacheKey)) {
            return cache.get(cacheKey);
        }
        MusicArtist artist = resolveArtist(ownerUserId, artistName, musicBrainzArtistId, providerMetadata);
        cache.put(cacheKey, artist);
        return artist;
    }

    /**
     * 带缓存的专辑解析。同一 ownerUserId 下同名专辑只查库一次。
     * 缓存 key: ownerUserId + "|" + albumTitle.toLowerCase()
     */
    @Transactional(rollbackFor = Exception.class)
    public MusicAlbum resolveAlbumCached(
            UUID ownerUserId,
            String albumTitle,
            String artistName,
            LocalDate releaseDate,
            String musicBrainzReleaseId,
            String musicBrainzReleaseGroupId,
            Map<String, Object> providerMetadata,
            Map<String, MusicAlbum> cache
    ) {
        String cacheKey = ownerUserId + "|"
                + (artistName == null ? "" : artistName.trim().toLowerCase())
                + "|" + (albumTitle == null ? "" : albumTitle.trim().toLowerCase());
        if (cache.containsKey(cacheKey)) {
            return cache.get(cacheKey);
        }
        MusicAlbum album = resolveAlbum(ownerUserId, albumTitle, artistName, releaseDate,
                musicBrainzReleaseId, musicBrainzReleaseGroupId, providerMetadata);
        cache.put(cacheKey, album);
        return album;
    }

    /**
     * 批量刷新统计。对每个唯一 ID 只执行一次刷新。
     */
    @Transactional(rollbackFor = Exception.class)
    public void refreshStatisticsBatch(UUID ownerUserId, Set<UUID> artistIds, Set<UUID> albumIds) {
        // 批量更新收敛为两条 SQL：逐条 find/count/sum/save 在整库扫描时会产生 4N 次往返。
        if (artistIds != null && !artistIds.isEmpty()) {
            artistRepository.refreshStatisticsBatch(ownerUserId, artistIds);
        }
        if (albumIds != null && !albumIds.isEmpty()) {
            albumRepository.refreshStatisticsBatch(ownerUserId, albumIds);
        }
    }

    private Optional<MusicArtist> findArtist(UUID ownerUserId, String musicBrainzArtistId, String artistName) {
        if (hasText(musicBrainzArtistId)) {
            Optional<MusicArtist> artist = artistRepository.findByOwnerUserIdAndMusicBrainzArtistId(
                    ownerUserId,
                    musicBrainzArtistId.trim()
            );
            if (artist.isPresent()) {
                return artist;
            }
        }
        if (hasText(artistName)) {
            return artistRepository.findByOwnerUserIdAndNameIgnoreCase(ownerUserId, artistName.trim());
        }
        return Optional.empty();
    }

    private Optional<MusicAlbum> findAlbum(
            UUID ownerUserId,
            String musicBrainzReleaseId,
            String musicBrainzReleaseGroupId,
            String albumTitle,
            String artistName
    ) {
        if (hasText(musicBrainzReleaseId)) {
            Optional<MusicAlbum> album = albumRepository.findByOwnerUserIdAndMusicBrainzReleaseId(
                    ownerUserId,
                    musicBrainzReleaseId.trim()
            );
            if (album.isPresent()) {
                return album;
            }
        }
        if (hasText(musicBrainzReleaseGroupId)) {
            Optional<MusicAlbum> album = albumRepository.findByOwnerUserIdAndMusicBrainzReleaseGroupId(
                    ownerUserId,
                    musicBrainzReleaseGroupId.trim()
            );
            if (album.isPresent()) {
                return album;
            }
        }
        if (hasText(albumTitle)) {
            // 专辑身份包含艺术家：同名专辑在两位歌手之间必须隔离，不能回退到
            // 单值 findByName 查询（多行会抛 IncorrectResultSizeDataAccessException）。
            return hasText(artistName)
                    ? albumRepository.findFirstByOwnerUserIdAndTitleIgnoreCaseAndArtistNameIgnoreCase(
                            ownerUserId, albumTitle.trim(), artistName.trim())
                    : albumRepository.findFirstByOwnerUserIdAndTitleIgnoreCaseAndArtistNameIsNull(
                            ownerUserId, albumTitle.trim());
        }
        return Optional.empty();
    }

    private void refreshArtist(UUID ownerUserId, UUID artistId) {
        if (artistId == null) {
            return;
        }
        artistRepository.findByIdAndOwnerUserId(artistId, ownerUserId).ifPresent(artist -> {
            artist.setTrackCount((int) trackRepository.countByOwnerUserIdAndArtistId(ownerUserId, artistId));
            artist.setAlbumCount((int) trackRepository.countDistinctAlbumIdsByOwnerUserIdAndArtistId(ownerUserId, artistId));
            artistRepository.save(artist);
        });
    }

    private void refreshAlbum(UUID ownerUserId, UUID albumId) {
        if (albumId == null) {
            return;
        }
        albumRepository.findByIdAndOwnerUserId(albumId, ownerUserId).ifPresent(album -> {
            album.setTrackCount((int) trackRepository.countByOwnerUserIdAndAlbumId(ownerUserId, albumId));
            long totalDuration = trackRepository.sumDurationSecondsByOwnerUserIdAndAlbumId(ownerUserId, albumId);
            album.setTotalDuration((int) Math.max(0L, totalDuration));
            albumRepository.save(album);
        });
    }

    private void mergeExternalId(Map<String, Object> externalIds, String key, String value) {
        if (externalIds == null || !hasText(value)) {
            return;
        }
        externalIds.put(key, value.trim());
    }

    private void mergeProviderMetadata(Map<String, Object> providerMetadata, Map<String, Object> metadata) {
        if (providerMetadata == null || metadata == null || metadata.isEmpty()) {
            return;
        }
        Object provider = metadata.get("provider");
        if (provider != null) {
            providerMetadata.put("provider", provider);
        }
        if (metadata.get("coverUrl") != null) {
            providerMetadata.put("coverUrl", metadata.get("coverUrl"));
        }
        if (metadata.get("avatarUrl") != null) {
            providerMetadata.put("avatarUrl", metadata.get("avatarUrl"));
        }
        providerMetadata.put("musicbrainz", new LinkedHashMap<>(metadata));
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }
}
