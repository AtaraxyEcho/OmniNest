package com.omninest.modules.video.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.CollectionType;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.video.domain.MediaSeriesFavorite;
import com.omninest.modules.video.domain.MediaVideoCollection;
import com.omninest.modules.video.domain.MediaVideoCollectionItem;
import com.omninest.modules.video.domain.MediaVideoFavorite;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.domain.MediaWatchHistory;
import com.omninest.modules.video.dto.MovieDtos.MovieCollectionDto;
import com.omninest.modules.video.dto.MovieDtos.MovieCollectionItemRequest;
import com.omninest.modules.video.dto.MovieDtos.MovieCollectionRequest;
import com.omninest.modules.video.dto.MovieDtos.MovieFavoriteStateDto;
import com.omninest.modules.video.dto.MovieDtos.MovieVideoItemDto;
import com.omninest.modules.video.dto.MovieDtos.MovieWatchHistoryDto;
import com.omninest.modules.video.repository.MediaSeriesFavoriteRepository;
import com.omninest.modules.video.repository.MediaVideoCollectionItemRepository;
import com.omninest.modules.video.repository.MediaVideoCollectionRepository;
import com.omninest.modules.video.repository.MediaVideoFavoriteRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.MediaWatchHistoryRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 影视收藏、历史与合集维护服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MovieEngagementService {
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaVideoFavoriteRepository favoriteRepository;
    private final MediaSeriesFavoriteRepository seriesFavoriteRepository;
    private final MediaWatchHistoryRepository historyRepository;
    private final MediaVideoCollectionRepository collectionRepository;
    private final MediaVideoCollectionItemRepository collectionItemRepository;
    private final VideoItemDtoConverter videoItemDtoConverter;
    private final MediaSyncEventService syncEventService;
    private final MediaLibraryAccessService mediaLibraryAccessService;
    private final MediaContentAccessService mediaContentAccessService;
    private final ReadThroughCache readThroughCache;

    @Transactional(readOnly = true)
    public List<MovieVideoItemDto> favorites(UUID ownerUserId) {
        List<MediaVideoFavorite> favorites = favoriteRepository.findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId);
        if (favorites.isEmpty()) {
            return List.of();
        }
        List<UUID> videoItemIds = favorites.stream().map(MediaVideoFavorite::getVideoItemId).toList();
        Map<UUID, MediaVideoItem> itemIndex = videoItemRepository.findReadableByIds(
                        ownerUserId,
                        mediaLibraryAccessService.findReadableLibraryIds(ownerUserId),
                        videoItemIds
                )
                .stream()
                .collect(Collectors.toMap(
                        MediaVideoItem::getId,
                        item -> item,
                        (left, right) -> left,
                        LinkedHashMap::new
                ));
        List<MediaVideoItem> items = favorites.stream()
                .map(fav -> itemIndex.get(fav.getVideoItemId()))
                .filter(item -> item != null)
                .toList();
        return videoItemDtoConverter.toVideoDtos(ownerUserId, items);
    }

    @Transactional(readOnly = true)
    public MovieFavoriteStateDto favoriteStatus(UUID ownerUserId, UUID videoItemId) {
        findVideo(ownerUserId, videoItemId);
        boolean isFavorite = favoriteRepository.findByOwnerUserIdAndVideoItemId(ownerUserId, videoItemId).isPresent();
        return new MovieFavoriteStateDto(videoItemId, isFavorite);
    }

    @Transactional(rollbackFor = Exception.class)
    public MovieFavoriteStateDto favorite(UUID ownerUserId, UUID videoItemId, boolean favorite) {
        findVideo(ownerUserId, videoItemId);
        var existing = favoriteRepository.findByOwnerUserIdAndVideoItemId(ownerUserId, videoItemId);
        if (favorite && existing.isEmpty()) {
            MediaVideoFavorite created = new MediaVideoFavorite();
            created.setOwnerUserId(ownerUserId);
            created.setVideoItemId(videoItemId);
            favoriteRepository.save(created);
        }
        if (!favorite) {
            existing.ifPresent(favoriteRepository::delete);
        }
        invalidateDashboardCache(ownerUserId);
        recordEvent(ownerUserId, "VIDEO_ITEM", videoItemId, SyncAction.UPDATED, Map.of("favorite", favorite));
        return new MovieFavoriteStateDto(videoItemId, favorite);
    }

    @Transactional(readOnly = true)
    public List<MovieWatchHistoryDto> history(UUID ownerUserId) {
        List<MediaWatchHistory> histories = historyRepository.findByOwnerUserIdOrderByPlayedAtDesc(ownerUserId);
        if (histories.isEmpty()) {
            return List.of();
        }
        List<UUID> videoItemIds = histories.stream().map(MediaWatchHistory::getVideoItemId).distinct().toList();
        List<MediaVideoItem> items = videoItemRepository.findReadableByIds(
                ownerUserId,
                mediaLibraryAccessService.findReadableLibraryIds(ownerUserId),
                videoItemIds
        );
        Map<UUID, MovieVideoItemDto> itemIndex = videoItemDtoConverter.toVideoDtos(ownerUserId, items).stream()
                .collect(Collectors.toMap(
                        MovieVideoItemDto::id,
                        item -> item,
                        (left, right) -> left,
                        LinkedHashMap::new
                ));

        return histories.stream()
                .flatMap(h -> Optional.ofNullable(itemIndex.get(h.getVideoItemId()))
                        .map(item -> {
                            return new MovieWatchHistoryDto(
                                    h.getId(),
                                    item.id(),
                                    item.title(),
                                    item.posterFileId(),
                                    item.posterUrl(),
                                    h.getPositionSeconds(),
                                    h.getDurationSeconds(),
                                    h.isCompleted(),
                                    h.getPlayedAt()
                            );
                        })
                        .stream())
                .toList();
    }

    @Transactional(readOnly = true)
    public List<MovieCollectionDto> collections(UUID ownerUserId) {
        List<MediaVideoCollection> collections = collectionRepository.findByOwnerUserIdOrderByUpdatedAtDesc(ownerUserId);
        if (collections.isEmpty()) {
            return List.of();
        }
        Map<UUID, Long> countMap = collectionItemRepository
                .countByOwnerUserIdAndCollectionIdIn(
                        ownerUserId,
                        collections.stream().map(MediaVideoCollection::getId).toList()
                )
                .stream()
                .collect(Collectors.toMap(
                        row -> (UUID) row[0],
                        row -> (Long) row[1]
                ));
        return collections.stream()
                .map(c -> toCollectionDto(c, countMap.getOrDefault(c.getId(), 0L)))
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public MovieCollectionDto createCollection(UUID ownerUserId, MovieCollectionRequest request) {
        if (request.name() == null || request.name().isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "合集名称不能为空");
        }
        MediaVideoCollection collection = new MediaVideoCollection();
        collection.setOwnerUserId(ownerUserId);
        collection.setName(request.name().trim());
        collection.setDescription(request.description());
        collection.setCoverFileId(request.coverFileId());
        collection.setCollectionType(CollectionType.MANUAL.getValue());
        MediaVideoCollection saved = collectionRepository.save(collection);
        invalidateDashboardCache(ownerUserId);
        recordEvent(ownerUserId, "VIDEO_COLLECTION", saved.getId(), SyncAction.CREATED, Map.of());
        return toCollectionDto(saved, 0);
    }

    @Transactional(rollbackFor = Exception.class)
    public MovieCollectionDto addCollectionItem(UUID ownerUserId, UUID collectionId, MovieCollectionItemRequest request) {
        MediaVideoCollection collection = collectionRepository.findByIdAndOwnerUserId(collectionId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "合集不存在"));
        findVideo(ownerUserId, request.videoItemId());
        collectionItemRepository.findByOwnerUserIdAndCollectionIdAndVideoItemId(ownerUserId, collectionId, request.videoItemId())
                .orElseGet(() -> {
                    MediaVideoCollectionItem item = new MediaVideoCollectionItem();
                    item.setOwnerUserId(ownerUserId);
                    item.setCollectionId(collectionId);
                    item.setVideoItemId(request.videoItemId());
                    item.setSortOrder(request.sortOrder());
                    return collectionItemRepository.save(item);
                });
        collectionRepository.save(collection);
        long itemCount = collectionItemRepository.countByOwnerUserIdAndCollectionId(ownerUserId, collectionId);
        invalidateDashboardCache(ownerUserId);
        recordEvent(ownerUserId, "VIDEO_COLLECTION", collectionId, SyncAction.UPDATED, Map.of());
        return toCollectionDto(collection, itemCount);
    }

    @Transactional(readOnly = true)
    public List<MovieVideoItemDto> collectionItems(UUID ownerUserId, UUID collectionId) {
        collectionRepository.findByIdAndOwnerUserId(collectionId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "合集不存在"));
        List<MediaVideoCollectionItem> collectionItems = collectionItemRepository
                .findByOwnerUserIdAndCollectionIdOrderBySortOrderAsc(ownerUserId, collectionId);
        if (collectionItems.isEmpty()) {
            return List.of();
        }
        List<UUID> videoItemIds = collectionItems.stream().map(MediaVideoCollectionItem::getVideoItemId).toList();
        Map<UUID, MediaVideoItem> itemIndex = videoItemRepository.findReadableByIds(
                        ownerUserId,
                        mediaLibraryAccessService.findReadableLibraryIds(ownerUserId),
                        videoItemIds
                )
                .stream()
                .collect(Collectors.toMap(
                        MediaVideoItem::getId,
                        item -> item,
                        (left, right) -> left,
                        LinkedHashMap::new
                ));
        List<MediaVideoItem> items = collectionItems.stream()
                .map(ci -> itemIndex.get(ci.getVideoItemId()))
                .filter(item -> item != null)
                .toList();
        return videoItemDtoConverter.toVideoDtos(ownerUserId, items);
    }

    private MovieCollectionDto toCollectionDto(MediaVideoCollection collection, long itemCount) {
        return new MovieCollectionDto(
                collection.getId(),
                collection.getName(),
                collection.getDescription(),
                collection.getCoverFileId(),
                collection.getCollectionType(),
                itemCount,
                collection.getUpdatedAt()
        );
    }

    @Transactional(rollbackFor = Exception.class)
    public boolean toggleSeriesFavorite(UUID ownerUserId, UUID seriesId) {
        mediaContentAccessService.requireReadableSeries(ownerUserId, seriesId);
        var existing = seriesFavoriteRepository.findByOwnerUserIdAndSeriesId(ownerUserId, seriesId);
        boolean newFavorite;
        if (existing.isPresent()) {
            seriesFavoriteRepository.delete(existing.get());
            newFavorite = false;
        } else {
            MediaSeriesFavorite fav = new MediaSeriesFavorite();
            fav.setOwnerUserId(ownerUserId);
            fav.setSeriesId(seriesId);
            seriesFavoriteRepository.save(fav);
            newFavorite = true;
        }
        recordEvent(ownerUserId, "VIDEO_SERIES", seriesId, SyncAction.UPDATED, Map.of("favorite", newFavorite));
        invalidateDashboardCache(ownerUserId);
        return newFavorite;
    }

    @Transactional(readOnly = true)
    public boolean seriesFavoriteStatus(UUID ownerUserId, UUID seriesId) {
        mediaContentAccessService.requireReadableSeries(ownerUserId, seriesId);
        return seriesFavoriteRepository.existsByOwnerUserIdAndSeriesId(ownerUserId, seriesId);
    }

    @Transactional(rollbackFor = Exception.class)
    public void deleteCollection(UUID ownerUserId, UUID collectionId) {
        MediaVideoCollection collection = collectionRepository.findByIdAndOwnerUserId(collectionId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "合集不存在"));
        collectionItemRepository.deleteByOwnerUserIdAndCollectionId(ownerUserId, collectionId);
        collectionRepository.delete(collection);
        invalidateDashboardCache(ownerUserId);
        recordEvent(ownerUserId, "VIDEO_COLLECTION", collectionId, SyncAction.DELETED, Map.of());
    }

    @Transactional(rollbackFor = Exception.class)
    public void removeCollectionItem(UUID ownerUserId, UUID collectionId, UUID videoItemId) {
        collectionRepository.findByIdAndOwnerUserId(collectionId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "合集不存在"));
        collectionItemRepository.deleteByOwnerUserIdAndCollectionIdAndVideoItemId(ownerUserId, collectionId, videoItemId);
        invalidateDashboardCache(ownerUserId);
        recordEvent(ownerUserId, "VIDEO_COLLECTION", collectionId, SyncAction.UPDATED, Map.of());
    }

    @Transactional(rollbackFor = Exception.class)
    public void deleteHistoryItem(UUID ownerUserId, UUID historyId) {
        historyRepository.deleteByOwnerUserIdAndId(ownerUserId, historyId);
        recordEvent(ownerUserId, "VIDEO_HISTORY", historyId, SyncAction.DELETED, Map.of());
    }

    @Transactional(rollbackFor = Exception.class)
    public void clearHistory(UUID ownerUserId) {
        historyRepository.deleteByOwnerUserId(ownerUserId);
        syncEventService.invalidate(ownerUserId, SyncScope.VIDEO, "VIDEO_HISTORY", Map.of());
    }

    /**
     * 失效指定用户的视频仪表盘缓存。
     *
     * <p>收藏与合集变更都会改变 dashboard 的收藏/合集计数统计。</p>
     *
     * @param ownerUserId 所有者用户 ID
     */
    private void invalidateDashboardCache(UUID ownerUserId) {
        readThroughCache.invalidate("omninest:dashboard:video:" + ownerUserId);
    }

    private MediaVideoItem findVideo(UUID ownerUserId, UUID videoItemId) {
        return mediaContentAccessService.requireReadableVideo(ownerUserId, videoItemId);
    }

    private void recordEvent(
            UUID ownerUserId,
            String resourceType,
            UUID resourceId,
            SyncAction action,
            Map<String, Object> hints
    ) {
        syncEventService.record(
                ownerUserId,
                SyncScope.VIDEO,
                resourceType,
                resourceId == null ? null : resourceId.toString(),
                action,
                null,
                hints
        );
    }

}
