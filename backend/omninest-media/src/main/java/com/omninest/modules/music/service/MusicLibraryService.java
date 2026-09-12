package com.omninest.modules.music.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.service.FilePurgeOrigin;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicArtist;
import com.omninest.modules.music.domain.MusicFavorite;
import com.omninest.modules.music.domain.MusicPlayHistory;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.dto.MusicDtos.MusicAlbumDto;
import com.omninest.modules.music.dto.MusicDtos.MusicArtistDto;
import com.omninest.modules.music.dto.MusicDtos.MusicDashboardDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlayHistoryRequest;
import com.omninest.modules.music.dto.MusicDtos.MusicRecentItemDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlayHistoryDto;
import com.omninest.modules.music.dto.MusicDtos.RecordMusicPlayHistoryRequest;
import com.omninest.modules.music.dto.MusicDtos.MusicSearchResultDto;
import com.omninest.modules.music.dto.MusicDtos.MusicTrackDto;
import com.omninest.modules.music.dto.OnlineMusicDtos.OnlineTrackDto;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicArtistRepository;
import com.omninest.modules.music.repository.MusicFavoriteRepository;
import com.omninest.modules.music.repository.MusicPlayHistoryRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import com.omninest.modules.music.service.platform.MusicPlatform;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 提供本地音乐曲库查询、收藏、历史和资源转换能力。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicLibraryService {
    private static final Duration PLAY_HISTORY_RETENTION = Duration.ofDays(7);

    /** 曲库三端点允许的动态排序字段白名单。 */
    private static final Set<String> TRACK_SORT_FIELDS = Set.of("title", "artistName", "updatedAt");
    private static final Set<String> ALBUM_SORT_FIELDS = Set.of("updatedAt", "name");
    private static final Set<String> ARTIST_SORT_FIELDS = Set.of("name");

    private final MusicTrackRepository trackRepository;
    private final MusicAlbumRepository albumRepository;
    private final MusicArtistRepository artistRepository;
    private final MusicFavoriteRepository favoriteRepository;
    private final MusicPlayHistoryRepository playHistoryRepository;
    private final FileDeletionService fileDeletionService;
    private final FileQueryService fileQueryService;
    private final ReadThroughCache readThroughCache;
    private final MediaSyncEventService syncEventService;

    @Transactional(readOnly = true)
    public MusicDashboardDto dashboard(UUID ownerUserId) {
        String cacheKey = "omninest:dashboard:music:" + ownerUserId;
        return readThroughCache.getOrLoad(cacheKey, Duration.ofMinutes(3),
                () -> loadDashboard(ownerUserId),
                MusicDashboardDto.class);
    }

    /**
     * 从数据库加载音乐仪表盘数据。
     */
    private MusicDashboardDto loadDashboard(UUID ownerUserId) {
        return new MusicDashboardDto(
                trackRepository.countByOwnerUserId(ownerUserId),
                albumRepository.countActiveByOwnerUserId(ownerUserId),
                artistRepository.countActiveByOwnerUserId(ownerUserId),
                playHistoryRepository.countByOwnerUserId(ownerUserId),
                toTrackDtos(ownerUserId, trackRepository.findTop12ByOwnerUserIdOrderByUpdatedAtDesc(ownerUserId)),
                albumRepository.findTop12ActiveByOwnerUserId(ownerUserId).stream()
                        .map(this::toAlbumDto)
                        .toList(),
                artistRepository.findTop12ActiveByOwnerUserId(ownerUserId).stream()
                        .map(this::toArtistDto)
                        .toList()
        );
    }

    @Transactional(readOnly = true)
    public Page<MusicTrackDto> tracks(UUID ownerUserId, int page, int size, String sort) {
        Page<MusicTrack> result = trackRepository.findTracksVisibleToUser(
                ownerUserId,
                SpaceType.SHARED,
                PageRequest.of(page, size, resolveSort(sort, TRACK_SORT_FIELDS, Sort.by(Sort.Direction.ASC, "title"))));
        return new PageImpl<>(
                toTrackDtos(ownerUserId, result.getContent()),
                result.getPageable(),
                result.getTotalElements());
    }

    @Transactional(readOnly = true)
    public Page<MusicAlbumDto> albums(UUID ownerUserId, int page, int size, String sort) {
        return albumRepository
                .findActiveByOwnerUserId(
                        ownerUserId,
                        PageRequest.of(page, size, resolveSort(sort, ALBUM_SORT_FIELDS, Sort.by(Sort.Direction.DESC, "updatedAt"))))
                .map(this::toAlbumDto);
    }

    @Transactional(readOnly = true)
    public Page<MusicArtistDto> artists(UUID ownerUserId, int page, int size, String sort) {
        return artistRepository
                .findActiveByOwnerUserId(
                        ownerUserId,
                        PageRequest.of(page, size, resolveSort(sort, ARTIST_SORT_FIELDS, Sort.by(Sort.Direction.ASC, "name"))))
                .map(this::toArtistDto);
    }

    /**
     * 将逗号分隔的排序参数解析为受白名单约束的 Sort，非法字段回退默认排序。
     */
    private Sort resolveSort(String sort, Set<String> allowedFields, Sort fallback) {
        if (sort == null || sort.isBlank()) {
            return fallback;
        }
        String[] parts = sort.split(",");
        String field = parts[0].trim();
        if (!allowedFields.contains(field)) {
            return fallback;
        }
        Sort.Direction direction = parts.length > 1 && "desc".equalsIgnoreCase(parts[1].trim())
                ? Sort.Direction.DESC
                : Sort.Direction.ASC;
        return Sort.by(direction, field);
    }

    @Transactional(readOnly = true)
    public List<MusicTrackDto> favorites(UUID ownerUserId) {
        List<UUID> trackIds = favoriteRepository.findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId).stream()
                .map(MusicFavorite::getTrackId)
                .toList();
        if (trackIds.isEmpty()) {
            return List.of();
        }
        return toTrackDtos(ownerUserId, trackRepository.findByOwnerUserIdAndIdIn(ownerUserId, trackIds));
    }

    @Transactional(readOnly = true)
    public List<MusicTrackDto> recent(UUID ownerUserId) {
        List<UUID> trackIds = playHistoryRepository
                .findTop50ByOwnerUserIdAndPlayedAtGreaterThanEqualOrderByPlayedAtDesc(
                        ownerUserId,
                        Instant.now().minus(PLAY_HISTORY_RETENTION)
                )
                .stream()
                .map(MusicPlayHistory::getTrackId)
                .filter(trackId -> trackId != null)
                .distinct()
                .toList();
        if (trackIds.isEmpty()) {
            return List.of();
        }
        return toTrackDtos(ownerUserId, trackRepository.findByOwnerUserIdAndIdIn(ownerUserId, trackIds));
    }

    /**
     * 查询本地和在线音乐的统一最近播放列表。
     *
     * @param ownerUserId 当前用户 ID
     * @return 按最后播放时间倒序排列的去重列表
     */
    @Transactional(readOnly = true)
    public List<MusicRecentItemDto> recentItems(UUID ownerUserId) {
        LinkedHashMap<String, MusicPlayHistory> latestByKey = new LinkedHashMap<>();
        for (MusicPlayHistory history : playHistoryRepository
                .findTop50ByOwnerUserIdAndPlayedAtGreaterThanEqualOrderByPlayedAtDesc(
                        ownerUserId,
                        Instant.now().minus(PLAY_HISTORY_RETENTION)
                )) {
            latestByKey.putIfAbsent(history.getPlayableKey(), history);
        }
        if (latestByKey.isEmpty()) {
            return List.of();
        }
        List<UUID> localTrackIds = latestByKey.values().stream()
                .map(MusicPlayHistory::getTrackId)
                .filter(trackId -> trackId != null)
                .toList();
        Map<UUID, MusicTrack> localTracks = trackRepository
                .findByOwnerUserIdAndIdIn(ownerUserId, localTrackIds)
                .stream()
                .collect(Collectors.toMap(MusicTrack::getId, track -> track));
        Set<UUID> favoriteTrackIds = favoriteTrackIds(ownerUserId, localTrackIds);
        List<MusicRecentItemDto> results = new ArrayList<>();
        for (MusicPlayHistory history : latestByKey.values()) {
            if (history.getTrackId() != null) {
                MusicTrack track = localTracks.get(history.getTrackId());
                if (track != null) {
                    results.add(new MusicRecentItemDto(
                            history.getPlayableKey(),
                            toTrackDto(track, favoriteTrackIds.contains(track.getId())),
                            null,
                            history.getPlayedAt()
                    ));
                }
                continue;
            }
            results.add(new MusicRecentItemDto(
                    history.getPlayableKey(),
                    null,
                    toOnlineTrackDto(history),
                    history.getPlayedAt()
            ));
        }
        return List.copyOf(results);
    }

    @Transactional(readOnly = true)
    public MusicSearchResultDto search(UUID ownerUserId, String keyword) {
        String normalized = keyword == null ? "" : keyword.trim();
        if (normalized.isEmpty()) {
            return new MusicSearchResultDto(List.of(), List.of(), List.of());
        }
        return new MusicSearchResultDto(
                toTrackDtos(ownerUserId, trackRepository.searchByOwnerUserId(
                        ownerUserId,
                        normalized,
                        PageRequest.of(0, 20)
                )),
                albumRepository
                        .searchActiveByOwnerUserId(
                                ownerUserId,
                                normalized
                        )
                        .stream()
                        .map(this::toAlbumDto)
                        .toList(),
                artistRepository
                        .searchActiveByOwnerUserId(
                                ownerUserId,
                                normalized
                        )
                        .stream()
                        .map(this::toArtistDto)
                        .toList()
        );
    }

    @Transactional(rollbackFor = Exception.class)
    public MusicTrackDto favorite(UUID ownerUserId, UUID trackId) {
        log.info("收藏曲目: trackId={}, userId={}", trackId, ownerUserId);
        MusicTrack track = requireTrack(ownerUserId, trackId);
        boolean created = favoriteRepository.findByOwnerUserIdAndTrackId(ownerUserId, trackId).isEmpty();
        if (created) {
            MusicFavorite favorite = new MusicFavorite();
            favorite.setOwnerUserId(ownerUserId);
            favorite.setTrackId(trackId);
            favoriteRepository.save(favorite);
            recordTrackEvent(ownerUserId, track, SyncAction.UPDATED, Map.of("favorite", true));
        }
        return toTrackDto(track, true);
    }

    @Transactional(rollbackFor = Exception.class)
    public MusicTrackDto removeFavorite(UUID ownerUserId, UUID trackId) {
        log.info("取消收藏: trackId={}, userId={}", trackId, ownerUserId);
        MusicTrack track = requireTrack(ownerUserId, trackId);
        favoriteRepository.deleteByOwnerUserIdAndTrackId(ownerUserId, trackId);
        recordTrackEvent(ownerUserId, track, SyncAction.UPDATED, Map.of("favorite", false));
        return toTrackDto(track, false);
    }

    @Transactional(rollbackFor = Exception.class)
    public void recordPlayHistory(UUID ownerUserId, UUID trackId, MusicPlayHistoryRequest request) {
        log.debug("记录播放历史: trackId={}, userId={}", trackId, ownerUserId);
        MusicTrack track = requireTrack(ownerUserId, trackId);
        MusicPlayHistory history = new MusicPlayHistory();
        history.setOwnerUserId(ownerUserId);
        history.setTrackId(trackId);
        history.setPlayableKey("local:" + trackId);
        history.setTitle(track.getTitle());
        history.setArtistName(track.getArtistName());
        history.setAlbumTitle(track.getAlbumTitle());
        history.setDurationSeconds(track.getDurationSeconds());
        history.setPlayDuration(request == null ? null : request.playDuration());
        history.setPlayedAt(Instant.now());
        savePlayHistory(ownerUserId, history);
    }

    /**
     * 记录本地或在线音乐播放历史。
     *
     * @param ownerUserId 当前用户 ID
     * @param request 类型化播放历史请求
     */
    @Transactional(rollbackFor = Exception.class)
    public void recordPlayHistory(UUID ownerUserId, RecordMusicPlayHistoryRequest request) {
        String playableKey = request.playableKey().trim();
        if (playableKey.startsWith("local:")) {
            recordLocalHistory(ownerUserId, playableKey, request);
            return;
        }
        if (playableKey.startsWith("online:")) {
            recordOnlineHistory(ownerUserId, playableKey, request);
            return;
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "音乐播放键格式不正确");
    }

    /**
     * 分页查询用户播放历史，按播放时间倒序。
     *
     * @param ownerUserId 当前用户 ID
     * @param page 页码
     * @param size 每页数量
     * @return 播放历史分页
     */
    @Transactional(readOnly = true)
    public Page<MusicPlayHistoryDto> playHistory(UUID ownerUserId, int page, int size) {
        Instant cutoff = Instant.now().minus(PLAY_HISTORY_RETENTION);
        var result = playHistoryRepository.findByOwnerUserIdAndPlayedAtGreaterThanEqualOrderByPlayedAtDesc(
                ownerUserId,
                cutoff,
                PageRequest.of(page, size)
        );
        return result.map(history -> new MusicPlayHistoryDto(
                history.getPlayableKey(),
                history.getTitle(),
                history.getArtistName(),
                history.getAlbumTitle(),
                history.getCoverUrl(),
                history.getDurationSeconds(),
                history.getPlayDuration(),
                history.getPlatform(),
                history.getExternalSongId(),
                history.getPlayedAt()
        ));
    }

    @Transactional(readOnly = true)
    public MusicTrackDto getLastPlayed(UUID ownerUserId) {
        return playHistoryRepository
                .findFirstByOwnerUserIdAndTrackIdIsNotNullOrderByPlayedAtDesc(ownerUserId)
                .flatMap(history -> trackRepository.findById(history.getTrackId()))
                .map(track -> toTrackDto(
                        track,
                        favoriteRepository.existsByOwnerUserIdAndTrackId(ownerUserId, track.getId())
                ))
                .orElse(null);
    }

    private void recordLocalHistory(
            UUID ownerUserId,
            String playableKey,
            RecordMusicPlayHistoryRequest request
    ) {
        UUID trackId;
        try {
            trackId = UUID.fromString(playableKey.substring("local:".length()));
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "本地音乐播放键格式不正确");
        }
        MusicTrack track = requireTrack(ownerUserId, trackId);
        MusicPlayHistory history = new MusicPlayHistory();
        history.setOwnerUserId(ownerUserId);
        history.setTrackId(trackId);
        history.setPlayableKey("local:" + trackId);
        history.setTitle(track.getTitle());
        history.setArtistName(track.getArtistName());
        history.setAlbumTitle(track.getAlbumTitle());
        history.setDurationSeconds(track.getDurationSeconds());
        history.setPlayDuration(request.playDuration());
        history.setPlayedAt(Instant.now());
        savePlayHistory(ownerUserId, history);
    }

    private void recordOnlineHistory(
            UUID ownerUserId,
            String playableKey,
            RecordMusicPlayHistoryRequest request
    ) {
        String[] segments = playableKey.split(":", 3);
        if (segments.length != 3 || segments[2].isBlank()
                || request.title() == null || request.title().isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "在线音乐播放历史参数不正确");
        }
        MusicPlatform platform = MusicPlatform.fromApiValue(segments[1]);
        MusicPlayHistory history = new MusicPlayHistory();
        history.setOwnerUserId(ownerUserId);
        history.setPlayableKey("online:" + platform.apiValue() + ":" + segments[2]);
        history.setPlatform(platform.apiValue());
        history.setExternalSongId(segments[2]);
        history.setTitle(request.title().trim());
        history.setArtistName(trimToNull(request.artistName()));
        history.setAlbumTitle(trimToNull(request.albumTitle()));
        history.setCoverUrl(trimToNull(request.coverUrl()));
        history.setDurationSeconds(request.durationSeconds());
        history.setMediaMid(trimToNull(request.mediaMid()));
        history.setPlayDuration(request.playDuration());
        history.setPlayedAt(Instant.now());
        savePlayHistory(ownerUserId, history);
    }

    private void savePlayHistory(UUID ownerUserId, MusicPlayHistory history) {
        playHistoryRepository.save(history);
        // 播放历史改变音乐仪表盘的历史计数与最近播放列表，需失效缓存。
        readThroughCache.invalidate("omninest:dashboard:music:" + ownerUserId);
        syncEventService.record(
                ownerUserId,
                SyncScope.MUSIC,
                "MUSIC_PLAY_HISTORY",
                history.getPlayableKey(),
                SyncAction.UPDATED,
                history.getVersion(),
                Map.of()
        );
        int deleted = playHistoryRepository.deleteExpiredHistory(
                ownerUserId,
                history.getPlayedAt().minus(PLAY_HISTORY_RETENTION)
        );
        if (deleted > 0) {
            log.debug("已清理过期音乐播放历史: userId={}, count={}", ownerUserId, deleted);
        }
    }

    private OnlineTrackDto toOnlineTrackDto(MusicPlayHistory history) {
        Map<String, Object> extra = history.getMediaMid() == null
                ? Map.of()
                : Map.of("mediaMid", history.getMediaMid());
        return new OnlineTrackDto(
                history.getPlatform(),
                history.getExternalSongId(),
                history.getTitle(),
                fallback(history.getArtistName(), "Unknown Artist"),
                fallback(history.getAlbumTitle(), "Unknown Album"),
                history.getCoverUrl(),
                history.getDurationSeconds(),
                null,
                extra
        );
    }

    private String trimToNull(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.trim();
    }

    @Transactional(rollbackFor = Exception.class)
    public UUID deleteTrack(UUID ownerUserId, UUID trackId) {
        return deleteTrack(ownerUserId, trackId, false);
    }

    /**
     * 创建本地音乐曲目永久删除任务。
     *
     * @param ownerUserId 所有者用户 ID
     * @param trackId 曲目 ID
     * @param cascade 是否允许级联清理其他业务引用
     * @return 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID deleteTrack(UUID ownerUserId, UUID trackId, boolean cascade) {
        log.info("删除音乐曲目: trackId={}, userId={}", trackId, ownerUserId);
        MusicTrack track = requireTrack(ownerUserId, trackId);
        UUID taskId = fileDeletionService.deletePermanently(
                ownerUserId,
                track.getFileNodeId(),
                cascade,
                new FilePurgeOrigin("MUSIC", trackId),
                null
        );
        log.info("音乐曲目永久删除任务已创建: taskId={}, trackId={}, userId={}",
                taskId, trackId, ownerUserId);
        return taskId;
    }

    @Transactional(readOnly = true)
    public MusicTrack requireTrack(UUID ownerUserId, UUID trackId) {
        return trackRepository.findByIdAndOwnerUserId(trackId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "音乐资源不存在"));
    }

    public MusicTrackDto toTrackDto(MusicTrack track, boolean favorite) {
        return new MusicTrackDto(
                track.getId(),
                track.getFileNodeId(),
                track.getTitle(),
                fallback(track.getArtistName(), "Unknown Artist"),
                fallback(track.getAlbumTitle(), "Unknown Album"),
                track.getDurationSeconds(),
                track.getFormat(),
                track.getBitrate(),
                track.getSampleRate(),
                track.getFileSize(),
                track.getLyricsRaw(),
                firstText(
                        resolveCoverUrl(track.getOwnerUserId(), track.getCoverFileId()),
                        firstText(
                                metadataText(track.getProviderMetadata(), "coverDataUrl"),
                                metadataText(track.getProviderMetadata(), "coverUrl")
                        )
                ),
                favorite,
                track.getUpdatedAt()
        );
    }

    private List<MusicTrackDto> toTrackDtos(UUID ownerUserId, List<MusicTrack> tracks) {
        Set<UUID> favoriteTrackIds = favoriteTrackIds(ownerUserId, tracks.stream().map(MusicTrack::getId).toList());
        return tracks.stream()
                .map(track -> toTrackDto(track, favoriteTrackIds.contains(track.getId())))
                .toList();
    }

    private Set<UUID> favoriteTrackIds(UUID ownerUserId, Collection<UUID> trackIds) {
        if (trackIds.isEmpty()) {
            return Set.of();
        }
        return favoriteRepository.findByOwnerUserIdAndTrackIdIn(ownerUserId, trackIds).stream()
                .map(MusicFavorite::getTrackId)
                .collect(Collectors.toCollection(LinkedHashSet::new));
    }

    private MusicAlbumDto toAlbumDto(MusicAlbum album) {
        return new MusicAlbumDto(
                album.getId(),
                album.getTitle(),
                fallback(album.getArtistName(), "Various Artists"),
                firstText(
                        resolveCoverUrl(album.getOwnerUserId(), album.getCoverFileId()),
                        metadataText(album.getProviderMetadata(), "coverUrl")
                ),
                album.getReleaseDate(),
                album.getTotalDuration(),
                album.getTrackCount(),
                album.getUpdatedAt()
        );
    }

    private MusicArtistDto toArtistDto(MusicArtist artist) {
        return new MusicArtistDto(
                artist.getId(),
                artist.getName(),
                firstText(
                        resolveCoverUrl(artist.getOwnerUserId(), artist.getAvatarFileId()),
                        metadataText(artist.getProviderMetadata(), "avatarUrl")
                ),
                artist.getTrackCount(),
                artist.getAlbumCount(),
                artist.getUpdatedAt()
        );
    }

    /**
     * 为音乐封面文件创建可直接渲染的短期下载地址。
     *
     * @param ownerUserId 所属用户标识
     * @param fileId 封面文件标识
     * @return 短期下载地址，解析失败时返回空值
     */
    public String resolveCoverUrl(UUID ownerUserId, UUID fileId) {
        if (ownerUserId == null || fileId == null) {
            return null;
        }
        try {
            return fileQueryService.createDownloadUrl(ownerUserId, fileId).downloadUrl();
        } catch (RuntimeException ex) {
            log.debug("音乐封面 URL 解析失败: fileId={}, message={}", fileId, ex.getMessage());
            return null;
        }
    }

    private String fallback(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }

    private String firstText(String first, String second) {
        if (first != null && !first.isBlank()) {
            return first;
        }
        return second == null || second.isBlank() ? null : second;
    }

    private String metadataText(Map<String, Object> metadata, String key) {
        if (metadata == null || metadata.isEmpty()) {
            return null;
        }
        Object value = metadata.get(key);
        if (value != null) {
            return String.valueOf(value);
        }
        Object nested = metadata.get("musicbrainz");
        if (nested instanceof Map<?, ?> nestedMap) {
            Object nestedValue = nestedMap.get(key);
            return nestedValue == null ? null : String.valueOf(nestedValue);
        }
        return null;
    }

    private void recordTrackEvent(
            UUID ownerUserId,
            MusicTrack track,
            SyncAction action,
            Map<String, Object> hints
    ) {
        syncEventService.record(
                ownerUserId,
                SyncScope.MUSIC,
                "MUSIC_TRACK",
                track.getId().toString(),
                action,
                track.getVersion(),
                hints
        );
    }
}
