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
import com.omninest.modules.music.repository.MusicArtistRepository;
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
import java.util.Optional;
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
        albumIds.stream()
                .filter(albumId -> trackRepository.countByOwnerUserIdAndAlbumIdAndIdNotIn(
                        ownerUserId, albumId, trackIds) == 0)
                .map(albumRepository::findById)
                .flatMap(Optional::stream)
                .map(MusicAlbum::getCoverFileId)
                .filter(Objects::nonNull)
                .forEach(fileId -> writer.addFileNodeIds(List.of(fileId)));
        artistIds.stream()
                .filter(artistId -> trackRepository.countByOwnerUserIdAndArtistIdAndIdNotIn(
                        ownerUserId, artistId, trackIds) == 0)
                .map(artistRepository::findById)
                .flatMap(Optional::stream)
                .map(MusicArtist::getAvatarFileId)
                .filter(Objects::nonNull)
                .forEach(fileId -> writer.addFileNodeIds(List.of(fileId)));
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
        playbackCleanupService.deleteOwned(ownerUserId, MediaPlaybackType.MUSIC, musicKeys);
        favoriteRepository.deleteByOwnerUserIdAndTrackIdIn(ownerUserId, trackIds);
        playHistoryRepository.deleteByOwnerUserIdAndTrackIdIn(ownerUserId, trackIds);
        playlistItemRepository.deleteByOwnerUserIdAndTrackIdIn(ownerUserId, trackIds);

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
            Set<UUID> albumsWithTracks = new HashSet<>(
                    trackRepository.findAlbumIdsWithTracks(ownerUserId, albumIds));
            List<MusicAlbum> orphanAlbums = albumRepository.findAllByIdInAndOwnerUserId(albumIds, ownerUserId)
                    .stream()
                    .filter(album -> !albumsWithTracks.contains(album.getId()))
                    .toList();
            if (!orphanAlbums.isEmpty()) {
                orphanAlbums.forEach(album -> coverFileIds.add(album.getCoverFileId()));
                albumRepository.deleteByOwnerUserIdAndIdIn(ownerUserId,
                        orphanAlbums.stream().map(MusicAlbum::getId).toList());
                log.info("已清理孤立专辑: count={}", orphanAlbums.size());
            }
        }

        if (!artistIds.isEmpty()) {
            Set<UUID> artistsWithTracks = new HashSet<>(
                    trackRepository.findArtistIdsWithTracks(ownerUserId, artistIds));
            List<MusicArtist> orphanArtists = artistRepository.findAllByIdInAndOwnerUserId(artistIds, ownerUserId)
                    .stream()
                    .filter(artist -> !artistsWithTracks.contains(artist.getId()))
                    .toList();
            if (!orphanArtists.isEmpty()) {
                orphanArtists.forEach(artist -> coverFileIds.add(artist.getAvatarFileId()));
                artistRepository.deleteByOwnerUserIdAndIdIn(ownerUserId,
                        orphanArtists.stream().map(MusicArtist::getId).toList());
                log.info("已清理孤立艺术家: count={}", orphanArtists.size());
            }
        }

        coverRetentionService.releaseUnreferenced(ownerUserId, coverFileIds);
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
