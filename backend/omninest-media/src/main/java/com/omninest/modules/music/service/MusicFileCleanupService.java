package com.omninest.modules.music.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.service.FileBusinessReference;
import com.omninest.modules.file.service.FilePurgeParticipant;
import com.omninest.modules.file.service.PurgeContext;
import com.omninest.modules.file.service.PurgeContributionWriter;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.service.MediaFileVisibilitySyncParticipant;
import com.omninest.modules.media.service.MediaPlaybackCleanupService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicArtist;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicAlbumTrackStats;
import com.omninest.modules.music.repository.MusicArtistRepository;
import com.omninest.modules.music.repository.MusicArtistTrackStats;
import com.omninest.modules.music.repository.MusicFavoriteRepository;
import com.omninest.modules.music.repository.MusicPlayHistoryRepository;
import com.omninest.modules.music.repository.MusicPlaylistItemRepository;
import com.omninest.modules.music.repository.MusicPlaylistRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件删除触发的音乐业务数据清理服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicFileCleanupService implements
        FilePurgeParticipant,
        MediaFileVisibilitySyncParticipant {
    private static final String MODULE = "MUSIC";
    private static final String RESOURCE_TYPE = "MUSIC_TRACK";
    private final MusicTrackRepository trackRepository;
    private final MediaPlaybackCleanupService playbackCleanupService;
    private final MusicFavoriteRepository favoriteRepository;
    private final MusicPlayHistoryRepository playHistoryRepository;
    private final MusicPlaylistItemRepository playlistItemRepository;
    private final MusicAlbumRepository albumRepository;
    private final MusicArtistRepository artistRepository;
    private final MusicPlaylistRepository playlistRepository;
    private final MediaSyncEventService syncEventService;
    private final ReadThroughCache readThroughCache;
    private final MusicCoverRetentionService coverRetentionService;

    /**
     * 查询目标文件的本地音乐曲目引用。
     *
     * @param context 删除上下文
     * @return 音乐曲目引用
     */
    @Override
    @Transactional(readOnly = true)
    public List<FileBusinessReference> findBusinessReferences(PurgeContext context) {
        return trackRepository
                .findByFileNodeIdIn(context.fileNodeIds())
                .stream()
                .map(track -> new FileBusinessReference(
                        MODULE,
                        RESOURCE_TYPE,
                        track.getId(),
                        track.getFileNodeId()
                ))
                .toList();
    }

    /**
     * 贡献曲目封面和删除后将成为孤立资源的父级封面。
     *
     * @param context 删除上下文
     * @param writer 资源写入器
     */
    @Override
    @Transactional(readOnly = true)
    public void contribute(PurgeContext context, PurgeContributionWriter writer) {
        Map<UUID, List<MusicTrack>> tracksByOwner = trackRepository.findByFileNodeIdIn(context.fileNodeIds()).stream()
                .collect(Collectors.groupingBy(
                        MusicTrack::getOwnerUserId,
                        LinkedHashMap::new,
                        Collectors.toList()
                ));
        tracksByOwner.forEach((ownerUserId, tracks) -> contributeOwnedTracks(
                ownerUserId,
                tracks,
                writer
        ));
    }

    private void contributeOwnedTracks(
            UUID ownerUserId,
            List<MusicTrack> tracks,
            PurgeContributionWriter writer
    ) {
        List<UUID> trackIds = tracks.stream().map(MusicTrack::getId).toList();
        writer.addFileNodeIds(tracks.stream()
                .map(MusicTrack::getCoverFileId)
                .filter(Objects::nonNull)
                .toList());

        Set<UUID> albumIds = new HashSet<>();
        Set<UUID> artistIds = new HashSet<>();
        tracks.forEach(track -> {
            if (track.getAlbumId() != null) {
                albumIds.add(track.getAlbumId());
            }
            if (track.getArtistId() != null) {
                artistIds.add(track.getArtistId());
            }
        });
        if (!albumIds.isEmpty()) {
            Set<UUID> albumsWithRemainingTracks = new HashSet<>(
                    trackRepository.findAlbumIdsWithRemainingTracks(ownerUserId, albumIds, trackIds));
            writer.addFileNodeIds(albumRepository.findAllByIdInAndOwnerUserId(albumIds, ownerUserId).stream()
                    .filter(album -> !albumsWithRemainingTracks.contains(album.getId()))
                    .map(MusicAlbum::getCoverFileId)
                    .filter(Objects::nonNull)
                    .toList());
        }
        if (!artistIds.isEmpty()) {
            Set<UUID> artistsWithRemainingTracks = new HashSet<>(
                    trackRepository.findArtistIdsWithRemainingTracks(ownerUserId, artistIds, trackIds));
            writer.addFileNodeIds(artistRepository.findAllByIdInAndOwnerUserId(artistIds, ownerUserId).stream()
                    .filter(artist -> !artistsWithRemainingTracks.contains(artist.getId()))
                    .map(MusicArtist::getAvatarFileId)
                    .filter(Objects::nonNull)
                    .toList());
        }
    }

    /**
     * 幂等清理音乐业务记录。
     *
     * @param context 删除上下文
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void finalizePurge(PurgeContext context) {
        List<UUID> fileNodeIds = List.copyOf(context.fileNodeIds());
        Map<UUID, List<MusicTrack>> tracksByOwner = trackRepository.findByFileNodeIdIn(fileNodeIds).stream()
                .collect(Collectors.groupingBy(
                        MusicTrack::getOwnerUserId,
                        LinkedHashMap::new,
                        Collectors.toList()
                ));
        tracksByOwner.forEach(this::deleteOwnedRows);
        clearDanglingFileReferences(fileNodeIds);
    }

    /**
     * 处理文件移入回收站事件。
     *
     * @param event 文件节点软删除事件
     */
    @EventListener
    @Transactional(rollbackFor = Exception.class)
    public void handleFileNodesSoftDeleted(FileNodesSoftDeletedEvent event) {
        if (event.fileNodeIds() == null || event.fileNodeIds().isEmpty()) {
            return;
        }
        log.debug("文件移入回收站，保留音乐业务数据: ownerUserId={}, fileNodeCount={}",
                event.ownerUserId(), event.fileNodeIds().size());
    }

    /**
     * 使引用指定文件节点的音乐库缓存失效。
     *
     * @param fileNodeIds 文件节点 ID
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void invalidateFileVisibility(Collection<UUID> fileNodeIds) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return;
        }
        trackRepository.findByFileNodeIdIn(fileNodeIds).stream()
                .map(MusicTrack::getOwnerUserId)
                .filter(Objects::nonNull)
                .collect(Collectors.toCollection(LinkedHashSet::new))
                .forEach(ownerUserId -> syncEventService.invalidate(
                        ownerUserId,
                        SyncScope.MUSIC,
                        "MUSIC_LIBRARY",
                        Map.of("reason", "FILE_VISIBILITY_CHANGED")
                ));
    }

    private void deleteOwnedRows(UUID ownerUserId, List<MusicTrack> tracks) {
        if (tracks.isEmpty()) {
            return;
        }
        List<UUID> trackIds = tracks.stream().map(MusicTrack::getId).toList();
        List<String> musicKeys = trackIds.stream().map(id -> "local:" + id).toList();
        // 曲目一旦被物理清除，所有成员名下的关联行都要跟着消失：按上传者过滤会留下
        // 指向不存在曲目的孤儿收藏/历史/歌单条目。仪表盘计数的短暂偏差由缓存 TTL 自愈。
        playbackCleanupService.deleteAllUsers(MediaPlaybackType.MUSIC, musicKeys);
        favoriteRepository.deleteByTrackIdIn(trackIds);
        playHistoryRepository.deleteByTrackIdIn(trackIds);
        playlistItemRepository.deleteByTrackIdIn(trackIds);

        Set<UUID> albumIds = new HashSet<>();
        Set<UUID> artistIds = new HashSet<>();
        Set<UUID> coverFileIds = new LinkedHashSet<>();
        for (MusicTrack track : tracks) {
            if (track.getAlbumId() != null) {
                albumIds.add(track.getAlbumId());
            }
            if (track.getArtistId() != null) {
                artistIds.add(track.getArtistId());
            }
            coverFileIds.add(track.getCoverFileId());
        }

        trackRepository.deleteAllInBatch(tracks);
        coverRetentionService.releaseUnreferenced(ownerUserId, coverFileIds);
        cleanupOrphanedParents(ownerUserId, albumIds, artistIds);
        // 曲目删除改变音乐仪表盘统计与最近列表，需失效缓存。
        readThroughCache.invalidate("omninest:dashboard:music:" + ownerUserId);
    }

    private void cleanupOrphanedParents(UUID ownerUserId, Set<UUID> albumIds, Set<UUID> artistIds) {
        Set<UUID> coverFileIds = new LinkedHashSet<>();
        if (!albumIds.isEmpty()) {
            List<MusicAlbum> albums = albumRepository.findAllByIdInAndOwnerUserId(albumIds, ownerUserId);
            Set<UUID> albumsWithTracks = new HashSet<>(
                    trackRepository.findAlbumIdsWithTracks(ownerUserId, albumIds));
            List<MusicAlbum> orphanAlbums = albums.stream()
                    .filter(album -> !albumsWithTracks.contains(album.getId()))
                    .toList();
            Set<UUID> orphanAlbumIds = new HashSet<>();
            if (!orphanAlbums.isEmpty()) {
                orphanAlbums.forEach(album -> {
                    coverFileIds.add(album.getCoverFileId());
                    orphanAlbumIds.add(album.getId());
                });
                albumRepository.deleteByOwnerUserIdAndIdIn(ownerUserId,
                        orphanAlbums.stream().map(MusicAlbum::getId).toList());
                log.info("已清理孤立专辑: count={}", orphanAlbums.size());
            }
            refreshSurvivingAlbumStats(ownerUserId, albums, orphanAlbumIds);
        }

        if (!artistIds.isEmpty()) {
            List<MusicArtist> artists = artistRepository.findAllByIdInAndOwnerUserId(artistIds, ownerUserId);
            Set<UUID> artistsWithTracks = new HashSet<>(
                    trackRepository.findArtistIdsWithTracks(ownerUserId, artistIds));
            List<MusicArtist> orphanArtists = artists.stream()
                    .filter(artist -> !artistsWithTracks.contains(artist.getId()))
                    .toList();
            Set<UUID> orphanArtistIds = new HashSet<>();
            if (!orphanArtists.isEmpty()) {
                orphanArtists.forEach(artist -> {
                    coverFileIds.add(artist.getAvatarFileId());
                    orphanArtistIds.add(artist.getId());
                });
                artistRepository.deleteByOwnerUserIdAndIdIn(ownerUserId,
                        orphanArtists.stream().map(MusicArtist::getId).toList());
                log.info("已清理孤立艺术家: count={}", orphanArtists.size());
            }
            refreshSurvivingArtistStats(ownerUserId, artists, orphanArtistIds);
        }

        coverRetentionService.releaseUnreferenced(ownerUserId, coverFileIds);
    }

    /**
     * 存活专辑的曲目数与总时长必须随永久删除收敛，否则专辑页会长期显示已删曲目。
     */
    private void refreshSurvivingAlbumStats(
            UUID ownerUserId,
            List<MusicAlbum> albums,
            Set<UUID> orphanAlbumIds
    ) {
        List<MusicAlbum> surviving = albums.stream()
                .filter(album -> !orphanAlbumIds.contains(album.getId()))
                .toList();
        if (surviving.isEmpty()) {
            return;
        }
        Map<UUID, MusicAlbumTrackStats> stats = trackRepository
                .findAlbumStatsByOwnerUserIdAndAlbumIdIn(
                        ownerUserId, surviving.stream().map(MusicAlbum::getId).toList())
                .stream()
                .collect(Collectors.toMap(MusicAlbumTrackStats::getAlbumId, item -> item));
        for (MusicAlbum album : surviving) {
            MusicAlbumTrackStats albumStats = stats.get(album.getId());
            album.setTrackCount(albumStats == null ? 0 : (int) albumStats.getTrackCount());
            album.setTotalDuration(albumStats == null ? 0 : boundedDuration(albumStats.getTotalDuration()));
        }
        albumRepository.saveAll(surviving);
    }

    /**
     * 存活艺术家的作品数同样在永久删除后重算。
     */
    private void refreshSurvivingArtistStats(
            UUID ownerUserId,
            List<MusicArtist> artists,
            Set<UUID> orphanArtistIds
    ) {
        List<MusicArtist> surviving = artists.stream()
                .filter(artist -> !orphanArtistIds.contains(artist.getId()))
                .toList();
        if (surviving.isEmpty()) {
            return;
        }
        Map<UUID, MusicArtistTrackStats> stats = trackRepository
                .findArtistStatsByOwnerUserIdAndArtistIdIn(
                        ownerUserId, surviving.stream().map(MusicArtist::getId).toList())
                .stream()
                .collect(Collectors.toMap(MusicArtistTrackStats::getArtistId, item -> item));
        for (MusicArtist artist : surviving) {
            MusicArtistTrackStats artistStats = stats.get(artist.getId());
            artist.setTrackCount(artistStats == null ? 0 : (int) artistStats.getTrackCount());
            artist.setAlbumCount(artistStats == null ? 0 : (int) artistStats.getAlbumCount());
        }
        artistRepository.saveAll(surviving);
    }

    private int boundedDuration(long seconds) {
        return (int) Math.min(Integer.MAX_VALUE, Math.max(0L, seconds));
    }

    private void clearDanglingFileReferences(List<UUID> deletedFileIds) {
        Set<UUID> fileIds = new HashSet<>(deletedFileIds);
        albumRepository.findByCoverFileIdIn(fileIds)
                .forEach(album -> album.setCoverFileId(null));
        artistRepository.findByAvatarFileIdIn(fileIds)
                .forEach(artist -> artist.setAvatarFileId(null));
        playlistRepository.findByCoverFileIdIn(fileIds)
                .forEach(playlist -> playlist.setCoverFileId(null));
        trackRepository.findByCoverFileIdIn(fileIds)
                .forEach(track -> track.setCoverFileId(null));
    }
}
