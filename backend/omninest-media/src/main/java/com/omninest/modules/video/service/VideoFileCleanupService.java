package com.omninest.modules.video.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.service.FileBusinessReference;
import com.omninest.modules.file.service.FilePurgeParticipant;
import com.omninest.modules.file.service.PurgeContext;
import com.omninest.modules.file.service.PurgeContributionWriter;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.service.MediaFileVisibilitySyncParticipant;
import com.omninest.modules.media.service.MediaPlaybackCleanupService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.video.domain.ContentAsset;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaTvEpisode;
import com.omninest.modules.video.domain.MediaTvSeason;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.ContentAssetRepository;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaNfoExportRepository;
import com.omninest.modules.video.repository.MediaSeriesFavoriteRepository;
import com.omninest.modules.video.repository.MediaSubtitleTrackRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoCollectionItemRepository;
import com.omninest.modules.video.repository.MediaVideoCollectionRepository;
import com.omninest.modules.video.repository.MediaVideoFavoriteRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.MediaWatchHistoryRepository;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashMap;
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
 * 文件删除触发的影视业务数据清理服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class VideoFileCleanupService implements
        FilePurgeParticipant,
        MediaFileVisibilitySyncParticipant {
    private static final String MODULE = "MOVIES";
    private static final String RESOURCE_TYPE = "VIDEO_ITEM";
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaPlaybackCleanupService playbackCleanupService;
    private final MediaWatchHistoryRepository watchHistoryRepository;
    private final MediaVideoFavoriteRepository videoFavoriteRepository;
    private final MediaVideoCollectionItemRepository collectionItemRepository;
    private final MediaSubtitleTrackRepository subtitleTrackRepository;
    private final MediaNfoExportRepository nfoExportRepository;
    private final ContentAssetRepository contentAssetRepository;
    private final MediaMovieRepository movieRepository;
    private final MediaTvEpisodeRepository tvEpisodeRepository;
    private final MediaTvSeasonRepository tvSeasonRepository;
    private final MediaTvSeriesRepository tvSeriesRepository;
    private final MediaSeriesFavoriteRepository seriesFavoriteRepository;
    private final MediaVideoCollectionRepository videoCollectionRepository;
    private final MediaSyncEventService syncEventService;
    private final ReadThroughCache readThroughCache;

    /**
     * 查询目标文件的视频条目引用。
     *
     * @param context 删除上下文
     * @return 视频条目引用
     */
    @Override
    @Transactional(readOnly = true)
    public List<FileBusinessReference> findBusinessReferences(PurgeContext context) {
        List<FileBusinessReference> references = new ArrayList<>();
        videoItemRepository.findByFileNodeIdIn(context.fileNodeIds()).stream()
                .map(video -> new FileBusinessReference(
                        MODULE,
                        RESOURCE_TYPE,
                        video.getId(),
                        video.getFileNodeId()
                ))
                .forEach(references::add);
        subtitleTrackRepository.findByFileNodeIdIn(context.fileNodeIds()).stream()
                .map(track -> new FileBusinessReference(
                        MODULE,
                        "SUBTITLE_TRACK",
                        track.getId(),
                        track.getFileNodeId()
                ))
                .forEach(references::add);
        return List.copyOf(references);
    }

    /**
     * 贡献视频条目及删除后将成为孤立资源的父级资产。
     *
     * @param context 删除上下文
     * @param writer 资源写入器
     */
    @Override
    @Transactional(readOnly = true)
    public void contribute(PurgeContext context, PurgeContributionWriter writer) {
        Map<UUID, List<MediaVideoItem>> videosByOwner = videoItemRepository
                .findByFileNodeIdIn(context.fileNodeIds())
                .stream()
                .collect(Collectors.groupingBy(
                        MediaVideoItem::getOwnerUserId,
                        LinkedHashMap::new,
                        Collectors.toList()
                ));
        videosByOwner.forEach((ownerUserId, videos) -> contributeOwnedVideos(
                new PurgeContext(
                        context.taskId(),
                        ownerUserId,
                        context.rootFileNodeId(),
                        context.fileNodeIds()
                ),
                videos,
                writer
        ));
    }

    private void contributeOwnedVideos(
            PurgeContext context,
            List<MediaVideoItem> videos,
            PurgeContributionWriter writer
    ) {
        List<UUID> videoIds = videos.stream().map(MediaVideoItem::getId).toList();
        addContentAssetFiles(writer, context.ownerUserId(), ResourceType.VIDEO_ITEM, videoIds);
        contributeMovieAssets(context, writer, videos, videoIds);
        contributeEpisodeAndSeriesAssets(context, writer, videos, videoIds);
    }

    /**
     * 幂等清理影视业务记录。
     *
     * @param context 删除上下文
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void finalizePurge(PurgeContext context) {
        List<UUID> fileNodeIds = List.copyOf(context.fileNodeIds());
        subtitleTrackRepository.deleteByFileNodeIdIn(fileNodeIds);
        Map<UUID, List<MediaVideoItem>> videosByOwner = videoItemRepository.findByFileNodeIdIn(fileNodeIds).stream()
                .collect(Collectors.groupingBy(
                        MediaVideoItem::getOwnerUserId,
                        LinkedHashMap::new,
                        Collectors.toList()
                ));
        videosByOwner.forEach(this::deleteOwnedRows);
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
        log.debug("文件移入回收站，保留影视业务数据: ownerUserId={}, fileNodeCount={}",
                event.ownerUserId(), event.fileNodeIds().size());
    }

    /**
     * 使引用指定文件节点的影视库缓存失效。
     *
     * @param fileNodeIds 文件节点 ID
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void invalidateFileVisibility(Collection<UUID> fileNodeIds) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return;
        }
        Set<UUID> owners = new HashSet<>();
        videoItemRepository.findByFileNodeIdIn(fileNodeIds).stream()
                .map(MediaVideoItem::getOwnerUserId)
                .filter(Objects::nonNull)
                .forEach(owners::add);
        subtitleTrackRepository.findByFileNodeIdIn(fileNodeIds).stream()
                .map(track -> track.getOwnerUserId())
                .filter(Objects::nonNull)
                .forEach(owners::add);
        owners.forEach(ownerUserId -> syncEventService.invalidate(
                ownerUserId,
                SyncScope.VIDEO,
                "VIDEO_LIBRARY",
                Map.of("reason", "FILE_VISIBILITY_CHANGED")
        ));
    }

    private void deleteOwnedRows(UUID ownerUserId, List<MediaVideoItem> videos) {
        if (videos.isEmpty()) {
            return;
        }
        List<UUID> videoItemIds = videos.stream().map(MediaVideoItem::getId).toList();
        List<String> videoKeys = videoItemIds.stream().map(UUID::toString).toList();
        playbackCleanupService.deleteOwned(ownerUserId, MediaPlaybackType.VIDEO, videoKeys);
        watchHistoryRepository.deleteByOwnerUserIdAndVideoItemIdIn(ownerUserId, videoItemIds);
        videoFavoriteRepository.deleteByOwnerUserIdAndVideoItemIdIn(ownerUserId, videoItemIds);
        collectionItemRepository.deleteByOwnerUserIdAndVideoItemIdIn(ownerUserId, videoItemIds);
        subtitleTrackRepository.deleteByOwnerUserIdAndVideoItemIdIn(ownerUserId, videoItemIds);
        nfoExportRepository.deleteByOwnerUserIdAndVideoItemIdIn(ownerUserId, videoItemIds);
        cleanupContentAssets(ownerUserId, videoItemIds);

        Set<UUID> movieIds = new HashSet<>();
        Set<UUID> episodeIds = new HashSet<>();
        Set<UUID> seriesIds = new HashSet<>();
        for (MediaVideoItem video : videos) {
            if (video.getMovieId() != null) {
                movieIds.add(video.getMovieId());
            }
            if (video.getEpisodeId() != null) {
                episodeIds.add(video.getEpisodeId());
            }
            if (video.getSeriesId() != null) {
                seriesIds.add(video.getSeriesId());
            }
        }

        videoItemRepository.deleteAllInBatch(videos);
        cleanupOrphanedMovieParents(ownerUserId, movieIds);
        cleanupOrphanedTvParents(ownerUserId, episodeIds, seriesIds);
        // 条目删除改变影视库各类统计，需失效 dashboard 缓存。
        readThroughCache.invalidate("omninest:dashboard:video:" + ownerUserId);
    }

    private void cleanupOrphanedMovieParents(UUID ownerUserId, Set<UUID> movieIds) {
        if (movieIds.isEmpty()) {
            return;
        }
        Set<UUID> moviesWithItems = new HashSet<>(
                videoItemRepository.findMovieIdsWithItems(ownerUserId, movieIds));
        List<UUID> toDelete = movieIds.stream()
                .filter(id -> !moviesWithItems.contains(id))
                .toList();
        if (!toDelete.isEmpty()) {
            deleteContentAssetRows(ownerUserId, ResourceType.MOVIE, toDelete);
            movieRepository.deleteByOwnerUserIdAndIdIn(ownerUserId, toDelete);
            log.info("已清理孤立电影: count={}, ids={}", toDelete.size(), toDelete);
        }
    }

    private void cleanupOrphanedTvParents(UUID ownerUserId, Set<UUID> episodeIds, Set<UUID> seriesIds) {
        Set<UUID> affectedSeriesIds = new HashSet<>(seriesIds);
        if (!episodeIds.isEmpty()) {
            Set<UUID> episodesWithItems = new HashSet<>(
                    videoItemRepository.findEpisodeIdsWithItems(ownerUserId, episodeIds));
            List<MediaTvEpisode> episodes = tvEpisodeRepository
                    .findAllByIdInAndOwnerUserId(episodeIds, ownerUserId);
            List<UUID> episodesToDelete = new ArrayList<>();
            for (MediaTvEpisode episode : episodes) {
                if (!episodesWithItems.contains(episode.getId())) {
                    episodesToDelete.add(episode.getId());
                    if (episode.getSeriesId() != null) {
                        affectedSeriesIds.add(episode.getSeriesId());
                    }
                }
            }
            if (!episodesToDelete.isEmpty()) {
                tvEpisodeRepository.deleteByOwnerUserIdAndIdIn(ownerUserId, episodesToDelete);
                log.info("已清理孤立剧集: count={}", episodesToDelete.size());
            }
        }

        if (affectedSeriesIds.isEmpty()) {
            return;
        }
        Set<UUID> seriesWithItems = new HashSet<>(
                videoItemRepository.findSeriesIdsWithItems(ownerUserId, affectedSeriesIds));
        List<MediaTvSeries> allSeries = tvSeriesRepository
                .findAllByIdInAndOwnerUserId(affectedSeriesIds, ownerUserId);
        List<UUID> seriesToDelete = new ArrayList<>();
        Set<UUID> seriesIdsToCheckSeasons = new HashSet<>();
        for (MediaTvSeries series : allSeries) {
            if (!seriesWithItems.contains(series.getId())) {
                seriesToDelete.add(series.getId());
            } else {
                seriesIdsToCheckSeasons.add(series.getId());
            }
        }

        cleanupOrphanedSeasons(ownerUserId, seriesIdsToCheckSeasons);
        deleteOrphanedSeries(ownerUserId, seriesToDelete);
    }

    private void cleanupOrphanedSeasons(UUID ownerUserId, Set<UUID> seriesIds) {
        for (UUID seriesId : seriesIds) {
            List<MediaTvSeason> seasons = tvSeasonRepository
                    .findByOwnerUserIdAndSeriesIdOrderBySeasonNumberAsc(ownerUserId, seriesId);
            for (MediaTvSeason season : seasons) {
                long episodeCount = videoItemRepository.countByOwnerUserIdAndSeriesIdAndSeasonNumber(
                        ownerUserId,
                        seriesId,
                        season.getSeasonNumber()
                );
                if (episodeCount == 0) {
                    tvSeasonRepository.delete(season);
                    log.info("已清理孤立季: seriesId={}, seasonNumber={}",
                            seriesId, season.getSeasonNumber());
                }
            }
        }
    }

    private void deleteOrphanedSeries(UUID ownerUserId, List<UUID> seriesIds) {
        if (seriesIds.isEmpty()) {
            return;
        }
        for (UUID seriesId : seriesIds) {
            List<MediaTvSeason> seasons = tvSeasonRepository
                    .findByOwnerUserIdAndSeriesIdOrderBySeasonNumberAsc(ownerUserId, seriesId);
            if (!seasons.isEmpty()) {
                tvSeasonRepository.deleteAll(seasons);
            }
        }
        seriesFavoriteRepository.deleteByOwnerUserIdAndSeriesIdIn(ownerUserId, seriesIds);
        deleteContentAssetRows(ownerUserId, ResourceType.TV_SERIES, seriesIds);
        tvSeriesRepository.deleteByOwnerUserIdAndIdIn(ownerUserId, seriesIds);
        log.info("已清理孤立系列: count={}, ids={}", seriesIds.size(), seriesIds);
    }

    private void clearDanglingFileReferences(List<UUID> deletedFileIds) {
        Set<UUID> fileIds = new HashSet<>(deletedFileIds);
        movieRepository.findByPosterFileIdIn(fileIds)
                .forEach(movie -> movie.setPosterFileId(null));
        movieRepository.findByBackdropFileIdIn(fileIds)
                .forEach(movie -> movie.setBackdropFileId(null));
        tvSeriesRepository.findByPosterFileIdIn(fileIds)
                .forEach(series -> series.setPosterFileId(null));
        tvSeriesRepository.findByBackdropFileIdIn(fileIds)
                .forEach(series -> series.setBackdropFileId(null));
        tvSeasonRepository.findByPosterFileIdIn(fileIds)
                .forEach(season -> season.setPosterFileId(null));
        tvEpisodeRepository.findByStillFileIdIn(fileIds)
                .forEach(episode -> episode.setStillFileId(null));
        videoCollectionRepository.findByCoverFileIdIn(fileIds)
                .forEach(collection -> collection.setCoverFileId(null));
    }

    private void cleanupContentAssets(UUID ownerUserId, List<UUID> resourceIds) {
        List<ContentAsset> assets = contentAssetRepository
                .findAllByOwnerUserIdAndResourceTypeAndResourceIdIn(
                        ownerUserId,
                        ResourceType.VIDEO_ITEM.getValue(),
                        resourceIds
                );
        if (assets.isEmpty()) {
            return;
        }
        contentAssetRepository.deleteAll(assets);
    }

    private void contributeMovieAssets(
            PurgeContext context,
            PurgeContributionWriter writer,
            List<MediaVideoItem> videos,
            List<UUID> videoIds
    ) {
        Set<UUID> orphanMovieIds = videos.stream()
                .map(MediaVideoItem::getMovieId)
                .filter(Objects::nonNull)
                .filter(movieId -> videoItemRepository.countByOwnerUserIdAndMovieIdAndIdNotIn(
                        context.ownerUserId(), movieId, videoIds) == 0)
                .collect(Collectors.toSet());
        List<MediaMovie> movies = movieRepository.findAllByIdInAndOwnerUserId(
                orphanMovieIds,
                context.ownerUserId()
        );
        writer.addFileNodeIds(movies.stream().map(MediaMovie::getPosterFileId).filter(Objects::nonNull).toList());
        writer.addFileNodeIds(movies.stream().map(MediaMovie::getBackdropFileId).filter(Objects::nonNull).toList());
        addContentAssetFiles(writer, context.ownerUserId(), ResourceType.MOVIE, orphanMovieIds);
    }

    private void contributeEpisodeAndSeriesAssets(
            PurgeContext context,
            PurgeContributionWriter writer,
            List<MediaVideoItem> videos,
            List<UUID> videoIds
    ) {
        Set<UUID> orphanEpisodeIds = videos.stream()
                .map(MediaVideoItem::getEpisodeId)
                .filter(Objects::nonNull)
                .filter(episodeId -> videoItemRepository.countByOwnerUserIdAndEpisodeIdAndIdNotIn(
                        context.ownerUserId(), episodeId, videoIds) == 0)
                .collect(Collectors.toSet());
        List<MediaTvEpisode> episodes = tvEpisodeRepository
                .findAllByIdInAndOwnerUserId(orphanEpisodeIds, context.ownerUserId());
        writer.addFileNodeIds(episodes.stream()
                .map(MediaTvEpisode::getStillFileId)
                .filter(Objects::nonNull)
                .toList());

        Set<UUID> orphanSeriesIds = videos.stream()
                .map(MediaVideoItem::getSeriesId)
                .filter(Objects::nonNull)
                .filter(seriesId -> videoItemRepository.countByOwnerUserIdAndSeriesIdAndIdNotIn(
                        context.ownerUserId(), seriesId, videoIds) == 0)
                .collect(Collectors.toSet());
        List<MediaTvSeries> series = tvSeriesRepository
                .findAllByIdInAndOwnerUserId(orphanSeriesIds, context.ownerUserId());
        writer.addFileNodeIds(series.stream().map(MediaTvSeries::getPosterFileId).filter(Objects::nonNull).toList());
        writer.addFileNodeIds(series.stream().map(MediaTvSeries::getBackdropFileId).filter(Objects::nonNull).toList());
        addContentAssetFiles(writer, context.ownerUserId(), ResourceType.TV_SERIES, orphanSeriesIds);

        Set<SeasonKey> affectedSeasons = videos.stream()
                .filter(video -> video.getSeriesId() != null && video.getSeasonNumber() != null)
                .map(video -> new SeasonKey(video.getSeriesId(), video.getSeasonNumber()))
                .collect(Collectors.toSet());
        for (SeasonKey seasonKey : affectedSeasons) {
            if (videoItemRepository.countSeasonItemsOutsideTarget(
                    context.ownerUserId(), seasonKey.seriesId(), seasonKey.seasonNumber(), videoIds) > 0) {
                continue;
            }
            tvSeasonRepository.findByOwnerUserIdAndSeriesIdOrderBySeasonNumberAsc(
                            context.ownerUserId(), seasonKey.seriesId())
                    .stream()
                    .filter(season -> seasonKey.seasonNumber().equals(season.getSeasonNumber()))
                    .map(MediaTvSeason::getPosterFileId)
                    .filter(Objects::nonNull)
                    .forEach(fileId -> writer.addFileNodeIds(List.of(fileId)));
        }
    }

    private void addContentAssetFiles(
            PurgeContributionWriter writer,
            UUID ownerUserId,
            ResourceType resourceType,
            Collection<UUID> resourceIds
    ) {
        if (resourceIds.isEmpty()) {
            return;
        }
        writer.addFileNodeIds(contentAssetRepository
                .findAllByOwnerUserIdAndResourceTypeAndResourceIdIn(
                        ownerUserId,
                        resourceType.getValue(),
                        resourceIds
                )
                .stream()
                .map(ContentAsset::getFileNodeId)
                .filter(Objects::nonNull)
                .toList());
    }

    private void deleteContentAssetRows(
            UUID ownerUserId,
            ResourceType resourceType,
            Collection<UUID> resourceIds
    ) {
        if (resourceIds.isEmpty()) {
            return;
        }
        List<ContentAsset> assets = contentAssetRepository
                .findAllByOwnerUserIdAndResourceTypeAndResourceIdIn(
                        ownerUserId,
                        resourceType.getValue(),
                        resourceIds
                );
        if (!assets.isEmpty()) {
            contentAssetRepository.deleteAll(assets);
        }
    }

    private record SeasonKey(UUID seriesId, Integer seasonNumber) {
    }
}
