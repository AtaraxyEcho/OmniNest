package com.omninest.modules.video.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.video.domain.NfoStatus;
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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 影视元数据刮削任务服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MovieScrapeService {
    private static final List<String> ACTIVE_TASK_STATUSES = List.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RUNNING.getValue(),
            TaskStatus.RETRY_WAIT.getValue()
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
        return videoItemRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, fileNodeId)
                .orElseGet(() -> {
                    MediaVideoItem created = videoItemRepository.save(pendingVideo(ownerUserId, file, guess));
                    // 新登记条目改变影视库统计，需失效 dashboard 缓存。
                    readThroughCache.invalidate("omninest:dashboard:video:" + ownerUserId);
                    return created;
                });
    }

    @Transactional(rollbackFor = Exception.class)
    public ScrapeTaskDto createScrapeTask(UUID ownerUserId, UUID fileNodeId, boolean force) {
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
        if (activeTask != null) {
            return new ScrapeTaskDto(
                    activeTask.getId(),
                    activeTask.getStatus(),
                    "该媒体实体已有刮削任务正在执行"
            );
        }
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("ownerUserId", ownerUserId.toString());
        payload.put("fileNodeId", fileNodeId.toString());
        payload.put("title", guess.title());
        payload.put("year", guess.year());
        payload.put("seasonNumber", guess.seasonNumber());
        payload.put("episodeNumber", guess.episodeNumber());
        payload.put("force", force);
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
                force
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
        FileNameGuess guess = videoItemRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, fileNodeId)
                .map(item -> scrapeGuess(item, fileGuess))
                .orElse(fileGuess);
        // 网络 IO 在事务外执行，避免长时间占用 DB 连接
        return metadataProviders.stream()
                .flatMap(provider -> provider.search(guess).stream())
                .toList();
    }

    private FileDescriptor resolveVideoFile(UUID ownerUserId, UUID fileNodeId) {
        FileDescriptor file = fileMetadataQueryService.findOwnedActive(ownerUserId, fileNodeId)
                .orElse(null);
        // 如果不是拥有者的文件，检查是否为共享文件
        if (file == null) {
            file = fileMetadataQueryService.findActiveById(fileNodeId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
            if (!file.shared()) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "文件未共享");
            }
            FilePermission perm = filePermissionService.resolvePermission(fileNodeId, ownerUserId);
            if (!perm.allowView()) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "无查看权限");
            }
        }
        if (!NodeType.FILE.getValue().equals(file.nodeType())
                || !fileNameParser.isVideoFile(file.name(), file.mimeType())) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "不是视频文件");
        }
        return file;
    }

    private MediaVideoItem pendingVideo(UUID ownerUserId, FileDescriptor file, FileNameGuess guess) {
        MediaVideoItem item = new MediaVideoItem();
        item.setOwnerUserId(ownerUserId);
        item.setFileNodeId(file.id());
        boolean isEpisode = guess.seasonNumber() != null;
        item.setMediaType(isEpisode ? MediaType.EPISODE.getValue() : MediaType.MOVIE.getValue());
        item.setSeasonNumber(guess.seasonNumber());
        item.setEpisodeNumber(guess.episodeNumber());
        item.setMetadataStatus(MetadataStatus.PENDING.getValue());
        item.setNfoStatus(NfoStatus.DISABLED.getValue());
        // 剧集在入库时即关联系列，确保去重和分组立即生效
        if (isEpisode && guess.title() != null && !guess.title().isBlank()) {
            String seriesTitle = guess.title().trim();
            MediaTvSeries series = tvSeriesRepository.findByOwnerUserIdAndTitle(ownerUserId, seriesTitle)
                    .orElseGet(() -> {
                        MediaTvSeries s = new MediaTvSeries();
                        s.setOwnerUserId(ownerUserId);
                        s.setTitle(seriesTitle);
                        s.setMetadataStatus(MetadataStatus.PENDING.getValue());
                        return tvSeriesRepository.save(s);
                    });
            item.setSeriesId(series.getId());
            if (guess.seasonNumber() != null) {
                MediaTvSeason season = tvSeasonRepository
                        .findByOwnerUserIdAndSeriesIdAndSeasonNumber(ownerUserId, series.getId(), guess.seasonNumber())
                        .orElseGet(() -> {
                            MediaTvSeason ts = new MediaTvSeason();
                            ts.setOwnerUserId(ownerUserId);
                            ts.setSeriesId(series.getId());
                            ts.setSeasonNumber(guess.seasonNumber());
                            ts.setTitle("第 " + guess.seasonNumber() + " 季");
                            ts.setEpisodeCount(0);
                            return tvSeasonRepository.save(ts);
                        });
                item.setSeasonId(season.getId());
            }
        }
        return item;
    }

    private record ScrapeResource(String type, UUID id) {
    }
}
