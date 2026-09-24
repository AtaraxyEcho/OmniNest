package com.omninest.modules.music.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.music.domain.PlaylistType;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.domain.MusicPlaylist;
import com.omninest.modules.music.domain.MusicPlaylistItem;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.dto.MusicDtos.CreatePlaylistRequest;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaylistDto;
import com.omninest.modules.music.dto.MusicDtos.MusicTrackDto;
import com.omninest.modules.music.dto.MusicDtos.PlaylistItemsRequest;
import com.omninest.modules.music.dto.MusicDtos.UpdatePlaylistRequest;
import com.omninest.modules.music.repository.MusicPlaylistItemRepository;
import com.omninest.modules.music.repository.MusicPlaylistRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 音乐播放列表维护服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicPlaylistService {
    private final MusicPlaylistRepository playlistRepository;
    private final MusicPlaylistItemRepository playlistItemRepository;
    private final MusicTrackRepository trackRepository;
    private final MusicLibraryService musicLibraryService;
    private final MusicCoverService musicCoverService;
    private final MusicCoverRetentionService coverRetentionService;
    private final MediaSyncEventService syncEventService;

    @Transactional(readOnly = true)
    public List<MusicPlaylistDto> playlists(UUID ownerUserId) {
        List<MusicPlaylist> playlists = playlistRepository.findByOwnerUserIdOrderByUpdatedAtDesc(ownerUserId);
        if (playlists.isEmpty()) {
            return List.of();
        }
        Map<UUID, Long> countMap = playlistItemRepository
                .countByOwnerUserIdAndPlaylistIdIn(
                        ownerUserId,
                        playlists.stream().map(MusicPlaylist::getId).toList()
                )
                .stream()
                .collect(Collectors.toMap(
                        row -> (UUID) row[0],
                        row -> (Long) row[1]
                ));
        Map<UUID, String> coverMap = firstTrackCovers(ownerUserId, playlists);
        return playlists.stream()
                .map(playlist -> toDto(
                        playlist,
                        countMap.getOrDefault(playlist.getId(), 0L),
                        coverMap.get(playlist.getId())
                ))
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public MusicPlaylistDto create(UUID ownerUserId, CreatePlaylistRequest request) {
        log.info("创建播放列表: name={}, userId={}", request.name(), ownerUserId);
        MusicPlaylist playlist = new MusicPlaylist();
        playlist.setOwnerUserId(ownerUserId);
        playlist.setName(request.name().trim());
        playlist.setDescription(request.description());
        musicCoverService.validateOwnedCover(ownerUserId, request.coverFileId());
        playlist.setCoverFileId(request.coverFileId());
        MusicPlaylist saved = playlistRepository.save(playlist);
        recordPlaylistEvent(ownerUserId, saved, SyncAction.CREATED);
        return toDto(saved, 0, null);
    }

    @Transactional(rollbackFor = Exception.class)
    public MusicPlaylistDto update(UUID ownerUserId, UUID playlistId, UpdatePlaylistRequest request) {
        MusicPlaylist playlist = requireCustomPlaylist(ownerUserId, playlistId);
        playlist.setName(request.name().trim());
        playlist.setDescription(request.description());
        UUID previousCoverFileId = playlist.getCoverFileId();
        if (request.coverFileId() != null) {
            musicCoverService.validateOwnedCover(ownerUserId, request.coverFileId());
            playlist.setCoverFileId(request.coverFileId());
        }
        MusicPlaylist saved = playlistRepository.save(playlist);
        coverRetentionService.releaseUnreferenced(ownerUserId, previousCoverFileId);
        recordPlaylistEvent(ownerUserId, saved, SyncAction.UPDATED);
        return toDto(
                saved,
                playlistItemRepository.countByOwnerUserIdAndPlaylistId(ownerUserId, playlistId),
                firstTrackCover(ownerUserId, playlistId)
        );
    }

    @Transactional(rollbackFor = Exception.class)
    public void delete(UUID ownerUserId, UUID playlistId) {
        log.info("删除播放列表: playlistId={}, userId={}", playlistId, ownerUserId);
        MusicPlaylist playlist = requireCustomPlaylist(ownerUserId, playlistId);
        UUID coverFileId = playlist.getCoverFileId();
        playlistItemRepository.deleteByOwnerUserIdAndPlaylistId(ownerUserId, playlistId);
        playlistRepository.delete(playlist);
        coverRetentionService.releaseUnreferenced(ownerUserId, coverFileId);
        recordPlaylistEvent(ownerUserId, playlist, SyncAction.DELETED);
    }

    @Transactional(readOnly = true)
    public List<MusicTrackDto> playlistTracks(UUID ownerUserId, UUID playlistId) {
        requirePlaylist(ownerUserId, playlistId);
        List<UUID> trackIds = playlistItemRepository
                .findByOwnerUserIdAndPlaylistIdOrderBySortOrderAscCreatedAtAsc(ownerUserId, playlistId)
                .stream()
                .map(MusicPlaylistItem::getTrackId)
                .toList();
        if (trackIds.isEmpty()) {
            return List.of();
        }
        Map<UUID, MusicTrack> tracksById =
                trackRepository.findByOwnerUserIdAndIdIn(ownerUserId, trackIds).stream()
                        .collect(Collectors.toMap(
                                MusicTrack::getId,
                                Function.identity()
                        ));
        return trackIds.stream()
                .map(tracksById::get)
                .filter(Objects::nonNull)
                .map(track -> musicLibraryService.toTrackDto(track, false))
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public MusicPlaylistDto addItems(UUID ownerUserId, UUID playlistId, PlaylistItemsRequest request) {
        log.info("添加曲目到播放列表: playlistId={}, count={}", playlistId, request.trackIds().size());
        requireCustomPlaylist(ownerUserId, playlistId);
        List<UUID> trackIds = request.trackIds();
        Set<UUID> existingTrackIds = trackRepository.findByOwnerUserIdAndIdIn(ownerUserId, trackIds)
                .stream()
                .map(MusicTrack::getId)
                .collect(Collectors.toSet());
        List<UUID> missing = trackIds.stream().filter(id -> !existingTrackIds.contains(id)).toList();
        if (!missing.isEmpty()) {
            throw new BusinessException(
                    ErrorCode.MEDIA_NOT_FOUND,
                    "曲目不存在: " + missing.get(0)
            );
        }
        int startOrder = (int) playlistItemRepository.countByOwnerUserIdAndPlaylistId(ownerUserId, playlistId);
        List<MusicPlaylistItem> items = new ArrayList<>();
        int offset = 0;
        for (UUID trackId : trackIds) {
            MusicPlaylistItem item = new MusicPlaylistItem();
            item.setOwnerUserId(ownerUserId);
            item.setPlaylistId(playlistId);
            item.setTrackId(trackId);
            item.setSortOrder(startOrder + offset++);
            items.add(item);
        }
        playlistItemRepository.saveAll(items);
        MusicPlaylist playlist = requirePlaylist(ownerUserId, playlistId);
        recordPlaylistEvent(ownerUserId, playlist, SyncAction.UPDATED);
        return toDto(
                playlist,
                playlistItemRepository.countByOwnerUserIdAndPlaylistId(ownerUserId, playlistId),
                firstTrackCover(ownerUserId, playlistId)
        );
    }

    @Transactional(rollbackFor = Exception.class)
    public MusicPlaylistDto removeItems(UUID ownerUserId, UUID playlistId, PlaylistItemsRequest request) {
        log.info("移除播放列表曲目: playlistId={}, count={}", playlistId, request.trackIds().size());
        MusicPlaylist playlist = requireCustomPlaylist(ownerUserId, playlistId);
        playlistItemRepository.deleteByOwnerUserIdAndPlaylistIdAndTrackIdIn(
                ownerUserId,
                playlistId,
                request.trackIds()
        );
        playlistItemRepository.flush();
        recordPlaylistEvent(ownerUserId, playlist, SyncAction.UPDATED);
        return toDto(
                playlist,
                playlistItemRepository.countByOwnerUserIdAndPlaylistId(ownerUserId, playlistId),
                firstTrackCover(ownerUserId, playlistId)
        );
    }

    private MusicPlaylist requirePlaylist(UUID ownerUserId, UUID playlistId) {
        return playlistRepository.findByIdAndOwnerUserId(playlistId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "播放列表不存在"));
    }

    private MusicPlaylist requireCustomPlaylist(UUID ownerUserId, UUID playlistId) {
        MusicPlaylist playlist = requirePlaylist(ownerUserId, playlistId);
        if (!PlaylistType.CUSTOM.getValue().equals(playlist.getPlaylistType())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "仅支持修改用户自建歌单");
        }
        return playlist;
    }

    private Map<UUID, String> firstTrackCovers(UUID ownerUserId, List<MusicPlaylist> playlists) {
        List<UUID> playlistIds = playlists.stream().map(MusicPlaylist::getId).toList();
        Map<UUID, UUID> firstTrackIds = new LinkedHashMap<>();
        for (MusicPlaylistItem item : playlistItemRepository.findOrderedByOwnerAndPlaylistIds(
                ownerUserId,
                playlistIds
        )) {
            firstTrackIds.putIfAbsent(item.getPlaylistId(), item.getTrackId());
        }
        if (firstTrackIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, MusicTrack> tracks = trackRepository
                .findByOwnerUserIdAndIdIn(ownerUserId, new ArrayList<>(firstTrackIds.values()))
                .stream()
                .collect(Collectors.toMap(MusicTrack::getId, Function.identity()));
        Map<UUID, String> covers = new LinkedHashMap<>();
        firstTrackIds.forEach((playlistId, trackId) -> {
            MusicTrack track = tracks.get(trackId);
            if (track != null) {
                covers.put(playlistId, musicLibraryService.toTrackDto(track, false).coverUrl());
            }
        });
        return covers;
    }

    private String firstTrackCover(UUID ownerUserId, UUID playlistId) {
        return playlistItemRepository
                .findByOwnerUserIdAndPlaylistIdOrderBySortOrderAscCreatedAtAsc(ownerUserId, playlistId)
                .stream()
                .findFirst()
                .flatMap(item -> trackRepository.findByIdAndOwnerUserId(item.getTrackId(), ownerUserId))
                .map(track -> musicLibraryService.toTrackDto(track, false).coverUrl())
                .orElse(null);
    }

    private MusicPlaylistDto toDto(MusicPlaylist playlist, long itemCount, String fallbackCoverUrl) {
        String coverUrl = fallbackCoverUrl;
        if (playlist.getCoverFileId() != null) {
            String customCoverUrl = musicLibraryService.resolveCoverApiPath(playlist.getCoverFileId());
            if (customCoverUrl != null && !customCoverUrl.isBlank()) {
                coverUrl = customCoverUrl;
            }
        }
        return new MusicPlaylistDto(
                playlist.getId(),
                playlist.getName(),
                playlist.getDescription(),
                playlist.getPlaylistType(),
                playlist.getCoverFileId(),
                coverUrl,
                itemCount,
                playlist.getUpdatedAt()
        );
    }

    private void recordPlaylistEvent(UUID ownerUserId, MusicPlaylist playlist, SyncAction action) {
        syncEventService.record(
                ownerUserId,
                SyncScope.MUSIC,
                "MUSIC_PLAYLIST",
                playlist.getId() == null ? null : playlist.getId().toString(),
                action,
                playlist.getVersion(),
                Map.of()
        );
    }
}
