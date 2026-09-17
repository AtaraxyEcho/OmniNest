package com.omninest.modules.music.service;

import com.alibaba.fastjson2.JSON;
import com.omninest.modules.media.domain.AssetType;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.service.DerivedAssetRequest;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.music.domain.MusicFavorite;
import com.omninest.modules.music.domain.MusicScanJob;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicArtist;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.event.MusicScrapeEvent;
import com.omninest.modules.music.dto.MusicDtos.MusicScanJobDto;
import com.omninest.modules.music.dto.MusicDtos.MusicScrapeApplyRequest;
import com.omninest.modules.music.dto.MusicDtos.MusicScrapeCandidateDto;
import com.omninest.modules.music.dto.MusicDtos.MusicTrackDto;
import com.omninest.modules.music.repository.MusicFavoriteRepository;
import com.omninest.modules.music.repository.MusicScanJobRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 音乐元数据刮削服务，负责候选查询、手动应用和批量异步刮削。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicScrapeService {
    private static final int AUTO_APPLY_THRESHOLD = 50;
    private static final int SCRAPE_BATCH_SIZE = 200;
    private static final String TASK_TYPE = "MUSIC_SCRAPE";

    private final MusicTrackRepository trackRepository;
    private final MusicFavoriteRepository favoriteRepository;
    private final MusicScanJobRepository scanJobRepository;
    private final MusicLibraryService musicLibraryService;
    private final NotificationPublisher notificationService;
    private final MusicCatalogService catalogService;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final List<MusicMetadataProvider> metadataProviders;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 查询单个曲目的元数据候选。
     *
     * @param ownerUserId 所属用户 ID
     * @param trackId 曲目 ID
     * @return 刮削候选列表
     */
    @Transactional(readOnly = true)
    public List<MusicScrapeCandidateDto> candidates(UUID ownerUserId, UUID trackId) {
        log.info("查询刮削候选: trackId={}", trackId);
        MusicTrack track = musicLibraryService.requireTrack(ownerUserId, trackId);
        return searchCandidates(track);
    }

    /**
     * 手动应用指定元数据候选。
     *
     * @param ownerUserId 所属用户 ID
     * @param trackId 曲目 ID
     * @param request 候选应用请求
     * @return 更新后的曲目 DTO
     */
    @Transactional(rollbackFor = Exception.class)
    public MusicTrackDto applyCandidate(UUID ownerUserId, UUID trackId, MusicScrapeApplyRequest request) {
        log.info("手动应用刮削结果: trackId={}, provider={}", trackId, request.provider());
        MusicTrack track = musicLibraryService.requireTrack(ownerUserId, trackId);
        UUID previousArtistId = track.getArtistId();
        UUID previousAlbumId = track.getAlbumId();

        Map<String, Object> externalIds = candidateExternalIds(request);
        Map<String, Object> providerMetadata = candidateProviderMetadata(request);
        String musicBrainzArtistId = text(externalIds.get("musicbrainzArtistId"));
        String musicBrainzReleaseId = text(externalIds.get("musicbrainzReleaseId"));
        String musicBrainzReleaseGroupId = text(externalIds.get("musicbrainzReleaseGroupId"));

        var artist = catalogService.resolveArtist(
                ownerUserId,
                request.artistName(),
                musicBrainzArtistId,
                providerMetadata
        );
        var album = catalogService.resolveAlbum(
                ownerUserId,
                request.albumTitle(),
                request.artistName(),
                request.releaseDate(),
                musicBrainzReleaseId,
                musicBrainzReleaseGroupId,
                providerMetadata
        );

        track.setTitle(request.title().trim());
        track.setArtistName(request.artistName().trim());
        track.setAlbumTitle(request.albumTitle().trim());
        track.setReleaseDate(request.releaseDate());
        track.setTrackNumber(request.trackNumber());
        track.setDiscNumber(request.discNumber());
        if (request.durationSeconds() != null && request.durationSeconds() > 0) {
            track.setDurationSeconds(request.durationSeconds());
        }
        if (request.genre() != null && !request.genre().isBlank()) {
            track.setGenre(request.genre().trim());
        }
        track.setArtistId(artist.getId());
        track.setAlbumId(album.getId());
        mergeExternalId(track.getExternalIds(), "musicbrainzRecordingId", request.externalId());
        mergeExternalId(track.getExternalIds(), "musicbrainzReleaseId", musicBrainzReleaseId);
        mergeExternalId(track.getExternalIds(), "musicbrainzReleaseGroupId", musicBrainzReleaseGroupId);
        mergeExternalId(track.getExternalIds(), "musicbrainzArtistId", musicBrainzArtistId);
        track.getProviderMetadata().put("musicbrainz", providerMetadata);
        if (request.coverUrl() != null && !request.coverUrl().isBlank()) {
            track.getProviderMetadata().put("coverUrl", request.coverUrl().trim());
        }
        if (request.score() != null) {
            track.getProviderMetadata().put("musicbrainzScore", request.score());
        }
        track.setMetadataStatus(MetadataStatus.MATCHED.getValue());
        trackRepository.save(track);

        // 下载封面到 MinIO 并设置 coverFileId
        downloadCover(ownerUserId, track, request.coverUrl());

        catalogService.refreshStatistics(ownerUserId, previousArtistId, previousAlbumId, track);
        return musicLibraryService.toTrackDto(track, isFavorite(ownerUserId, trackId));
    }

    /**
     * 创建音乐库批量刮削任务并发布到任务队列。
     *
     * @param ownerUserId 所属用户 ID
     * @param force 是否强制覆盖已匹配条目
     * @return 刮削任务 DTO
     */
    @Transactional(rollbackFor = Exception.class)
    public MusicScanJobDto scrapeLibrary(UUID ownerUserId, boolean force) {
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(taskId, ownerUserId, TASK_TYPE, QueueNames.MUSIC_SCRAPE_ROUTING_KEY, Map.of(
                "jobId", taskId.toString(),
                "ownerUserId", ownerUserId.toString(),
                "force", force
        ));
        MusicScanJob job = new MusicScanJob();
        job.setId(taskId);
        job.setTaskId(taskId);
        job.setOwnerUserId(ownerUserId);
        job.setStatus(TaskStatus.QUEUED.getValue());
        job.setMessage("MusicBrainz 刮削任务已排队");
        job.setDetails(scrapeDetails(force, 0, 0, 0, 0, 0));
        scanJobRepository.save(job);

        MusicScrapeEvent event = new MusicScrapeEvent(taskId, ownerUserId, force);
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.MUSIC_SCRAPE_ROUTING_KEY,
                event
        );
        return toDto(job);
    }

    /**
     * 执行音乐库批量刮削任务，由 Worker 消费者调用。
     *
     * @param jobId 任务 ID
     * @param ownerUserId 所属用户 ID
     * @param force 是否强制覆盖已匹配条目
     */
    // 长任务由任务记录和逐项保存维护状态，不使用跨整库扫描的长事务。
    public void executeScrapeLibrary(UUID jobId, UUID ownerUserId, boolean force) {
        MusicScanJob job = scanJobRepository.findById(jobId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "音乐刮削任务不存在"));
        if (!ownerUserId.equals(job.getOwnerUserId())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权执行音乐刮削任务");
        }
        UUID taskId = systemTaskId(job);
        if (!taskRecordService.claimForExecution(taskId, "SCRAPING")) {
            return;
        }
        long totalTracks = trackRepository.countVisibleByOwnerUserId(ownerUserId);
        log.info("开始批量刮削: jobId={}, userId={}, trackCount={}, force={}", jobId, ownerUserId, totalTracks, force);
        job.setStatus(TaskStatus.RUNNING.getValue());
        job.setMessage("MusicBrainz 刮削中");
        job.setDetails(scrapeDetails(force, 0, 0, 0, 0, 0));
        scanJobRepository.save(job);

        int processed = 0;
        int matched = 0;
        int skipped = 0;
        int unmatched = 0;
        int failed = 0;
        int visited = 0;

        try {
            Set<UUID> favoriteTrackIds = favoriteRepository.findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId)
                    .stream()
                    .map(MusicFavorite::getTrackId)
                    .collect(Collectors.toSet());

            // N+1 优化：artist/album 缓存加批量统计刷新。
            Map<String, MusicArtist> artistCache = new LinkedHashMap<>();
            Map<String, MusicAlbum> albumCache = new LinkedHashMap<>();
            Set<UUID> affectedArtistIds = new HashSet<>();
            Set<UUID> affectedAlbumIds = new HashSet<>();

            UUID cursor = new UUID(0L, 0L);
            while (true) {
                List<MusicTrack> batch = trackRepository.findScrapePageAfter(
                        ownerUserId, cursor, PageRequest.of(0, SCRAPE_BATCH_SIZE));
                if (batch.isEmpty()) {
                    break;
                }
                for (MusicTrack track : batch) {
                    visited++;
                    if (!force && shouldSkip(track)) {
                        log.debug("[刮削] 跳过: trackId={}, status={}",
                                track.getId(), track.getMetadataStatus());
                        skipped++;
                        updateScrapeProgress(job, totalTracks, visited, force, processed, matched, skipped, unmatched, failed);
                        continue;
                    }
                    processed++;
                    try {
                        List<MusicScrapeCandidateDto> candidates = searchCandidates(track);
                        MusicScrapeCandidateDto best = candidates.isEmpty() ? null : candidates.get(0);
                        if (best == null || (best.score() != null && best.score() < AUTO_APPLY_THRESHOLD)) {
                            Integer bestScore = best == null ? null : best.score();
                            log.info("[刮削] 未命中: trackId={}, 候选数={}, 最佳score={} (阈值={})",
                                    track.getId(), candidates.size(), bestScore, AUTO_APPLY_THRESHOLD);
                            unmatched++;
                            updateScrapeProgress(job, totalTracks, visited, force, processed, matched, skipped, unmatched, failed);
                            continue;
                        }
                        log.info("[刮削] 命中: trackId={}, score={}", track.getId(), best.score());
                        applyCandidateBatchCached(ownerUserId, track, best,
                                favoriteTrackIds.contains(track.getId()),
                                artistCache, albumCache,
                                affectedArtistIds, affectedAlbumIds);
                        matched++;
                    } catch (RuntimeException ex) {
                        log.warn("刮削失败: trackId={}, errorType={}",
                                track.getId(), ex.getClass().getSimpleName());
                        failed++;
                    }
                    updateScrapeProgress(job, totalTracks, visited, force, processed, matched, skipped, unmatched, failed);
                }
                cursor = batch.getLast().getId();
                if (batch.size() < SCRAPE_BATCH_SIZE) {
                    break;
                }
            }

            // 批量刷新统计，每个 artist/album 只刷新一次。
            log.info("批量刷新统计: artists={}, albums={}", affectedArtistIds.size(), affectedAlbumIds.size());
            catalogService.refreshStatisticsBatch(ownerUserId, affectedArtistIds, affectedAlbumIds);
            job.setStatus(TaskStatus.COMPLETED.getValue());
            job.setScannedFiles(processed);
            job.setMessage("MusicBrainz 刮削完成，已命中 " + matched + " 个条目");
            job.setDetails(scrapeDetails(force, processed, matched, skipped, unmatched, failed));
            scanJobRepository.save(job);
            taskRecordService.markCompleted(systemTaskId(job), new LinkedHashMap<>(Map.of(
                    "processed", processed,
                    "matched", matched,
                    "skipped", skipped,
                    "unmatched", unmatched,
                    "failed", failed
            )));
            log.info("批量刮削完成: jobId={}, matched={}, skipped={}, unmatched={}, failed={}",
                    job.getId(), matched, skipped, unmatched, failed);
            notificationService.notifyOrLog(ownerUserId, "TASK_COMPLETED",
                    "音乐刮削完成", "已命中 " + matched + " 个条目",
                    Map.of("jobId", job.getId().toString(), "matched", matched));
        } catch (RuntimeException ex) {
            log.error("音乐刮削任务失败: jobId={}", jobId, ex);
            job.setStatus(TaskStatus.FAILED.getValue());
            job.setMessage("音乐刮削失败: " + ex.getMessage());
            job.setDetails(scrapeDetails(force, processed, matched, skipped, unmatched, failed));
            scanJobRepository.save(job);
            notificationService.notifyOrLog(ownerUserId, "TASK_FAILED",
                    "音乐刮削失败", "刮削失败: " + ex.getMessage(),
                    Map.of("jobId", job.getId().toString()));
            throw ex;
        }
    }

    private void updateScrapeProgress(
            MusicScanJob job,
            long totalTracks,
            int visited,
            boolean force,
            int processed,
            int matched,
            int skipped,
            int unmatched,
            int failed
    ) {
        job.setScannedFiles(processed);
        job.setDetails(scrapeDetails(force, processed, matched, skipped, unmatched, failed));
        if (totalTracks > 0 && (visited == totalTracks || visited % 20 == 0)) {
            int progress = 10 + (int) Math.floor((visited * 80.0) / totalTracks);
            taskRecordService.updateExecution(systemTaskId(job), "SCRAPING", progress);
            scanJobRepository.save(job);
        }
    }

    private UUID systemTaskId(MusicScanJob job) {
        return job.getTaskId() == null ? job.getId() : job.getTaskId();
    }

    private String scrapeDetails(boolean force, int processed, int matched, int skipped, int unmatched, int failed) {
        return JSON.toJSONString(new LinkedHashMap<>(Map.of(
                "force", force,
                "processed", processed,
                "matched", matched,
                "skipped", skipped,
                "unmatched", unmatched,
                "failed", failed
        )));
    }

    private List<MusicScrapeCandidateDto> searchCandidates(MusicTrack track) {
        if (metadataProviders.isEmpty()) {
            log.debug("无元数据提供者注册，跳过: trackId={}", track.getId());
            return List.of();
        }
        List<MusicScrapeCandidateDto> candidates = new ArrayList<>();
        for (MusicMetadataProvider provider : metadataProviders) {
            List<MusicScrapeCandidateDto> providerCandidates = provider.search(track);
            log.info("提供者返回候选: provider={}, count={}, trackId={}",
                    provider.providerName(), providerCandidates.size(), track.getId());
            candidates.addAll(providerCandidates);
        }
        candidates.sort((left, right) -> Integer.compare(
                right.score() == null ? 0 : right.score(),
                left.score() == null ? 0 : left.score()
        ));
        return candidates;
    }

    private boolean shouldSkip(MusicTrack track) {
        if (MetadataStatus.MANUAL.getValue().equals(track.getMetadataStatus())) {
            return true;
        }
        Object recordingId = track.getExternalIds() == null ? null : track.getExternalIds().get("musicbrainzRecordingId");
        return recordingId != null && !recordingId.toString().isBlank();
    }

    private MusicScanJobDto toDto(MusicScanJob job) {
        return new MusicScanJobDto(
                job.getId(),
                job.getStatus(),
                scanProgress(job),
                job.getScannedFiles(),
                job.getMessage(),
                job.getDetails(),
                job.getCreatedAt(),
                job.getUpdatedAt()
        );
    }

    private int scanProgress(MusicScanJob job) {
        return switch (job.getStatus()) {
            case "COMPLETED" -> 100;
            case "FAILED" -> 100;
            case "RUNNING" -> 50;
            default -> 0;
        };
    }

    private boolean isFavorite(UUID ownerUserId, UUID trackId) {
        return favoriteRepository.findByOwnerUserIdAndTrackId(ownerUserId, trackId).isPresent();
    }

    private void applyCandidateBatch(UUID ownerUserId, MusicTrack track, MusicScrapeCandidateDto candidate, boolean favorite) {
        UUID previousArtistId = track.getArtistId();
        UUID previousAlbumId = track.getAlbumId();

        Map<String, Object> externalIds = candidate.externalIds() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(candidate.externalIds());
        Map<String, Object> providerMetadata = candidate.providerMetadata() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(candidate.providerMetadata());
        String musicBrainzArtistId = text(externalIds.get("musicbrainzArtistId"));
        String musicBrainzReleaseId = text(externalIds.get("musicbrainzReleaseId"));
        String musicBrainzReleaseGroupId = text(externalIds.get("musicbrainzReleaseGroupId"));

        var artist = catalogService.resolveArtist(ownerUserId, candidate.artistName(), musicBrainzArtistId, providerMetadata);
        var album = catalogService.resolveAlbum(ownerUserId, candidate.albumTitle(), candidate.artistName(),
                candidate.releaseDate(), musicBrainzReleaseId, musicBrainzReleaseGroupId, providerMetadata);

        track.setTitle(candidate.title().trim());
        track.setArtistName(candidate.artistName().trim());
        track.setAlbumTitle(candidate.albumTitle().trim());
        track.setReleaseDate(candidate.releaseDate());
        track.setTrackNumber(candidate.trackNumber());
        track.setDiscNumber(candidate.discNumber());
        if (candidate.durationSeconds() != null && candidate.durationSeconds() > 0) {
            track.setDurationSeconds(candidate.durationSeconds());
        }
        if (candidate.genre() != null && !candidate.genre().isBlank()) {
            track.setGenre(candidate.genre().trim());
        }
        track.setArtistId(artist.getId());
        track.setAlbumId(album.getId());
        mergeExternalId(track.getExternalIds(), "musicbrainzRecordingId", candidate.externalId());
        mergeExternalId(track.getExternalIds(), "musicbrainzReleaseId", musicBrainzReleaseId);
        mergeExternalId(track.getExternalIds(), "musicbrainzReleaseGroupId", musicBrainzReleaseGroupId);
        mergeExternalId(track.getExternalIds(), "musicbrainzArtistId", musicBrainzArtistId);
        track.getProviderMetadata().put("musicbrainz", providerMetadata);
        if (candidate.coverUrl() != null && !candidate.coverUrl().isBlank()) {
            track.getProviderMetadata().put("coverUrl", candidate.coverUrl().trim());
        }
        if (candidate.score() != null) {
            track.getProviderMetadata().put("musicbrainzScore", candidate.score());
        }
        track.setMetadataStatus(MetadataStatus.MATCHED.getValue());
        trackRepository.save(track);
        log.info("[刮削应用] trackId={}, score={}, hasCover={}, mbRecordingIdPresent={}",
                track.getId(), candidate.score(), candidate.coverUrl() != null && !candidate.coverUrl().isBlank(),
                externalIds.get("musicbrainzRecordingId") != null);

        // 下载封面到 MinIO 并设置 coverFileId
        downloadCover(ownerUserId, track, candidate.coverUrl());

        catalogService.refreshStatistics(ownerUserId, previousArtistId, previousAlbumId, track);
    }

    /**
     * 带缓存的批量刮削应用。使用 artist/album 缓存减少 DB 查询，
     * 收集受影响的 ID 用于后续批量刷新统计。
     */
    private void applyCandidateBatchCached(
            UUID ownerUserId, MusicTrack track, MusicScrapeCandidateDto candidate, boolean favorite,
            Map<String, MusicArtist> artistCache,
            Map<String, MusicAlbum> albumCache,
            Set<UUID> affectedArtistIds, Set<UUID> affectedAlbumIds
    ) {
        UUID previousArtistId = track.getArtistId();
        UUID previousAlbumId = track.getAlbumId();

        Map<String, Object> externalIds = candidate.externalIds() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(candidate.externalIds());
        Map<String, Object> providerMetadata = candidate.providerMetadata() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(candidate.providerMetadata());
        String musicBrainzArtistId = text(externalIds.get("musicbrainzArtistId"));
        String musicBrainzReleaseId = text(externalIds.get("musicbrainzReleaseId"));
        String musicBrainzReleaseGroupId = text(externalIds.get("musicbrainzReleaseGroupId"));

        var artist = catalogService.resolveArtistCached(ownerUserId, candidate.artistName(),
                musicBrainzArtistId, providerMetadata, artistCache);
        var album = catalogService.resolveAlbumCached(ownerUserId, candidate.albumTitle(), candidate.artistName(),
                candidate.releaseDate(), musicBrainzReleaseId, musicBrainzReleaseGroupId, providerMetadata, albumCache);

        track.setTitle(candidate.title().trim());
        track.setArtistName(candidate.artistName().trim());
        track.setAlbumTitle(candidate.albumTitle().trim());
        track.setReleaseDate(candidate.releaseDate());
        track.setTrackNumber(candidate.trackNumber());
        track.setDiscNumber(candidate.discNumber());
        if (candidate.durationSeconds() != null && candidate.durationSeconds() > 0) {
            track.setDurationSeconds(candidate.durationSeconds());
        }
        if (candidate.genre() != null && !candidate.genre().isBlank()) {
            track.setGenre(candidate.genre().trim());
        }
        track.setArtistId(artist.getId());
        track.setAlbumId(album.getId());
        mergeExternalId(track.getExternalIds(), "musicbrainzRecordingId", candidate.externalId());
        mergeExternalId(track.getExternalIds(), "musicbrainzReleaseId", musicBrainzReleaseId);
        mergeExternalId(track.getExternalIds(), "musicbrainzReleaseGroupId", musicBrainzReleaseGroupId);
        mergeExternalId(track.getExternalIds(), "musicbrainzArtistId", musicBrainzArtistId);
        track.getProviderMetadata().put("musicbrainz", providerMetadata);
        if (candidate.coverUrl() != null && !candidate.coverUrl().isBlank()) {
            track.getProviderMetadata().put("coverUrl", candidate.coverUrl().trim());
        }
        if (candidate.score() != null) {
            track.getProviderMetadata().put("musicbrainzScore", candidate.score());
        }
        track.setMetadataStatus(MetadataStatus.MATCHED.getValue());
        trackRepository.save(track);
        log.info("[刮削应用] trackId={}, score={}, hasCover={}, mbRecordingIdPresent={}",
                track.getId(), candidate.score(), candidate.coverUrl() != null && !candidate.coverUrl().isBlank(),
                externalIds.get("musicbrainzRecordingId") != null);

        // 下载封面到 MinIO 并设置 coverFileId
        downloadCover(ownerUserId, track, candidate.coverUrl());

        // 收集受影响的 artist/album ID（不逐个刷新，最后批量刷新）
        if (previousArtistId != null) affectedArtistIds.add(previousArtistId);
        affectedArtistIds.add(artist.getId());
        if (previousAlbumId != null) affectedAlbumIds.add(previousAlbumId);
        affectedAlbumIds.add(album.getId());
    }

    private void mergeExternalId(Map<String, Object> externalIds, String key, String value) {
        if (externalIds == null || value == null || value.isBlank()) {
            return;
        }
        externalIds.put(key, value.trim());
    }

    private Map<String, Object> candidateExternalIds(MusicScrapeApplyRequest request) {
        Map<String, Object> values = request.externalIds() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(request.externalIds());
        mergeExternalId(values, "musicbrainzRecordingId", request.externalId());
        return values;
    }

    private Map<String, Object> candidateProviderMetadata(MusicScrapeApplyRequest request) {
        Map<String, Object> values = request.providerMetadata() == null ? new LinkedHashMap<>() : new LinkedHashMap<>(request.providerMetadata());
        values.putIfAbsent("provider", request.provider());
        values.putIfAbsent("coverUrl", request.coverUrl());
        values.putIfAbsent("score", request.score());
        return values;
    }

    private String text(Object value) {
        return value == null ? null : value.toString();
    }

    /**
     * 下载封面图片到 MinIO 并设置 track.coverFileId。
     * 跳过条件：coverUrl 为空、track 已有 coverFileId、或下载失败。
     */
    private void downloadCover(UUID ownerUserId, MusicTrack track, String coverUrl) {
        if (coverUrl == null || coverUrl.isBlank()) {
            return;
        }
        if (track.getCoverFileId() != null) {
            log.debug("封面已存在，跳过下载: trackId={}, coverFileId={}", track.getId(), track.getCoverFileId());
            return;
        }
        try {
            String fileName = "cover-" + track.getId() + ".jpg";
            UUID coverFileId = derivedAssetStorageService.storeRemote(new DerivedAssetRequest(
                    ownerUserId,
                    coverUrl,
                    ResourceType.MUSIC_TRACK.getValue(),
                    track.getId(),
                    AssetType.POSTER.getValue(),
                    fileName,
                    "image/jpeg",
                    SpaceType.PERSONAL
            ));
            track.setCoverFileId(coverFileId);
            trackRepository.save(track);
            log.info("[封面下载] trackId={}, coverFileId={}", track.getId(), coverFileId);
        } catch (RuntimeException ex) {
            log.warn("[封面下载失败] trackId={}, errorType={}",
                    track.getId(), ex.getClass().getSimpleName());
        }
    }
}
