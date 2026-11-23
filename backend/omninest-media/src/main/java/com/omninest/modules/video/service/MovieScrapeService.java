package com.omninest.modules.video.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.video.domain.NfoStatus;
import com.omninest.modules.video.domain.SeriesType;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.domain.FilePermission;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FilePermissionService;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaTvSeason;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.ScrapeCandidateDto;
import com.omninest.modules.video.dto.MovieDtos.ScrapeTaskDto;
import com.omninest.modules.video.event.MediaScrapeRequestedEvent;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 影视元数据刮削任务服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class MovieScrapeService {
    private static final List<String> ACTIVE_TASK_STATUSES = List.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RUNNING.getValue(),
            TaskStatus.RETRY_WAIT.getValue()
    );
    private static final Pattern PATH_SEASON_DIR = Pattern.compile(
            "(?i)^(?:season|series|s)[ ._-]*(\\d{1,2})$|^第([一二三四五六七八九十百\\d]+)季$");
    private static final Set<String> ANIME_PATH_HINTS = Set.of(
            "anime", "animes", "animation", "cartoon", "cartoons",
            "动画", "动漫", "番剧", "国漫", "日漫", "新番", "日本动漫", "国产动漫"
    );

    private final FileMetadataQueryService fileMetadataQueryService;
    private final TaskRecordService taskRecordService;
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaTvSeriesRepository tvSeriesRepository;
    private final MediaTvSeasonRepository tvSeasonRepository;
    private final SimpleFileNameParser fileNameParser;
    private final List<MetadataProvider> metadataProviders;
    private final TaskDispatchService taskDispatchService;
    private final FilePermissionService filePermissionService;
    private final MediaLibraryAccessService mediaLibraryAccessService;
    private final ReadThroughCache readThroughCache;

    /**
     * 仅登记待补充元数据的视频条目，不调用元数据提供器，也不创建刮削任务。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 已存在或新建的视频条目
     */
    @Transactional(rollbackFor = Exception.class)
    public MediaVideoItem registerPendingVideo(UUID ownerUserId, UUID fileNodeId) {
        FileDescriptor file = resolveVideoFile(ownerUserId, fileNodeId);
        FileNameGuess guess = fileNameParser.parse(file.name());
        // 一行一文件：先按 fileNodeId 定位再判写权限，按「请求者+文件」查会撞唯一键。
        MediaVideoItem existing = videoItemRepository.findByFileNodeId(fileNodeId).orElse(null);
        if (existing != null) {
            requireScrapeWritable(ownerUserId, existing);
            return existing;
        }
        requireFileWritableForScrape(ownerUserId, file);
        UUID catalogOwnerId = file.ownerUserId() != null ? file.ownerUserId() : ownerUserId;
        MediaVideoItem created = videoItemRepository.save(pendingVideo(catalogOwnerId, file, guess));
        // 新登记条目改变影视库统计，需失效 dashboard 缓存。
        readThroughCache.invalidate("omninest:dashboard:video:" + catalogOwnerId);
        return created;
    }

    /**
     * 批量登记待刮削视频，复用扫描阶段已加载的文件描述与既有条目。
     *
     * <p>不包单一事务：中途无权限时已登记条目保留，与逐文件登记一致。</p>
     *
     * @param ownerUserId 扫描发起者
     * @param files 待登记文件，调用方已按扫描规则过滤
     * @param existingByFileNodeId 已存在的业务行，键为文件节点 ID
     * @return 新登记条目数
     */
    public int registerPendingVideosBatch(
            UUID ownerUserId,
            List<FileDescriptor> files,
            Map<UUID, MediaVideoItem> existingByFileNodeId
    ) {
        if (files.isEmpty()) {
            return 0;
        }
        Set<UUID> touchedCatalogOwners = new LinkedHashSet<>();
        int registered = 0;
        // 系列/季缓存在整批复用：一部剧的文件通常连续出现，逐文件定位会重复同一查询。
        Map<String, MediaTvSeries> seriesMemo = new LinkedHashMap<>();
        Map<String, MediaTvSeason> seasonMemo = new LinkedHashMap<>();
        List<MediaVideoItem> pendingItems = new ArrayList<>();
        for (FileDescriptor file : files) {
            MediaVideoItem existing = existingByFileNodeId.get(file.id());
            if (existing != null) {
                requireScrapeWritable(ownerUserId, existing);
                continue;
            }
            requireFileWritableForScrape(ownerUserId, file);
            UUID catalogOwnerId = file.ownerUserId() != null ? file.ownerUserId() : ownerUserId;
            pendingItems.add(pendingVideo(
                    catalogOwnerId, file, fileNameParser.parse(file.name()), seriesMemo, seasonMemo));
            touchedCatalogOwners.add(catalogOwnerId);
            registered++;
        }
        videoItemRepository.saveAll(pendingItems);
        for (UUID catalogOwnerId : touchedCatalogOwners) {
            readThroughCache.invalidate("omninest:dashboard:video:" + catalogOwnerId);
        }
        return registered;
    }

    /**
     * 刮削写入只认行所有者；公共影视库条目额外接受该来源的管理员。
     */
    private void requireScrapeWritable(UUID requesterUserId, MediaVideoItem item) {
        if (item.getOwnerUserId().equals(requesterUserId)) {
            return;
        }
        if (item.getLibrarySourceId() != null) {
            mediaLibraryAccessService.requireManage(requesterUserId, item.getLibrarySourceId());
            return;
        }
        throw new BusinessException(ErrorCode.FORBIDDEN, "只有文件所有者能刮削该条目");
    }

    /**
     * 尚无业务行时按文件写权限判定：所有者，或共享空间内具备编辑权限的成员。
     */
    private void requireFileWritableForScrape(UUID requesterUserId, FileDescriptor file) {
        if (file.ownerUserId() == null || file.ownerUserId().equals(requesterUserId)) {
            return;
        }
        FilePermission permission = filePermissionService.resolvePermission(file.id(), requesterUserId);
        if (!permission.allowEdit()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权限刮削该文件");
        }
    }

    @Transactional(rollbackFor = Exception.class)
    public ScrapeTaskDto createScrapeTask(UUID ownerUserId, UUID fileNodeId, boolean force) {
        return createScrapeTask(ownerUserId, fileNodeId, force, null, null);
    }

    /**
     * 创建刮削任务；{@code provider}/{@code externalId} 非空时按指定候选刮削。
     *
     * @param ownerUserId 任务发起者
     * @param fileNodeId 视频文件节点 ID
     * @param force 是否强制覆盖既有元数据
     * @param provider 指定元数据提供器，可为空
     * @param externalId 指定候选外部 ID，可为空
     * @return 任务提交结果
     */
    @Transactional(rollbackFor = Exception.class)
    public ScrapeTaskDto createScrapeTask(
            UUID ownerUserId,
            UUID fileNodeId,
            boolean force,
            String provider,
            String externalId
    ) {
        FileDescriptor file = resolveVideoFile(ownerUserId, fileNodeId);
        FileNameGuess fileGuess = fileNameParser.parse(file.name());
        MediaVideoItem item = registerPendingVideo(ownerUserId, fileNodeId);
        FileNameGuess guess = scrapeGuess(item, fileGuess);
        ScrapeResource resource = scrapeResource(item);
        TaskRecord activeTask = taskRecordService.findActiveResourceTask(
                ownerUserId,
                "MEDIA_SCRAPE",
                resource.type(),
                resource.id(),
                ACTIVE_TASK_STATUSES
        ).orElse(null);
        String preferredProvider = blankToNull(provider);
        String preferredExternalId = blankToNull(externalId);
        if (activeTask != null) {
            boolean manualPickRetryWait = preferredExternalId != null
                    && TaskStatus.RETRY_WAIT.getValue().equals(activeTask.getStatus());
            if (!manualPickRetryWait) {
                return new ScrapeTaskDto(
                        activeTask.getId(),
                        activeTask.getStatus(),
                        "该媒体实体已有刮削任务正在执行"
                );
            }
            // 滞留的自动重试任务会静默吞掉用户手动选中的候选，先取消再入队。
            taskRecordService.markCancelled(activeTask.getId());
            log.info("取消滞留的自动刮削重试任务: taskId={}, fileNodeId={}",
                    activeTask.getId(), fileNodeId);
        }
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("ownerUserId", ownerUserId.toString());
        payload.put("fileNodeId", fileNodeId.toString());
        payload.put("title", guess.title());
        payload.put("year", guess.year());
        payload.put("seasonNumber", guess.seasonNumber());
        payload.put("episodeNumber", guess.episodeNumber());
        payload.put("force", force);
        // 用户选中的候选必须随任务落库：重投与恢复调度只读任务载荷，丢字段会退回自动匹配。
        if (preferredProvider != null) {
            payload.put("provider", preferredProvider);
        }
        if (preferredExternalId != null) {
            payload.put("externalId", preferredExternalId);
        }
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                "MEDIA_SCRAPE",
                QueueNames.MEDIA_SCRAPE_ROUTING_KEY,
                "QUEUED",
                resource.type(),
                resource.id(),
                payload
        );
        MediaScrapeRequestedEvent event = new MediaScrapeRequestedEvent(
                taskId,
                ownerUserId,
                fileNodeId,
                guess.title(),
                guess.year(),
                guess.seasonNumber(),
                guess.episodeNumber(),
                force,
                preferredProvider,
                preferredExternalId
        );
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.MEDIA_SCRAPE_ROUTING_KEY,
                event
        );
        return new ScrapeTaskDto(taskId, TaskStatus.QUEUED.getValue(), "刮削任务已进入队列");
    }

    private String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private ScrapeResource scrapeResource(MediaVideoItem item) {
        if (MediaType.EPISODE.getValue().equals(item.getMediaType()) && item.getSeriesId() != null) {
            return new ScrapeResource("MEDIA_SERIES", item.getSeriesId());
        }
        if (item.getMovieId() != null) {
            return new ScrapeResource("MEDIA_MOVIE", item.getMovieId());
        }
        return new ScrapeResource("FILE_NODE", item.getFileNodeId());
    }

    private FileNameGuess scrapeGuess(MediaVideoItem item, FileNameGuess fileGuess) {
        if (!MediaType.EPISODE.getValue().equals(item.getMediaType()) || item.getSeriesId() == null) {
            return fileGuess;
        }
        return tvSeriesRepository.findById(item.getSeriesId())
                .map(series -> {
                    Integer year = fileGuess.year();
                    if (series.getFirstAirDate() != null) {
                        year = series.getFirstAirDate().getYear();
                    }
                    return new FileNameGuess(
                            series.getTitle(),
                            year,
                            item.getSeasonNumber() == null ? 1 : item.getSeasonNumber(),
                            null
                    );
                })
                .orElse(fileGuess);
    }

    public List<ScrapeCandidateDto> candidates(UUID ownerUserId, UUID fileNodeId) {
        FileDescriptor file = resolveVideoFile(ownerUserId, fileNodeId);
        FileNameGuess fileGuess = fileNameParser.parse(file.name());
        FileNameGuess guess = videoItemRepository.findByFileNodeId(fileNodeId)
                .map(item -> scrapeGuess(item, fileGuess))
                .orElse(fileGuess);
        // 检索词只能从文件名推导，落中间态便于区分「解析错」与「提供器不通」。
        log.info("刮削候选检索: fileNodeId={}, fileName={}, title={}, year={}, season={}, episode={}",
                fileNodeId, file.name(), guess.title(), guess.year(),
                guess.seasonNumber(), guess.episodeNumber());
        // 网络 IO 在事务外执行，避免长时间占用 DB 连接
        List<ScrapeCandidateDto> candidates = new ArrayList<>();
        MetadataProviderUnavailableException unavailable = null;
        for (MetadataProvider provider : metadataProviders) {
            try {
                candidates.addAll(provider.search(guess));
            } catch (MetadataProviderUnavailableException ex) {
                // 单个提供器不可达不立刻中断：其它提供器可能仍有结果。
                unavailable = ex;
                log.warn("元数据提供器不可达: provider={}, reason={}", ex.providerName(), ex.getMessage());
            }
        }
        // 全部为空且有提供器不可达时报错：空列表会被前端渲染成「没有候选」。
        if (candidates.isEmpty() && unavailable != null) {
            throw new BusinessException(
                    ErrorCode.MEDIA_PROVIDER_UNREACHABLE,
                    "无法连接 " + unavailable.providerName() + "，请检查服务器网络与代理设置"
            );
        }
        return candidates;
    }

    private FileDescriptor resolveVideoFile(UUID ownerUserId, UUID fileNodeId) {
        FileDescriptor file = fileMetadataQueryService.findOwnedActive(ownerUserId, fileNodeId)
                .orElse(null);
        // 非拥有者交给权限矩阵：共享成员与父目录分享的子文件，shared 位都可能是 false。
        if (file == null) {
            file = fileMetadataQueryService.findActiveById(fileNodeId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
            FilePermission perm = filePermissionService.resolvePermission(fileNodeId, ownerUserId);
            if (!perm.allowView()) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "无权访问该视频文件");
            }
        }
        if (!NodeType.FILE.getValue().equals(file.nodeType())
                || !fileNameParser.isVideoFile(file.name(), file.mimeType())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "不是视频文件");
        }
        return file;
    }

    private MediaVideoItem pendingVideo(UUID ownerUserId, FileDescriptor file, FileNameGuess guess) {
        return pendingVideo(
                ownerUserId, file, guess, new LinkedHashMap<>(), new LinkedHashMap<>());
    }

    /** 组装待刮削条目，按批量缓存系列与季（缓存仅单次调用内有效）。 */
    private MediaVideoItem pendingVideo(
            UUID ownerUserId,
            FileDescriptor file,
            FileNameGuess guess,
            Map<String, MediaTvSeries> seriesMemo,
            Map<String, MediaTvSeason> seasonMemo
    ) {
        MediaVideoItem item = new MediaVideoItem();
        item.setOwnerUserId(ownerUserId);
        item.setFileNodeId(file.id());
        Integer pathSeason = extractSeasonFromPath(file.normalizedPath());
        boolean animePath = hasAnimePathHint(file.normalizedPath());
        boolean isEpisode = guess.seasonNumber() != null || guess.episodeNumber() != null || pathSeason != null;
        Integer resolvedSeason = isEpisode
                ? (guess.seasonNumber() != null ? guess.seasonNumber() : (pathSeason != null ? pathSeason : 1))
                : null;
        item.setMediaType(isEpisode ? MediaType.EPISODE.getValue() : MediaType.MOVIE.getValue());
        item.setSeasonNumber(resolvedSeason);
        item.setEpisodeNumber(guess.episodeNumber());
        item.setMetadataStatus(MetadataStatus.PENDING.getValue());
        item.setNfoStatus(NfoStatus.DISABLED.getValue());
        // 剧集在入库时即关联系列，确保去重和分组立即生效，并保留 ANIME 类型
        if (isEpisode && guess.title() != null && !guess.title().isBlank()) {
            String seriesTitle = guess.title().trim();
            MediaTvSeries series = seriesMemo.computeIfAbsent(
                    ownerUserId + "|" + seriesTitle.toLowerCase(Locale.ROOT),
                    key -> tvSeriesRepository
                            .findFirstByOwnerUserIdAndLibrarySourceIdIsNullAndTitleIgnoreCaseOrderByCreatedAtAsc(
                                    ownerUserId, seriesTitle)
                            .orElseGet(() -> {
                                MediaTvSeries s = new MediaTvSeries();
                                s.setOwnerUserId(ownerUserId);
                                s.setTitle(seriesTitle);
                                s.setSeriesType(animePath
                                        ? SeriesType.ANIME.getValue()
                                        : SeriesType.TV.getValue());
                                s.setMetadataStatus(MetadataStatus.PENDING.getValue());
                                return tvSeriesRepository.save(s);
                            }));
            item.setSeriesId(series.getId());
            if (resolvedSeason != null) {
                MediaTvSeason season = seasonMemo.computeIfAbsent(
                        ownerUserId + "|" + series.getId() + "|" + resolvedSeason,
                        key -> tvSeasonRepository
                                .findByOwnerUserIdAndSeriesIdAndSeasonNumber(
                                        ownerUserId, series.getId(), resolvedSeason)
                                .orElseGet(() -> {
                                    MediaTvSeason ts = new MediaTvSeason();
                                    ts.setOwnerUserId(ownerUserId);
                                    ts.setSeriesId(series.getId());
                                    ts.setSeasonNumber(resolvedSeason);
                                    ts.setTitle(resolvedSeason == 0 ? "特别篇" : "第 " + resolvedSeason + " 季");
                                    ts.setEpisodeCount(0);
                                    return tvSeasonRepository.save(ts);
                                }));
                item.setSeasonId(season.getId());
            }
        }
        return item;
    }

    private boolean hasAnimePathHint(String normalizedPath) {
        if (normalizedPath == null || normalizedPath.isBlank()) {
            return false;
        }
        String[] segments = normalizedPath.replace('\\', '/').split("/");
        for (int i = 0; i < segments.length - 1; i++) {
            String normalized = segments[i].trim()
                    .toLowerCase(Locale.ROOT)
                    .replace('_', ' ')
                    .replace('-', ' ')
                    .replaceAll("\\s+", " ");
            if (ANIME_PATH_HINTS.contains(normalized)) {
                return true;
            }
        }
        return false;
    }

    private Integer extractSeasonFromPath(String normalizedPath) {
        if (normalizedPath == null || normalizedPath.isBlank()) {
            return null;
        }
        String[] segments = normalizedPath.replace('\\', '/').split("/");
        for (int i = segments.length - 2; i >= 0; i--) {
            String segment = segments[i].trim();
            if ("specials".equalsIgnoreCase(segment)) {
                return 0;
            }
            Matcher matcher = PATH_SEASON_DIR.matcher(segment);
            if (matcher.matches()) {
                if (matcher.group(1) != null) {
                    return Integer.parseInt(matcher.group(1));
                }
                return parseChineseSeasonNumber(matcher.group(2));
            }
        }
        return null;
    }

    private int parseChineseSeasonNumber(String value) {
        if (value == null || value.isBlank()) {
            return 1;
        }
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException ignored) {
            return switch (value) {
                case "一" -> 1;
                case "二" -> 2;
                case "三" -> 3;
                case "四" -> 4;
                case "五" -> 5;
                case "六" -> 6;
                case "七" -> 7;
                case "八" -> 8;
                case "九" -> 9;
                case "十" -> 10;
                case "十一" -> 11;
                case "十二" -> 12;
                default -> 1;
            };
        }
    }

    private record ScrapeResource(String type, UUID id) {
    }
}
