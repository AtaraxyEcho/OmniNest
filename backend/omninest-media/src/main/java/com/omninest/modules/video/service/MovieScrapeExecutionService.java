package com.omninest.modules.video.service;

import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.modules.video.domain.SeriesType;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaTvEpisode;
import com.omninest.modules.video.domain.MediaTvSeason;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.CastMemberDto;
import com.omninest.modules.video.dto.MovieDtos.CrewMemberDto;
import com.omninest.modules.video.dto.MovieDtos.ScrapeCandidateDto;
import com.omninest.modules.video.event.MediaScrapeRequestedEvent;
import com.omninest.modules.video.event.VideoProbeEvent;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.service.DerivedAssetRequest;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.time.LocalDate;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import jakarta.annotation.PostConstruct;
import java.util.Optional;
import java.util.UUID;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 影视元数据刮削任务执行服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MovieScrapeExecutionService {
    private final MediaRuntimeConfigService configService;
    private final MediaVideoItemRepository videoItemRepository;
    private final TaskRecordService taskRecordService;
    private final List<MetadataProvider> metadataProviders;
    private final ContentAssetService contentAssetService;
    private final ApplicationEventPublisher applicationEventPublisher;
    private final MediaTvSeriesRepository tvSeriesRepository;
    private final MediaTvSeasonRepository tvSeasonRepository;
    private final MediaMovieRepository movieRepository;
    private final MediaTvEpisodeRepository episodeRepository;
    private final NotificationPublisher notificationService;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final MediaSyncEventService syncEventService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final ReadThroughCache readThroughCache;
    private final PlatformTransactionManager transactionManager;
    private TransactionTemplate transactionTemplate;

    @PostConstruct
    void initTransactionTemplate() {
        this.transactionTemplate = new TransactionTemplate(transactionManager);
    }

    /**
     * 执行刮削任务。
     *
     * <p>元数据检索是外部 HTTP（连接/读取超时可达十秒以上），必须在事务外发起；写库与
     * 同步事件集中在一个短事务里，边界与拆分前的整方法事务一致。同步事件记录器要求
     * 外层事务（MANDATORY 传播），因此 {@code recordVideoUpdated} 只能在事务内调用。</p>
     */
    public void execute(MediaScrapeRequestedEvent event) {
        if (!taskRecordService.claimForExecution(event.taskId(), "SCRAPING")) {
            return;
        }
        fileLifecycleGuard.requireReadable(event.ownerUserId(), event.fileNodeId());

        // 一个文件只有一条业务行，行 owner 是文件所有者：按 fileNodeId 定位，
        // 否则请求者与所有者不同时会查不到而行，甚至重复插入撞 uniq_media_video_items_file。
        Optional<MediaVideoItem> itemOpt = videoItemRepository.findByFileNodeId(event.fileNodeId());
        if (itemOpt.isEmpty()) {
            log.warn("媒体条目不存在: taskId={}, fileNodeId={}", event.taskId(), event.fileNodeId());
            taskRecordService.markFailed(event.taskId(), "媒体条目不存在");
            // 发送刮削失败通知
            notificationService.notifyOrLog(event.ownerUserId(), "TASK_FAILED",
                    "视频刮削失败", "媒体条目不存在",
                    Map.of("taskId", event.taskId().toString()));
            return;
        }
        MediaVideoItem item = itemOpt.get();
        if (!configService.metadataProvidersEnabled()) {
            log.info("元数据提供器未启用，跳过刮削: taskId={}", event.taskId());
            taskRecordService.markCompleted(event.taskId(), resultMap("元数据提供器未启用", null));
            return;
        }

        FileNameGuess guess = new FileNameGuess(event.title(), event.year(), event.seasonNumber(), event.episodeNumber());
        Optional<ScrapeCandidateDto> candidateOpt = metadataProviders.stream()
                .flatMap(provider -> {
                    log.info("调用元数据提供器: provider={}", provider.providerName());
                    List<ScrapeCandidateDto> results = provider.search(guess);
                    log.info("元数据提供器返回: provider={}, candidates={}", provider.providerName(), results.size());
                    return results.stream();
                })
                .findFirst();
        if (candidateOpt.isEmpty()) {
            transactionTemplate.executeWithoutResult(status -> finishUnmatched(event, item, guess));
            return;
        }
        ScrapeCandidateDto candidate = candidateOpt.get();
        transactionTemplate.executeWithoutResult(status -> finishMatched(event, item, candidate));
    }

    private void finishUnmatched(MediaScrapeRequestedEvent event, MediaVideoItem item, FileNameGuess guess) {
        log.warn("未匹配到元数据: taskId={}, title={}, year={}", event.taskId(), guess.title(), guess.year());
        item.setMetadataStatus(MetadataStatus.FAILED.getValue());
        videoItemRepository.save(item);
        recordVideoUpdated(item.getOwnerUserId(), item, SyncAction.FAILED);
        taskRecordService.markFailed(event.taskId(), "没有匹配到元数据");
        // 发送刮削失败通知
        notificationService.notifyOrLog(event.ownerUserId(), "TASK_FAILED",
                "视频刮削失败", "未找到《" + guess.title() + "》的元数据",
                Map.of("taskId", event.taskId().toString(), "title", guess.title()));
    }

    private void finishMatched(MediaScrapeRequestedEvent event, MediaVideoItem item, ScrapeCandidateDto candidate) {
        fileLifecycleGuard.requireReadable(event.ownerUserId(), event.fileNodeId());

        log.info("匹配到元数据: taskId={}, provider={}, externalId={}, title={}, originalTitle={}, releaseDate={}, runtime={}",
                event.taskId(), candidate.provider(), candidate.externalId(), candidate.title(),
                candidate.originalTitle(), candidate.runtimeMinutes());

        boolean isEpisode = MediaType.EPISODE.getValue().equals(item.getMediaType());
        ScrapeAssetPlan plan = transactionTemplate.execute(status -> isEpisode
                ? prepareEpisodeTargets(item, candidate)
                : prepareMovieTargets(item, candidate));

        // 海报与背景图是 TMDB 图片下载 + MinIO 入库（单张读取超时 30 秒、最多跟随 5 次重定向），
        // 必须落在两次短事务之间：Worker 的数据库连接池很小，外部网络整段占住会拖垮其他消费者。
        ScrapeAssetRefs refs = fetchAssetRefs(plan, candidate);

        transactionTemplate.executeWithoutResult(status -> {
            applyAssetRefs(plan, refs);
            // 文件级信息仍写入 video_item
            fileLifecycleGuard.requireReadable(event.ownerUserId(), event.fileNodeId());
            videoItemRepository.save(item);
            applicationEventPublisher.publishEvent(new VideoProbeEvent(item));
            taskRecordService.markCompleted(event.taskId(), resultMap("元数据刮削完成", candidate));
            recordVideoUpdated(item.getOwnerUserId(), item, SyncAction.UPDATED);
        });

        log.info("刮削完成: taskId={}, itemId={}, mediaType={}, provider={}",
                event.taskId(), item.getId(), item.getMediaType(), candidate.provider());
        // 发送刮削完成通知
        notificationService.notifyOrLog(event.ownerUserId(), "TASK_COMPLETED",
                "视频刮削完成", "《" + candidate.title() + "》元数据已更新",
                Map.of("taskId", event.taskId().toString(), "itemId", item.getId().toString()));
    }

    /**
     * 下载并入库主海报/背景图；返回全空表示本次不需要同步或同步未产出可用对象。
     */
    private ScrapeAssetRefs fetchAssetRefs(ScrapeAssetPlan plan, ScrapeCandidateDto candidate) {
        if (plan == null) {
            return ScrapeAssetRefs.empty();
        }
        // 演职员头像与海报/背景图同样是一次 HTTP + 对象存储写入，必须留在事务外。
        Map<String, UUID> profileFileIds = fetchProfileImages(plan, candidate);
        if (!plan.requireAssets()) {
            return new ScrapeAssetRefs(null, null, profileFileIds);
        }
        if (plan.series()) {
            ContentAssetService.SeriesAssetResult assets =
                    contentAssetService.syncPrimarySeriesAssets(plan.ownerUserId(), plan.resourceId(), candidate);
            return new ScrapeAssetRefs(assets.posterFileId(), assets.backdropFileId(), profileFileIds);
        }
        ContentAssetService.MovieAssetResult assets =
                contentAssetService.syncPrimaryMovieAssets(plan.resourceId(), plan.ownerUserId(), candidate);
        return new ScrapeAssetRefs(assets.posterFileId(), assets.backdropFileId(), profileFileIds);
    }

    /**
     * 下载演职员头像：同一张 profilePath 在一次刮削内只下载一次。
     */
    private Map<String, UUID> fetchProfileImages(ScrapeAssetPlan plan, ScrapeCandidateDto candidate) {
        Map<String, String> pathsByName = new LinkedHashMap<>();
        if (candidate.castMembers() != null) {
            for (CastMemberDto member : candidate.castMembers()) {
                if (member.profilePath() != null && !member.profilePath().isBlank()) {
                    pathsByName.putIfAbsent(member.profilePath(), member.name());
                }
            }
        }
        if (candidate.crewMembers() != null) {
            for (CrewMemberDto member : candidate.crewMembers()) {
                if (member.profilePath() != null && !member.profilePath().isBlank()) {
                    pathsByName.putIfAbsent(member.profilePath(), member.name());
                }
            }
        }
        if (pathsByName.isEmpty()) {
            return Map.of();
        }
        String resourceType = plan.series() ? ResourceType.TV_SERIES.getValue() : ResourceType.MOVIE.getValue();
        Map<String, UUID> fileIdsByPath = new LinkedHashMap<>();
        for (Map.Entry<String, String> entry : pathsByName.entrySet()) {
            UUID fileId = storeProfileImage(
                    plan.ownerUserId(), plan.resourceId(), resourceType, entry.getKey(), entry.getValue());
            if (fileId != null) {
                fileIdsByPath.put(entry.getKey(), fileId);
            }
        }
        return fileIdsByPath;
    }


    /**
     * 把已入库的资产引用回填到电影或系列行上。
     */
    private void applyAssetRefs(ScrapeAssetPlan plan, ScrapeAssetRefs refs) {
        if (plan.series()) {
            MediaTvSeries series = tvSeriesRepository
                    .findByIdAndOwnerUserId(plan.resourceId(), plan.ownerUserId())
                    .orElse(null);
            if (series == null) {
                return;
            }
            boolean changed = false;
            if (refs.posterFileId() != null) {
                series.setPosterFileId(refs.posterFileId());
                changed = true;
            }
            if (refs.backdropFileId() != null) {
                series.setBackdropFileId(refs.backdropFileId());
                changed = true;
            }
            changed |= applyProfileFileIds(series.getCastMembers(), refs.profileFileIds());
            changed |= applyProfileFileIds(series.getCrewMembers(), refs.profileFileIds());
            if (changed) {
                tvSeriesRepository.save(series);
            }
            return;
        }
        MediaMovie movie = movieRepository
                .findByIdAndOwnerUserId(plan.resourceId(), plan.ownerUserId())
                .orElse(null);
        if (movie == null) {
            return;
        }
        boolean changed = false;
        if (refs.posterFileId() != null) {
            movie.setPosterFileId(refs.posterFileId());
            changed = true;
        }
        if (refs.backdropFileId() != null) {
            movie.setBackdropFileId(refs.backdropFileId());
            changed = true;
        }
        changed |= applyProfileFileIds(movie.getCastMembers(), refs.profileFileIds());
        changed |= applyProfileFileIds(movie.getCrewMembers(), refs.profileFileIds());
        if (changed) {
            movieRepository.save(movie);
        }
    }

    private boolean applyProfileFileIds(List<Map<String, Object>> members, Map<String, UUID> profileFileIds) {
        if (members == null || members.isEmpty() || profileFileIds.isEmpty()) {
            return false;
        }
        boolean changed = false;
        for (Map<String, Object> member : members) {
            Object path = member.get("profilePath");
            if (path == null) {
                continue;
            }
            UUID fileId = profileFileIds.get(path.toString());
            if (fileId != null && !fileId.toString().equals(member.get("profileFileId"))) {
                member.put("profileFileId", fileId.toString());
                changed = true;
            }
        }
        return changed;
    }

    /**
     * 层级落库后的资产同步计划：{@code resourceId} 是电影 ID 或系列 ID。
     */
    private record ScrapeAssetPlan(
            UUID ownerUserId,
            UUID resourceId,
            boolean series,
            boolean requireAssets
    ) {
    }

    /**
     * 外部图片本地化后的资产引用。
     */
    private record ScrapeAssetRefs(
            UUID posterFileId,
            UUID backdropFileId,
            Map<String, UUID> profileFileIds
    ) {

        static ScrapeAssetRefs empty() {
            return new ScrapeAssetRefs(null, null, Map.of());
        }
    }

    private void recordVideoUpdated(UUID ownerUserId, MediaVideoItem item, SyncAction action) {
        // 元数据状态流转影响 scrapeFailedCount 统计，需同步失效 dashboard 缓存。
        readThroughCache.invalidate("omninest:dashboard:video:" + ownerUserId);
        syncEventService.record(
                ownerUserId,
                SyncScope.VIDEO,
                "VIDEO_ITEM",
                item.getId().toString(),
                action,
                item.getVersion(),
                Map.of("metadataStatus", item.getMetadataStatus())
        );
    }

    private ScrapeAssetPlan prepareMovieTargets(MediaVideoItem item, ScrapeCandidateDto candidate) {
        // 扫描已经建立电影实体时直接补充该实体，避免同一个本地文件形成两部电影。
        MediaMovie movie = item.getMovieId() == null
                ? findOrCreateMovie(item.getOwnerUserId(), candidate)
                : movieRepository.findByIdAndOwnerUserId(item.getMovieId(), item.getOwnerUserId())
                        .orElseGet(() -> findOrCreateMovie(item.getOwnerUserId(), candidate));
        applyMovieCandidate(movie, candidate);
        movieRepository.save(movie);

        // 关联 video_item → movie
        item.setMovieId(movie.getId());
        item.setMetadataStatus(MetadataStatus.MATCHED.getValue());
        if (item.getVersionLabel() == null || item.getVersionLabel().isBlank()) {
            item.setVersionLabel(buildVersionLabel(item));
        }
        return new ScrapeAssetPlan(item.getOwnerUserId(), movie.getId(), false, true);
    }

    private ScrapeAssetPlan prepareEpisodeTargets(MediaVideoItem item, ScrapeCandidateDto candidate) {
        // 扫描阶段已经建立 Series/Season/Episode 层级，刮削只更新 Series，不按 Episode 再次搜索。
        MediaTvSeries series = resolveSeries(item, candidate);
        // 只有还没有海报的系列才需要外部图片；判断必须在落库前取，资产同步在事务外进行。
        boolean seriesNeedsAssets = series.getPosterFileId() == null;
        applySeriesCandidate(series, candidate);
        tvSeriesRepository.save(series);

        // 查找或创建 MediaTvSeason
        Integer seasonNumber = item.getSeasonNumber();
        UUID seasonId = null;
        if (seasonNumber != null) {
            MediaTvSeason season = findOrCreateSeason(item.getOwnerUserId(), series.getId(), seasonNumber);
            seasonId = season.getId();
            item.setSeriesId(series.getId());
            item.setSeasonId(seasonId);
        } else {
            item.setSeriesId(series.getId());
        }

        // 查找或创建 MediaTvEpisode（带乐观重试）
        if (seasonNumber != null && item.getEpisodeNumber() != null) {
            MediaTvEpisode episode = findOrCreateEpisode(
                    item.getOwnerUserId(), series.getId(), seasonId, seasonNumber, item.getEpisodeNumber());
            item.setEpisodeId(episode.getId());

            // 更新季的集数
            updateSeasonEpisodeCount(seasonId, item.getOwnerUserId(), series.getId(), seasonNumber);
        }

        // 回溯关联孤立剧集
        linkOrphanedEpisodes(item.getOwnerUserId(), series.getId());

        // 一个 Series 的外部元数据由所有分集复用；Episode 只维持文件与层级关联。
        // 本次条目自身排除在外：它的行由完成事务落库，同批保存会让那份实体版本失效。
        List<MediaVideoItem> otherSeriesItems = videoItemRepository
                .findByOwnerUserIdAndSeriesIdOrderBySeasonNumberAscEpisodeNumberAsc(
                        item.getOwnerUserId(), series.getId())
                .stream()
                .filter(seriesItem -> !seriesItem.getId().equals(item.getId()))
                .toList();
        for (MediaVideoItem seriesItem : otherSeriesItems) {
            seriesItem.setMetadataStatus(MetadataStatus.MATCHED.getValue());
            if (seriesItem.getVersionLabel() == null || seriesItem.getVersionLabel().isBlank()) {
                seriesItem.setVersionLabel(buildVersionLabel(seriesItem));
            }
        }
        if (!otherSeriesItems.isEmpty()) {
            videoItemRepository.saveAll(otherSeriesItems);
        }
        item.setMetadataStatus(MetadataStatus.MATCHED.getValue());
        if (item.getVersionLabel() == null || item.getVersionLabel().isBlank()) {
            item.setVersionLabel(buildVersionLabel(item));
        }
        return new ScrapeAssetPlan(item.getOwnerUserId(), series.getId(), true, seriesNeedsAssets);
    }

    private MediaMovie findOrCreateMovie(UUID ownerUserId, ScrapeCandidateDto candidate) {
        Integer tmdbId;
        try {
            tmdbId = Integer.parseInt(candidate.externalId());
        } catch (NumberFormatException e) {
            // 无法解析为 TMDB ID，创建无 tmdbId 的记录
            MediaMovie movie = new MediaMovie();
            movie.setOwnerUserId(ownerUserId);
            movie.setTitle(candidate.title() != null ? candidate.title() : "未知影片");
            return movie;
        }

        try {
            return movieRepository.findByTmdbIdAndOwnerUserId(tmdbId, ownerUserId)
                    .orElseGet(() -> {
                        MediaMovie movie = new MediaMovie();
                        movie.setOwnerUserId(ownerUserId);
                        movie.setTmdbId(tmdbId);
                        movie.setTitle(candidate.title() != null ? candidate.title() : "未知影片");
                        return movieRepository.save(movie);
                    });
        } catch (DataIntegrityViolationException e) {
            log.info("并发创建电影冲突，重新查找: tmdbId={}, ownerUserId={}", tmdbId, ownerUserId);
            return movieRepository.findByTmdbIdAndOwnerUserId(tmdbId, ownerUserId)
                    .orElseThrow(() -> new IllegalStateException("唯一约束冲突后仍无法找到电影记录: tmdbId=" + tmdbId));
        }
    }

    /**
     * 优先沿用扫描阶段建立的系列，避免刮削另建无 librarySourceId 的系列
     * 导致剧集/动漫从 seriesByType 查询中消失。
     */
    private MediaTvSeries resolveSeries(MediaVideoItem item, ScrapeCandidateDto candidate) {
        if (item.getSeriesId() != null) {
            MediaTvSeries existing = tvSeriesRepository
                    .findByIdAndOwnerUserId(item.getSeriesId(), item.getOwnerUserId())
                    .orElse(null);
            if (existing != null) {
                return existing;
            }
        }
        return findOrCreateSeries(item.getOwnerUserId(), candidate, item.getLibrarySourceId());
    }

    private MediaTvSeries findOrCreateSeries(
            UUID ownerUserId,
            ScrapeCandidateDto candidate,
            UUID librarySourceId
    ) {
        Integer tmdbId;
        try {
            tmdbId = Integer.parseInt(candidate.externalId());
        } catch (NumberFormatException e) {
            // 无法解析为 TMDB ID，创建无 tmdbId 的记录
            MediaTvSeries series = new MediaTvSeries();
            series.setOwnerUserId(ownerUserId);
            series.setLibrarySourceId(librarySourceId);
            series.setTitle(candidate.title() != null ? candidate.title() : "未知剧集");
            return series;
        }

        try {
            return tvSeriesRepository.findByTmdbIdAndOwnerUserId(tmdbId, ownerUserId)
                    .map(existing -> {
                        if (existing.getLibrarySourceId() == null && librarySourceId != null) {
                            existing.setLibrarySourceId(librarySourceId);
                        }
                        return existing;
                    })
                    .orElseGet(() -> {
                        MediaTvSeries newSeries = new MediaTvSeries();
                        newSeries.setOwnerUserId(ownerUserId);
                        newSeries.setLibrarySourceId(librarySourceId);
                        newSeries.setTmdbId(tmdbId);
                        newSeries.setTitle(candidate.title());
                        newSeries.setOriginalTitle(candidate.originalTitle());
                        newSeries.setFirstAirDate(candidate.releaseDate());
                        newSeries.setOverview(candidate.overview());
                        newSeries.setRating(candidate.voteAverage());
                        newSeries.setVoteCount(candidate.voteCount() != null ? candidate.voteCount() : 0);
                        newSeries.setPopularity(candidate.popularity());
                        newSeries.setOriginalLanguage(candidate.originalLanguage());
                        newSeries.setContentRating(candidate.contentRating());
                        newSeries.setMetadataStatus(MetadataStatus.MATCHED.getValue());
                        if (candidate.genres() != null) {
                            List<Map<String, Object>> genreMaps = new ArrayList<>();
                            for (String name : candidate.genres()) {
                                Map<String, Object> g = new LinkedHashMap<>();
                                g.put("name", name);
                                genreMaps.add(g);
                            }
                            newSeries.setGenres(genreMaps);
                        }
                        Map<String, Object> seriesExternalIds = new LinkedHashMap<>();
                        seriesExternalIds.put("provider", candidate.provider());
                        seriesExternalIds.put("externalId", candidate.externalId());
                        newSeries.setExternalIds(seriesExternalIds);
                        newSeries.setSeriesType(detectSeriesType(candidate.genres(), candidate.originalLanguage()));
                        return tvSeriesRepository.save(newSeries);
                    });
        } catch (DataIntegrityViolationException e) {
            log.info("并发创建系列冲突，重新查找: tmdbId={}, ownerUserId={}", tmdbId, ownerUserId);
            return tvSeriesRepository.findByTmdbIdAndOwnerUserId(tmdbId, ownerUserId)
                    .orElseThrow(() -> new IllegalStateException("唯一约束冲突后仍无法找到系列记录: tmdbId=" + tmdbId));
        }
    }

    private String detectSeriesType(List<String> genres, String originalLanguage) {
        if (genres != null && genres.contains("Animation")
                && "ja".equalsIgnoreCase(originalLanguage)) {
            return SeriesType.ANIME.getValue();
        }
        return SeriesType.TV.getValue();
    }

    private MediaTvSeason findOrCreateSeason(UUID ownerUserId, UUID seriesId, Integer seasonNumber) {
        return tvSeasonRepository
                .findByOwnerUserIdAndSeriesIdAndSeasonNumber(ownerUserId, seriesId, seasonNumber)
                .orElseGet(() -> {
                    MediaTvSeason newSeason = new MediaTvSeason();
                    newSeason.setOwnerUserId(ownerUserId);
                    newSeason.setSeriesId(seriesId);
                    newSeason.setSeasonNumber(seasonNumber);
                    newSeason.setTitle("第 " + seasonNumber + " 季");
                    newSeason.setEpisodeCount(0);
                    return tvSeasonRepository.save(newSeason);
                });
    }

    private MediaTvEpisode findOrCreateEpisode(UUID ownerUserId, UUID seriesId, UUID seasonId,
            Integer seasonNumber, Integer episodeNumber) {
        try {
            return episodeRepository
                    .findByOwnerUserIdAndSeriesIdAndSeasonNumberAndEpisodeNumber(
                            ownerUserId, seriesId, seasonNumber, episodeNumber)
                    .orElseGet(() -> {
                        MediaTvEpisode ep = new MediaTvEpisode();
                        ep.setOwnerUserId(ownerUserId);
                        ep.setSeriesId(seriesId);
                        ep.setSeasonId(seasonId);
                        ep.setSeasonNumber(seasonNumber);
                        ep.setEpisodeNumber(episodeNumber);
                        return episodeRepository.save(ep);
                    });
        } catch (DataIntegrityViolationException e) {
            log.info("并发创建剧集冲突，重新查找: seriesId={}, S{}E{}", seriesId, seasonNumber, episodeNumber);
            return episodeRepository
                    .findByOwnerUserIdAndSeriesIdAndSeasonNumberAndEpisodeNumber(
                            ownerUserId, seriesId, seasonNumber, episodeNumber)
                    .orElseThrow(() -> new IllegalStateException(
                            "唯一约束冲突后仍无法找到剧集记录: seriesId=" + seriesId + " S" + seasonNumber + "E" + episodeNumber));
        }
    }

    private void applyMovieCandidate(MediaMovie movie, ScrapeCandidateDto candidate) {
        movie.setTitle(candidate.title());
        if (candidate.originalTitle() != null && !candidate.originalTitle().isBlank()) {
            movie.setOriginalTitle(candidate.originalTitle());
        }
        if (candidate.releaseDate() != null) {
            movie.setReleaseDate(candidate.releaseDate());
        } else if (candidate.year() != null) {
            movie.setReleaseDate(LocalDate.of(candidate.year(), 1, 1));
        }
        movie.setOverview(candidate.overview());
        if (candidate.runtimeMinutes() != null) {
            movie.setRuntimeSeconds(candidate.runtimeMinutes() * 60);
        }
        try {
            movie.setTmdbId(Integer.parseInt(candidate.externalId()));
        } catch (NumberFormatException ignored) {
            log.debug("忽略: {}", ignored.getMessage());
        }
        if (candidate.imdbId() != null && !candidate.imdbId().isBlank()) {
            movie.setImdbId(candidate.imdbId());
        }
        movie.setRating(candidate.voteAverage());
        if (candidate.voteCount() != null) {
            movie.setVoteCount(candidate.voteCount());
        }
        if (candidate.popularity() != null) {
            movie.setPopularity(candidate.popularity());
        }
        if (candidate.originalLanguage() != null && !candidate.originalLanguage().isBlank()) {
            movie.setOriginalLanguage(candidate.originalLanguage());
        }
        if (candidate.tagline() != null && !candidate.tagline().isBlank()) {
            movie.setTagline(candidate.tagline());
        }
        if (candidate.contentRating() != null && !candidate.contentRating().isBlank()) {
            movie.setContentRating(candidate.contentRating());
        }
        if (candidate.genres() != null && !candidate.genres().isEmpty()) {
            List<Map<String, Object>> genreMaps = new ArrayList<>();
            for (String name : candidate.genres()) {
                Map<String, Object> g = new LinkedHashMap<>();
                g.put("name", name);
                genreMaps.add(g);
            }
            movie.setGenres(genreMaps);
        }
        if (candidate.castMembers() != null && !candidate.castMembers().isEmpty()) {
            List<Map<String, Object>> castMaps = new ArrayList<>();
            for (var member : candidate.castMembers()) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("name", member.name());
                m.put("character", member.character());
                if (member.profilePath() != null) {
                    m.put("profilePath", member.profilePath());
                }
                if (member.order() != null) m.put("order", member.order());
                castMaps.add(m);
            }
            movie.setCastMembers(castMaps);
        }
        if (candidate.crewMembers() != null && !candidate.crewMembers().isEmpty()) {
            List<Map<String, Object>> crewMaps = new ArrayList<>();
            for (var member : candidate.crewMembers()) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("name", member.name());
                m.put("job", member.job());
                m.put("department", member.department());
                if (member.profilePath() != null) {
                    m.put("profilePath", member.profilePath());
                }
                crewMaps.add(m);
            }
            movie.setCrewMembers(crewMaps);
        }
        if (candidate.studios() != null && !candidate.studios().isEmpty()) {
            movie.setStudios(candidate.studios());
        }
        if (candidate.countries() != null && !candidate.countries().isEmpty()) {
            movie.setCountries(candidate.countries());
        }
        movie.setLastScrapedAt(Instant.now());
        movie.setMetadataStatus(MetadataStatus.MATCHED.getValue());
        Map<String, Object> externalIds = movie.getExternalIds();
        externalIds.put("provider", candidate.provider());
        externalIds.put("externalId", candidate.externalId());
        if (candidate.imdbId() != null && !candidate.imdbId().isBlank()) {
            externalIds.put("imdbId", candidate.imdbId());
        }
        movie.setExternalIds(externalIds);
        Map<String, Object> metadata = movie.getMetadata();
        metadata.put("provider", candidate.provider());
        metadata.put("externalId", candidate.externalId());
        metadata.put("providerPosterUrl", candidate.posterUrl());
        metadata.put("providerBackdropUrl", candidate.backdropUrl());
        metadata.put("voteAverage", candidate.voteAverage());
        metadata.put("voteCount", candidate.voteCount());
        metadata.put("popularity", candidate.popularity());
        metadata.put("originalLanguage", candidate.originalLanguage());
        metadata.put("contentRating", candidate.contentRating());
        metadata.put("tagline", candidate.tagline());
        metadata.put("scrapedAt", Instant.now().toString());
        movie.setMetadata(metadata);
    }

    private void applySeriesCandidate(MediaTvSeries series, ScrapeCandidateDto candidate) {
        if (candidate.title() != null && !candidate.title().isBlank()) {
            series.setTitle(candidate.title());
            series.setSortTitle(candidate.title());
        }
        if (candidate.originalTitle() != null && !candidate.originalTitle().isBlank()) {
            series.setOriginalTitle(candidate.originalTitle());
        }
        if (candidate.releaseDate() != null) {
            series.setFirstAirDate(candidate.releaseDate());
        }
        if (candidate.overview() != null && !candidate.overview().isBlank()) {
            series.setOverview(candidate.overview());
        }
        if (candidate.voteAverage() != null) {
            series.setRating(candidate.voteAverage());
        }
        if (candidate.voteCount() != null) {
            series.setVoteCount(candidate.voteCount());
        }
        series.setPopularity(candidate.popularity());
        series.setOriginalLanguage(candidate.originalLanguage());
        series.setContentRating(candidate.contentRating());
        if (candidate.genres() != null) {
            List<Map<String, Object>> genres = new ArrayList<>();
            for (String name : candidate.genres()) {
                genres.add(Map.of("name", name));
            }
            series.setGenres(genres);
        }
        try {
            series.setTmdbId(Integer.parseInt(candidate.externalId()));
        } catch (NumberFormatException exception) {
            log.debug("系列外部 ID 不是 TMDB 数字 ID: provider={}", candidate.provider());
        }
        Map<String, Object> externalIds = new LinkedHashMap<>(series.getExternalIds());
        externalIds.put("provider", candidate.provider());
        externalIds.put("externalId", candidate.externalId());
        series.setExternalIds(externalIds);
        Map<String, Object> metadata = new LinkedHashMap<>(series.getMetadata());
        metadata.put("provider", candidate.provider());
        metadata.put("externalId", candidate.externalId());
        metadata.put("providerPosterUrl", candidate.posterUrl());
        metadata.put("providerBackdropUrl", candidate.backdropUrl());
        metadata.put("scrapedAt", Instant.now().toString());
        series.setMetadata(metadata);
        // 本地约定目录（Anime/TV）已定型系列类型；刮削仅在无库源归属时推断，
        // 且不得把已有 ANIME 降级为 TV。
        if (series.getLibrarySourceId() == null
                && !SeriesType.ANIME.getValue().equals(series.getSeriesType())) {
            series.setSeriesType(detectSeriesType(candidate.genres(), candidate.originalLanguage()));
        }
        // 剧集刮削按集触发：演员表仅在没有数据时补齐，避免每集刮削重复下载全部头像。
        if ((series.getCastMembers() == null || series.getCastMembers().isEmpty())
                && candidate.castMembers() != null && !candidate.castMembers().isEmpty()) {
            List<Map<String, Object>> castMaps = new ArrayList<>();
            for (var member : candidate.castMembers()) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("name", member.name());
                m.put("character", member.character());
                if (member.profilePath() != null) {
                    m.put("profilePath", member.profilePath());
                }
                if (member.order() != null) m.put("order", member.order());
                castMaps.add(m);
            }
            series.setCastMembers(castMaps);
        }
        if ((series.getCrewMembers() == null || series.getCrewMembers().isEmpty())
                && candidate.crewMembers() != null && !candidate.crewMembers().isEmpty()) {
            List<Map<String, Object>> crewMaps = new ArrayList<>();
            for (var member : candidate.crewMembers()) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("name", member.name());
                m.put("job", member.job());
                m.put("department", member.department());
                if (member.profilePath() != null) {
                    m.put("profilePath", member.profilePath());
                }
                crewMaps.add(m);
            }
            series.setCrewMembers(crewMaps);
        }
        series.setMetadataStatus(MetadataStatus.MATCHED.getValue());
        series.setLastScrapedAt(Instant.now());
    }

    /**
     * 回溯关联：将同系列下尚未关联 episode 逻辑实体的 video_items 补链。
     * 使用 Map 查找替代嵌套遍历，从 O(items * episodes) 降为 O(items + episodes)。
     */
    private void linkOrphanedEpisodes(UUID ownerUserId, UUID seriesId) {
        List<MediaTvEpisode> orphanEpisodes = episodeRepository
                .findByOwnerUserIdAndSeriesIdOrderBySeasonNumberAscEpisodeNumberAsc(ownerUserId, seriesId);
        if (orphanEpisodes.isEmpty()) {
            return;
        }
        // 构建 (seasonNumber, episodeNumber) → episode 索引
        Map<String, MediaTvEpisode> episodeIndex = new LinkedHashMap<>();
        for (MediaTvEpisode ep : orphanEpisodes) {
            if (ep.getSeasonNumber() != null && ep.getEpisodeNumber() != null) {
                episodeIndex.put(ep.getSeasonNumber() + ":" + ep.getEpisodeNumber(), ep);
            }
        }
        List<MediaVideoItem> items = videoItemRepository
                .findByOwnerUserIdAndSeriesIdOrderBySeasonNumberAscEpisodeNumberAsc(ownerUserId, seriesId);
        List<MediaVideoItem> toSave = new ArrayList<>();
        for (MediaVideoItem item : items) {
            if (item.getEpisodeId() != null || item.getSeasonNumber() == null || item.getEpisodeNumber() == null) {
                continue;
            }
            String key = item.getSeasonNumber() + ":" + item.getEpisodeNumber();
            MediaTvEpisode ep = episodeIndex.get(key);
            if (ep != null) {
                item.setEpisodeId(ep.getId());
                toSave.add(item);
                log.info("回溯关联 video_item → episode: itemId={}, episodeId={}", item.getId(), ep.getId());
            }
        }
        if (!toSave.isEmpty()) {
            videoItemRepository.saveAll(toSave);
        }
    }

    private void updateSeasonEpisodeCount(UUID seasonId, UUID ownerUserId, UUID seriesId, Integer seasonNumber) {
        tvSeasonRepository.findById(seasonId)
                .ifPresent(season -> {
                    long count = episodeRepository.countByOwnerUserIdAndSeriesIdAndSeasonNumber(
                            ownerUserId, seriesId, seasonNumber);
                    season.setEpisodeCount((int) count);
                    tvSeasonRepository.save(season);
                });
    }

    private String buildVersionLabel(MediaVideoItem item) {
        if (item.getResolutionHeight() != null) {
            return item.getResolutionHeight() + "p";
        }
        return "默认版本";
    }

    private Map<String, Object> resultMap(String message, ScrapeCandidateDto candidate) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("message", message);
        if (candidate != null) {
            result.put("provider", candidate.provider());
            result.put("externalId", candidate.externalId());
            result.put("title", candidate.title());
        }
        return result;
    }

    /**
     * 下载演员头像到 MinIO，返回 FileNode UUID。失败时返回 null（保留 TMDB URL 降级）。
     *
     * <p>文件名以头像 URL 摘要为前缀：TMDB 的 profile_path 按人唯一，哈希保证同一资源内
     * 不同演员、同名演员不会共用同一个派生文件；显示名仅用于可读性，不参与唯一性。</p>
     */
    private UUID storeProfileImage(
            UUID ownerUserId, UUID resourceId, String resourceType, String profileUrl, String personName) {
        if (profileUrl == null || profileUrl.isBlank()) {
            return null;
        }
        try {
            String safeName = (personName == null || personName.isBlank())
                    ? "profile"
                    : personName.replaceAll("[^\\p{L}\\p{N}\\-_]", "_").trim();
            return derivedAssetStorageService.storeRemote(new DerivedAssetRequest(
                    ownerUserId,
                    profileUrl,
                    resourceType,
                    resourceId,
                    "PROFILE",
                    profileUrlHash(profileUrl) + "_" + safeName + ".jpg",
                    "image/jpeg",
                    SpaceType.PERSONAL
            ));
        } catch (RuntimeException ex) {
            log.debug("演员头像下载失败，保留外部 URL: name={}, message={}", personName, ex.getMessage());
            return null;
        }
    }

    /**
     * 计算头像 URL 的短摘要作为文件名前缀。
     */
    private String profileUrlHash(String profileUrl) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(profileUrl.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest).substring(0, 8);
        } catch (NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 algorithm is unavailable", ex);
        }
    }
}
