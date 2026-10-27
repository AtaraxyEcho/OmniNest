package com.omninest.modules.music.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.security.Permissions;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FilePermissionService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicArtist;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import com.omninest.modules.music.domain.MusicScanJob;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.event.MusicScanEvent;
import com.omninest.modules.music.dto.MusicDtos.MusicScanJobDto;
import com.omninest.modules.music.dto.MusicDtos.MusicTrackDto;
import com.omninest.modules.music.dto.MusicDtos.UpdateMusicTrackRequest;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicArtistRepository;
import com.omninest.modules.music.repository.MusicScanJobRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import com.omninest.modules.user.domain.UserStatus;
import com.omninest.modules.user.dto.UserDirectoryDtos.UserAuthorizationProfile;
import com.omninest.modules.reader.service.TxtContentDecoder;
import com.omninest.modules.user.service.UserDirectoryQueryService;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.UUID;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.Semaphore;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 音乐扫描、导入与曲目管理服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicAdminService {
    /** 音乐扫描预取 I/O 并发；默认 4。 */
    @Value("${omninest.concurrency.music-prefetch:4}")
    int scanPrefetchConcurrency = 4;
    /** 每批预取的音频数量；默认 16。 */
    @Value("${omninest.concurrency.music-prefetch-batch:16}")
    int scanPrefetchBatchSize = 16;

    private static final List<String> ACTIVE_TASK_STATUSES = List.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RUNNING.getValue(),
            TaskStatus.RETRY_WAIT.getValue()
    );

    /** 派生封面存储的资源类型与资产类型，与手动上传共用同一前缀。 */
    private static final String COVER_RESOURCE_TYPE = "MUSIC_COVER";
    private static final String COVER_ASSET_TYPE = "COVER";

    /** 超过该字节数的内嵌封面维持内联，避免为罕见大图在扫描流程写对象存储。 */


    private final MediaProcessingLimitsProperties processingLimits;
    private final MusicScanJobRepository scanJobRepository;
    private final MusicTrackRepository trackRepository;
    private final MusicAlbumRepository albumRepository;
    private final MusicArtistRepository artistRepository;
    private final MusicCatalogService catalogService;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final FileQueryService fileQueryService;
    private final MusicMetadataExtractor metadataExtractor;
    private final MusicLibraryService musicLibraryService;
    private final FilePermissionService filePermissionService;
    private final NotificationPublisher notificationService;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final MediaSyncEventService syncEventService;
    private final ReadThroughCache readThroughCache;
    private final PlatformTransactionManager transactionManager;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final MusicCoverRetentionService coverRetentionService;
    private final TxtContentDecoder txtContentDecoder;
    private final UserDirectoryQueryService userDirectoryQueryService;
    private TransactionTemplate transactionTemplate;

    /**
     * 初始化逐文件独立事务模板。
     */
    @PostConstruct
    void initTransactionTemplate() {
        this.transactionTemplate = new TransactionTemplate(transactionManager);
        this.transactionTemplate.setPropagationBehavior(
                TransactionDefinition.PROPAGATION_REQUIRES_NEW
        );
    }

    /**
     * 创建扫描任务，发布到 RabbitMQ 异步执行。
     */
    @Transactional(rollbackFor = Exception.class)
    public MusicScanJobDto createScanJob(UUID ownerUserId) {
        log.info("创建音乐扫描任务: userId={}", ownerUserId);
        MusicScanJob existing = taskRecordService
                .findActiveTaskForOwner(ownerUserId, "MUSIC_SCAN", ACTIVE_TASK_STATUSES)
                .flatMap(task -> scanJobRepository.findByIdAndOwnerUserId(task.getId(), ownerUserId))
                .orElse(null);
        if (existing != null) {
            return toDto(existing);
        }
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(taskId, ownerUserId, "MUSIC_SCAN", QueueNames.MUSIC_SCAN_ROUTING_KEY, Map.of(
                "jobId", taskId.toString(),
                "ownerUserId", ownerUserId.toString()
        ));
        MusicScanJob job = new MusicScanJob();
        job.setId(taskId);
        job.setTaskId(taskId);
        job.setOwnerUserId(ownerUserId);
        job.setStatus(TaskStatus.QUEUED.getValue());
        job.setMessage("音乐库扫描任务已排队");
        scanJobRepository.save(job);

        MusicScanEvent event = new MusicScanEvent(job.getId(), ownerUserId);
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                job.getId(),
                QueueNames.TASK_EXCHANGE,
                QueueNames.MUSIC_SCAN_ROUTING_KEY,
                event
        );

        return toDto(job);
    }

    /**
     * 执行扫描任务（由 Worker 消费者调用）。
     * 逐文件独立事务，避免单个长事务独占 DB 连接数小时。
     */
    public void executeScanJob(UUID jobId, UUID ownerUserId) {
        MusicScanJob job = scanJobRepository.findById(jobId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "音乐扫描任务不存在"));
        if (!taskRecordService.claimForExecution(jobId, "SCANNING")) {
            return;
        }

        job.setStatus(TaskStatus.RUNNING.getValue());
        job.setMessage("音乐库扫描中");
        // executeScanJob 无外层事务，job 为脱管实体：merge 返回的新受管实例
        // 才携带推进后的 version；不接住返回值则后续收尾 save 仍带旧版本，
        // 必然触发 StaleObjectStateException（D-009）。
        job = scanJobRepository.save(job);

        int imported = 0;
        try {
            List<FileDescriptor> ownedNodes = fileMetadataQueryService.listOwnedActive(ownerUserId);
            List<FileDescriptor> allSharedNodes = fileMetadataQueryService.listSharedVisibleToUser(ownerUserId);
            Set<UUID> viewableSharedFileIds = filePermissionService.resolveViewableFileIds(
                    allSharedNodes.stream().map(FileDescriptor::id).toList(), ownerUserId);
            List<FileDescriptor> sharedNodes = allSharedNodes.stream()
                    .filter(node -> viewableSharedFileIds.contains(node.id()))
                    .toList();

            List<FileDescriptor> nodes = new ArrayList<>(ownedNodes);
            nodes.addAll(sharedNodes);

            Map<String, FileDescriptor> lyricFilesByBasePath = nodes.stream()
                    .filter(this::isLrcFile)
                    .collect(Collectors.toMap(
                            node -> basePathKey(node.normalizedPath()),
                            Function.identity(),
                            (left, right) -> left
                    ));

            // N+1 优化: artist/album 缓存 + 批量统计刷新
            Map<String, MusicArtist> artistCache = new LinkedHashMap<>();
            Map<String, MusicAlbum> albumCache = new LinkedHashMap<>();
            // 统计必须按实际归属人刷新：共享文件首次建索引时曲目落在文件所有者名下，
            // 记到扫描者账上会让所有者的歌手/专辑曲目数失真。
            Map<UUID, Set<UUID>> affectedArtistsByOwner = new LinkedHashMap<>();
            Map<UUID, Set<UUID>> affectedAlbumsByOwner = new LinkedHashMap<>();
            int visited = 0;
            List<FileDescriptor> audioNodes = nodes.stream().filter(this::isAudioFile).toList();
            Semaphore ioPermits = new Semaphore(Math.max(1, scanPrefetchConcurrency));
            try (ExecutorService ioExecutor = Executors.newVirtualThreadPerTaskExecutor()) {
                for (int start = 0; start < audioNodes.size(); start += Math.max(1, scanPrefetchBatchSize)) {
                    List<FileDescriptor> chunk = audioNodes.subList(
                            start,
                            Math.min(start + Math.max(1, scanPrefetchBatchSize), audioNodes.size())
                    );
                    List<Future<PrefetchedAudio>> futures = chunk.stream()
                            .map(file -> ioExecutor.submit(() -> prefetchAudio(file, lyricFilesByBasePath, ioPermits)))
                            .toList();
                    // 单线程顺序入库：artist/album 缓存与同名唯一键都不能并发写。
                    for (Future<PrefetchedAudio> future : futures) {
                        visited++;
                        try {
                            PrefetchedAudio prefetched = future.get();
                            transactionTemplate.executeWithoutResult(status ->
                                    importPrefetchedAudioCached(ownerUserId, prefetched,
                                            artistCache, albumCache,
                                            affectedArtistsByOwner, affectedAlbumsByOwner)
                            );
                            imported++;
                        } catch (InterruptedException exception) {
                            Thread.currentThread().interrupt();
                            throw new IllegalStateException("音乐扫描等待预取结果时被中断", exception);
                        } catch (ExecutionException | RuntimeException perFileError) {
                            log.warn("音乐扫描单文件失败，跳过继续: jobId={}, errorType={}",
                                    jobId, perFileError.getClass().getSimpleName());
                        }
                        if (!audioNodes.isEmpty()
                                && (visited == audioNodes.size() || visited % 20 == 0)) {
                            int progress = 10 + (int) Math.floor((visited * 80.0) / audioNodes.size());
                            taskRecordService.updateExecution(jobId, "SCANNING", progress);
                        }
                    }
                }
            }

            // 批量刷新统计：逐个归属人刷新，包含被扫入共享文件的文件所有者。
            for (Map.Entry<UUID, Set<UUID>> entry : affectedArtistsByOwner.entrySet()) {
                catalogService.refreshStatisticsBatch(
                        entry.getKey(),
                        entry.getValue(),
                        affectedAlbumsByOwner.getOrDefault(entry.getKey(), Set.of())
                );
            }
            job.setStatus(TaskStatus.COMPLETED.getValue());
            job.setScannedFiles(imported);
            job.setMessage("音乐库扫描完成，已处理 " + imported + " 个音频文件");
            taskRecordService.markCompleted(jobId, Map.of("imported", imported));
            // 扫描入库改变音乐仪表盘统计与最近列表，需失效缓存；共享曲目同时影响所有者。
            Set<UUID> affectedOwners = new LinkedHashSet<>(affectedArtistsByOwner.keySet());
            affectedOwners.add(ownerUserId);
            for (UUID affectedOwner : affectedOwners) {
                readThroughCache.invalidate("omninest:dashboard:music:" + affectedOwner);
            }
            // 同步事件记录器要求外层事务（MANDATORY 传播），而 executeScanJob
            // 本体刻意无事务（逐文件独立提交），故失效事件在独立短事务内落库；
            // 此前裸调触发 IllegalTransactionStateException 使任务在完成边缘
            // 失败并进入重试死循环（D-009）。
            final int importedCount = imported;
            transactionTemplate.executeWithoutResult(status -> {
                for (UUID affectedOwner : affectedOwners) {
                    syncEventService.invalidate(
                            affectedOwner,
                            SyncScope.MUSIC,
                            "MUSIC_LIBRARY",
                            Map.of("source", "SCAN", "imported", importedCount)
                    );
                }
            });
            log.info("音乐扫描完成: jobId={}, imported={}", jobId, imported);
            // 发送完成通知
            notificationService.notifyOrLog(ownerUserId, "TASK_COMPLETED",
                    "音乐扫描完成", "已处理 " + imported + " 个音频文件",
                    Map.of("jobId", jobId.toString()));
        } catch (Exception e) {
            log.error("音乐扫描失败: jobId={}", jobId, e);
            job.setStatus(TaskStatus.FAILED.getValue());
            job.setMessage("音乐扫描失败: " + e.getMessage());
            scanJobRepository.save(job);
            // 发送失败通知
            notificationService.notifyOrLog(ownerUserId, "TASK_FAILED",
                    "音乐扫描失败", "扫描失败: " + e.getMessage(),
                    Map.of("jobId", jobId.toString()));
            if (e instanceof RuntimeException runtimeException) {
                throw runtimeException;
            }
            throw new IllegalStateException("音乐扫描失败", e);
        }
        scanJobRepository.save(job);
    }

    @Transactional(readOnly = true)
    public MusicScanJobDto scanJob(UUID ownerUserId, UUID jobId) {
        return scanJobRepository.findByIdAndOwnerUserId(jobId, ownerUserId)
                .map(this::toDto)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "音乐库扫描任务不存在"));
    }

    /**
     * 更新曲目元数据。可选字段采用部分更新：请求未携带（null）时保留原值，
     * 避免仅编辑标题或歌词时误清已有封面、歌词与流派。
     *
     * <p>清空语义：clearCover=true 清空封面；lyricsRaw 传空字符串清空歌词原文与译文。</p>
     */
    @Transactional(rollbackFor = Exception.class)
    public MusicTrackDto updateTrack(UUID ownerUserId, UUID trackId, UpdateMusicTrackRequest request) {
        log.info("更新音乐曲目: trackId={}", trackId);
        MusicTrack track = requireWritableTrack(ownerUserId, trackId);
        // 歌手/专辑与统计必须落在曲目真实归属人名下，否则会在管理员个人曲库凭空建出重复目录。
        UUID catalogOwnerId = track.getOwnerUserId();
        UUID previousArtistId = track.getArtistId();
        UUID previousAlbumId = track.getAlbumId();
        UUID previousCoverFileId = track.getCoverFileId();

        // 同步 music_artists / music_albums 实体，重关联 FK
        String artistName = request.artistName() != null ? request.artistName().trim() : track.getArtistName();
        String albumTitle = request.albumTitle() != null ? request.albumTitle().trim() : track.getAlbumTitle();
        var artist = catalogService.resolveArtist(catalogOwnerId, artistName, null, null);
        var album = catalogService.resolveAlbum(catalogOwnerId, albumTitle, artistName, null, null, null, null);

        if (request.title() != null) {
            String title = request.title().trim();
            if (title.isEmpty()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "曲目标题不能为空");
            }
            track.setTitle(title);
        }
        track.setArtistName(artistName);
        track.setAlbumTitle(albumTitle);
        if (request.genre() != null) {
            track.setGenre(request.genre());
        }
        if (request.lyricsRaw() != null) {
            track.setLyricsRaw(request.lyricsRaw());
            if (request.lyricsRaw().isEmpty()) {
                track.setLyricsTranslation(null);
            }
        }
        applyCoverUpdate(track, request.coverFileId(), Boolean.TRUE.equals(request.clearCover()));
        track.setArtistId(artist.getId());
        track.setAlbumId(album.getId());
        track.setMetadataStatus(MetadataStatus.MANUAL.getValue());
        trackRepository.save(track);
        // 封面未变时不能回收：未携带 coverFileId 只表示“不修改”，不是替换。
        if (previousCoverFileId != null && !previousCoverFileId.equals(track.getCoverFileId())) {
            coverRetentionService.releaseUnreferenced(catalogOwnerId, previousCoverFileId);
        }
        catalogService.refreshStatistics(catalogOwnerId, previousArtistId, previousAlbumId, track);
        recordTrackUpdated(catalogOwnerId, track);
        return musicLibraryService.toTrackDto(track, false);
    }

    /**
     * 应用封面部分更新：clearCover 优先清空（含内联/外部回退地址），
     * 否则仅在携带新 coverFileId 时替换。
     */
    private void applyCoverUpdate(MusicTrack track, UUID coverFileId, boolean clearCover) {
        if (clearCover) {
            track.setCoverFileId(null);
            track.getProviderMetadata().remove("coverDataUrl");
            track.getProviderMetadata().remove("coverUrl");
            return;
        }
        if (coverFileId != null) {
            track.setCoverFileId(coverFileId);
            track.getProviderMetadata().remove("coverDataUrl");
        }
    }

    /**
     * 曲目元数据可写判据：所有者本人，或共享空间曲目且操作者具备媒体库/系统配置管理权限。
     *
     * <p>与影视模块的 requireWritableVideo 同口径；其余情况统一按 FORBIDDEN 返回，
     * 避免把“可读但不可写”误报成资源不存在。</p>
     */
    private MusicTrack requireWritableTrack(UUID operatorUserId, UUID trackId) {
        MusicTrack track = trackRepository.findById(trackId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "音乐资源不存在"));
        if (track.getOwnerUserId().equals(operatorUserId)) {
            return track;
        }
        FileDescriptor file = fileMetadataQueryService.findActiveById(track.getFileNodeId()).orElse(null);
        boolean sharedSpace = file != null && SpaceType.SHARED == file.spaceType();
        if (sharedSpace && canManageSharedCatalog(operatorUserId)) {
            return track;
        }
        throw new BusinessException(ErrorCode.FORBIDDEN, "无权修改该音乐资源");
    }

    private boolean canManageSharedCatalog(UUID operatorUserId) {
        UserAuthorizationProfile profile = userDirectoryQueryService.requireAuthorizationProfile(operatorUserId);
        if (!UserStatus.ACTIVE.getValue().equals(profile.status())) {
            return false;
        }
        return profile.permissions().contains(Permissions.MEDIA_LIBRARY_MANAGE)
                || profile.permissions().contains(Permissions.SYSTEM_CONFIG_MANAGE);
    }

    @Transactional(rollbackFor = Exception.class)
    public MusicTrackDto applyLyrics(UUID ownerUserId, UUID trackId, String lyrics, String lyricsTranslation) {
        log.info("应用歌词: trackId={}", trackId);
        MusicTrack track = requireWritableTrack(ownerUserId, trackId);
        track.setLyricsRaw(lyrics);
        track.setLyricsTranslation(lyricsTranslation);
        trackRepository.save(track);
        recordTrackUpdated(track.getOwnerUserId(), track);
        log.info(
                "歌词已应用: trackId={}, length={}, hasTranslation={}",
                trackId,
                lyrics != null ? lyrics.length() : 0,
                lyricsTranslation != null && !lyricsTranslation.isBlank()
        );
        return musicLibraryService.toTrackDto(track, false);
    }

    /**
     * 导入单个音频文件（供自动导入调用）。
     * 查找 FileNode 和同目录同名 .lrc 歌词文件，调用内部导入逻辑。
     */
    @Transactional(rollbackFor = Exception.class)
    public void importSingleAudioFile(UUID ownerUserId, UUID fileNodeId) {
        FileDescriptor file = fileMetadataQueryService.findActiveById(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "文件不存在"));
        UUID catalogOwnerId = file.ownerUserId() != null ? file.ownerUserId() : ownerUserId;
        // 查找同目录同名 .lrc 歌词文件（以文件所有者目录为准，共享文件由上传者持有）
        String baseName = titleFromFileName(file.name());
        FileDescriptor sidecarLyrics = fileMetadataQueryService
                .listOwnedActiveChildren(catalogOwnerId, file.parentId())
                .stream()
                .filter(node -> isLrcFile(node) && titleFromFileName(node.name()).equals(baseName))
                .findFirst()
                .orElse(null);
        importAudioFile(catalogOwnerId, file, sidecarLyrics);
        // 单曲导入改变音乐仪表盘统计与最近列表，需失效缓存。
        readThroughCache.invalidate("omninest:dashboard:music:" + catalogOwnerId);
        syncEventService.invalidate(
                catalogOwnerId,
                SyncScope.MUSIC,
                "MUSIC_LIBRARY",
                Map.of("source", "SINGLE_IMPORT")
        );
    }

    private void importAudioFile(UUID ownerUserId, FileDescriptor file, FileDescriptor sidecarLyrics) {
        UUID catalogOwnerId = file.ownerUserId() != null ? file.ownerUserId() : ownerUserId;
        var existingTrack = trackRepository.findByFileNodeId(file.id());
        // 单曲导入同样受所有者边界与手动精修保护，避免自动导入冲掉用户编辑。
        if (!catalogOwnerId.equals(ownerUserId) && existingTrack.isPresent()) {
            return;
        }
        if (existingTrack.isPresent()
                && MetadataStatus.MANUAL.getValue().equals(existingTrack.get().getMetadataStatus())) {
            MusicTrack manualTrack = existingTrack.get();
            manualTrack.setFileSize(file.sizeBytes());
            manualTrack.setFormat(formatFromFileName(file.name()));
            trackRepository.save(manualTrack);
            return;
        }
        MusicTrack track = existingTrack.orElseGet(() -> {
            MusicTrack created = new MusicTrack();
            created.setOwnerUserId(catalogOwnerId);
            created.setFileNodeId(file.id());
            return created;
        });
        if (!catalogOwnerId.equals(track.getOwnerUserId())) {
            track.setOwnerUserId(catalogOwnerId);
        }
        UUID previousArtistId = track.getArtistId();
        UUID previousAlbumId = track.getAlbumId();
        MusicMetadataExtractor.Metadata metadata = extractMetadata(file);
        String lyricsRaw = firstText(metadata.lyricsRaw(), readTextObject(sidecarLyrics));

        // 文件名解析兜底：当 ID3/Vorbis 标签缺失时，从文件名提取 title/artist/album
        MusicFileNameGuess fileNameGuess = parseFileName(file.name());
        String title = firstText(metadata.title(), firstText(fileNameGuess.title(), titleFromFileName(file.name())));
        String artistName = firstText(metadata.artistName(), firstText(fileNameGuess.artistName(), "Unknown Artist"));
        String albumTitle = firstText(metadata.albumTitle(), firstText(fileNameGuess.albumTitle(), "Unknown Album"));
        MusicArtist artist = artist(catalogOwnerId, artistName);
        MusicAlbum album = album(catalogOwnerId, albumTitle, artistName);
        track.setTitle(title);
        track.setArtistName(artistName);
        track.setAlbumTitle(albumTitle);
        track.setGenre(metadata.genre());
        track.setLyricsRaw(lyricsRaw);
        track.setTrackNumber(parseNullableInt(metadata.trackNumber()));
        track.setDiscNumber(parseNullableInt(metadata.discNumber()));
        track.setBitrate(metadata.bitrate());
        track.setSampleRate(metadata.sampleRate());
        applyDuration(track, metadata);
        track.setArtistId(artist.getId());
        track.setAlbumId(album.getId());
        track.setFormat(formatFromFileName(file.name()));
        track.setFileSize(file.sizeBytes());
        track.getProviderMetadata().put("title", title);
        track.getProviderMetadata().put("artistName", artistName);
        track.getProviderMetadata().put("albumTitle", albumTitle);
        track.getProviderMetadata().put("genre", metadata.genre());
        track.getProviderMetadata().put("lyricsRaw", lyricsRaw);
        if (metadata.trackNumber() != null) {
            track.getProviderMetadata().put("trackNumber", metadata.trackNumber());
        }
        if (metadata.discNumber() != null) {
            track.getProviderMetadata().put("discNumber", metadata.discNumber());
        }
        storeEmbeddedCover(catalogOwnerId, track, file, metadata.coverDataUrl());
        track.setMetadataStatus(metadata.hasAnyValue() || hasText(lyricsRaw) ? MetadataStatus.MATCHED.getValue() : MetadataStatus.PENDING.getValue());
        trackRepository.save(track);
        catalogService.refreshStatistics(catalogOwnerId, previousArtistId, previousAlbumId, track);
    }

    /**
     * 带缓存的音频文件导入。使用 artist/album 缓存减少 DB 查询，
     * 收集受影响的 ID 用于后续批量刷新统计。
     */
    private PrefetchedAudio prefetchAudio(
            FileDescriptor file,
            Map<String, FileDescriptor> lyricFilesByBasePath,
            Semaphore ioPermits
    ) throws IOException {
        FileDescriptor sidecarLyrics = lyricFilesByBasePath.get(basePathKey(file.normalizedPath()));
        ioPermits.acquireUninterruptibly();
        try {
            MusicMetadataExtractor.Metadata metadata = extractMetadata(file);
            String lyricsRaw = firstText(metadata.lyricsRaw(), readTextObject(sidecarLyrics));
            return new PrefetchedAudio(file, metadata, lyricsRaw);
        } finally {
            ioPermits.release();
        }
    }

    private record PrefetchedAudio(
            FileDescriptor file,
            MusicMetadataExtractor.Metadata metadata,
            String lyricsRaw
    ) {
    }

    private void importPrefetchedAudioCached(
            UUID ownerUserId, PrefetchedAudio prefetched,
            Map<String, MusicArtist> artistCache, Map<String, MusicAlbum> albumCache,
            Map<UUID, Set<UUID>> affectedArtistsByOwner, Map<UUID, Set<UUID>> affectedAlbumsByOwner
    ) {
        FileDescriptor file = prefetched.file();
        MusicMetadataExtractor.Metadata metadata = prefetched.metadata();
        String lyricsRaw = prefetched.lyricsRaw();
        // 曲目行归属固定为文件所有者：共享空间文件被成员扫描时也由上传者持有，
        // 否则"谁先扫谁拥有"会让非所有者获得元数据写权限，且与唯一约束冲突。
        UUID catalogOwnerId = file.ownerUserId() != null ? file.ownerUserId() : ownerUserId;
        var existingTrack = trackRepository.findByFileNodeId(file.id());
        // 只读成员扫描共享文件时，已有曲目归文件所有者维护，绝不能拿原文件标签覆写。
        if (!catalogOwnerId.equals(ownerUserId) && existingTrack.isPresent()) {
            return;
        }
        // 所有者手动精修过的曲目只同步物理属性，不覆盖标题、歌手、专辑、歌词与封面。
        if (existingTrack.isPresent()
                && MetadataStatus.MANUAL.getValue().equals(existingTrack.get().getMetadataStatus())) {
            MusicTrack manualTrack = existingTrack.get();
            manualTrack.setFileSize(file.sizeBytes());
            manualTrack.setFormat(formatFromFileName(file.name()));
            trackRepository.save(manualTrack);
            return;
        }
        MusicTrack track = existingTrack.orElseGet(() -> {
            MusicTrack created = new MusicTrack();
            created.setOwnerUserId(catalogOwnerId);
            created.setFileNodeId(file.id());
            return created;
        });
        if (!catalogOwnerId.equals(track.getOwnerUserId())) {
            // 开发期数据修正：把历史上按扫描者归属的行改回文件所有者。
            track.setOwnerUserId(catalogOwnerId);
        }
        UUID previousArtistId = track.getArtistId();
        UUID previousAlbumId = track.getAlbumId();

        MusicFileNameGuess fileNameGuess = parseFileName(file.name());
        String title = firstText(metadata.title(), firstText(fileNameGuess.title(), titleFromFileName(file.name())));
        String artistName = firstText(metadata.artistName(), firstText(fileNameGuess.artistName(), "Unknown Artist"));
        String albumTitle = firstText(metadata.albumTitle(), firstText(fileNameGuess.albumTitle(), "Unknown Album"));

        // 使用缓存的 artist/album 解析
        String artistCacheKey = catalogOwnerId + "|" + artistName.toLowerCase(Locale.ROOT);
        MusicArtist artist = artistCache.get(artistCacheKey);
        if (artist == null) {
            artist = artist(catalogOwnerId, artistName);
            artistCache.put(artistCacheKey, artist);
        }
        String albumCacheKey = catalogOwnerId + "|" + albumTitle.toLowerCase(Locale.ROOT);
        MusicAlbum album = albumCache.get(albumCacheKey);
        if (album == null) {
            album = album(catalogOwnerId, albumTitle, artistName);
            albumCache.put(albumCacheKey, album);
        }

        track.setTitle(title);
        track.setArtistName(artistName);
        track.setAlbumTitle(albumTitle);
        track.setGenre(metadata.genre());
        track.setLyricsRaw(lyricsRaw);
        track.setTrackNumber(parseNullableInt(metadata.trackNumber()));
        track.setDiscNumber(parseNullableInt(metadata.discNumber()));
        track.setBitrate(metadata.bitrate());
        track.setSampleRate(metadata.sampleRate());
        applyDuration(track, metadata);
        track.setArtistId(artist.getId());
        track.setAlbumId(album.getId());
        track.setFormat(formatFromFileName(file.name()));
        track.setFileSize(file.sizeBytes());
        track.getProviderMetadata().put("title", title);
        track.getProviderMetadata().put("artistName", artistName);
        track.getProviderMetadata().put("albumTitle", albumTitle);
        track.getProviderMetadata().put("genre", metadata.genre());
        track.getProviderMetadata().put("lyricsRaw", lyricsRaw);
        if (metadata.trackNumber() != null) {
            track.getProviderMetadata().put("trackNumber", metadata.trackNumber());
        }
        if (metadata.discNumber() != null) {
            track.getProviderMetadata().put("discNumber", metadata.discNumber());
        }
        storeEmbeddedCover(catalogOwnerId, track, file, metadata.coverDataUrl());
        track.setMetadataStatus(metadata.hasAnyValue() || hasText(lyricsRaw) ? MetadataStatus.MATCHED.getValue() : MetadataStatus.PENDING.getValue());
        trackRepository.save(track);

        // 收集受影响的 ID（不逐个刷新，最后按归属人批量刷新）。
        Set<UUID> ownerArtistIds = affectedArtistsByOwner.computeIfAbsent(
                catalogOwnerId, key -> new HashSet<>());
        Set<UUID> ownerAlbumIds = affectedAlbumsByOwner.computeIfAbsent(
                catalogOwnerId, key -> new HashSet<>());
        if (previousArtistId != null) {
            ownerArtistIds.add(previousArtistId);
        }
        ownerArtistIds.add(artist.getId());
        if (previousAlbumId != null) {
            ownerAlbumIds.add(previousAlbumId);
        }
        ownerAlbumIds.add(album.getId());
    }

    /**
     * 把音频内嵌封面落成派生资产并回填 coverFileId，成功后移除内联地址。
     *
     * <p>内联 data URL 会随曲目列表与播放队列快照整段进出（单条几百 KB），是曲库首屏
     * 与重启恢复的主要载荷来源；资产化后列表只剩稳定 API 路径，列表位还能用派生缩略图。
     * 存储键以音频文件节点为资源标识，重复扫描命中同一 normalizedPath 复用节点，不新增对象。
     * 地址形态不认识、超限或存储失败时保留内联，展示不回退。</p>
     */
    private void storeEmbeddedCover(
            UUID ownerUserId,
            MusicTrack track,
            FileDescriptor sourceFile,
            String coverDataUrl
    ) {
        if (coverDataUrl == null || coverDataUrl.isBlank()) {
            return;
        }
        if (track.getCoverFileId() != null) {
            // 已有封面文件时列表不会用到内联地址，直接清掉这份冗余字节。
            track.getProviderMetadata().remove("coverDataUrl");
            return;
        }
        EmbeddedCover cover = parseEmbeddedCover(coverDataUrl);
        if (cover == null || !storeCoverAsset(ownerUserId, track, sourceFile, cover)) {
            track.getProviderMetadata().put("coverDataUrl", coverDataUrl);
            return;
        }
        track.getProviderMetadata().remove("coverDataUrl");
    }

    private boolean storeCoverAsset(
            UUID ownerUserId,
            MusicTrack track,
            FileDescriptor sourceFile,
            EmbeddedCover cover
    ) {
        Path staged = null;
        try {
            staged = Files.createTempFile("omninest-music-cover-", "." + cover.extension());
            Files.write(staged, cover.bytes());
            track.setCoverFileId(derivedAssetStorageService.store(
                    ownerUserId,
                    COVER_RESOURCE_TYPE,
                    sourceFile.id(),
                    COVER_ASSET_TYPE,
                    "cover." + cover.extension(),
                    cover.mimeType(),
                    staged
            ));
            return true;
        } catch (IOException | RuntimeException ex) {
            log.warn("音乐内嵌封面资产化失败，保留内联地址: fileNodeId={}, errorType={}",
                    sourceFile.id(), ex.getClass().getSimpleName());
            return false;
        } finally {
            deleteQuietly(staged);
        }
    }

    private EmbeddedCover parseEmbeddedCover(String coverDataUrl) {
        int comma = coverDataUrl.indexOf(',');
        if (comma <= 0) {
            return null;
        }
        String header = coverDataUrl.substring(0, comma).toLowerCase(Locale.ROOT);
        if (!header.startsWith("data:image/") || !header.endsWith(";base64")) {
            return null;
        }
        String mimeType = header.substring("data:".length(), header.length() - ";base64".length());
        String extension = coverExtension(mimeType);
        if (extension == null) {
            return null;
        }
        String payload = coverDataUrl.substring(comma + 1);
        long maxBytes = processingLimits.getMaxEmbeddedCoverBytes();
        long maxEncodedChars = (maxBytes / 3L + 1L) * 4L;
        if (payload.isEmpty() || payload.length() > maxEncodedChars) {
            return null;
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(payload);
        } catch (IllegalArgumentException ex) {
            log.warn("音乐内嵌封面 base64 解码失败: errorType={}", ex.getClass().getSimpleName());
            return null;
        }
        if (bytes.length == 0 || bytes.length > maxBytes) {
            return null;
        }
        return new EmbeddedCover(mimeType, extension, bytes);
    }

    private String coverExtension(String mimeType) {
        return switch (mimeType) {
            case "image/jpeg" -> "jpg";
            case "image/png" -> "png";
            case "image/gif" -> "gif";
            case "image/webp" -> "webp";
            default -> null;
        };
    }

    private void deleteQuietly(Path file) {
        if (file == null) {
            return;
        }
        try {
            Files.deleteIfExists(file);
        } catch (IOException ex) {
            log.debug("音乐封面临时文件清理失败: errorType={}", ex.getClass().getSimpleName());
        }
    }

    /**
     * 解码后的内嵌封面：MIME、派生文件名后缀与原始字节。
     */
    private record EmbeddedCover(String mimeType, String extension, byte[] bytes) {
    }

    /**
     * 只在解析出时长时写入：部分容器（moov 在尾部的 M4A、无 Xing 且长度未知的流式 WAV）
     * 读不出时长，重扫时不能把已有的正确值抹成空。
     */
    private void applyDuration(MusicTrack track, MusicMetadataExtractor.Metadata metadata) {
        if (metadata.durationSeconds() != null && metadata.durationSeconds() > 0) {
            track.setDurationSeconds(metadata.durationSeconds());
        }
    }

    private MusicMetadataExtractor.Metadata extractMetadata(FileDescriptor file) {
        try (FileContentStream content = fileQueryService.openOwnedFileContent(
                file.ownerUserId(),
                file.id())) {
            return metadataExtractor.extract(
                    content.inputStream(),
                    file.name(),
                    file.mimeType(),
                    file.sizeBytes()
            );
        } catch (IOException | RuntimeException exception) {
            log.warn("音乐元数据提取失败: fileNodeId={}, fileName={}", file.id(), file.name(), exception);
            return MusicMetadataExtractor.Metadata.empty();
        }
    }

    private String readTextObject(FileDescriptor file) {
        if (file == null) {
            return null;
        }
        try (FileContentStream content = fileQueryService.openOwnedFileContent(
                file.ownerUserId(),
                file.id())) {
            // 外挂 .lrc 大量使用 GBK/GB18030 与带 BOM 的 UTF-16：沿用阅读器的字符集嗅探，
            // 不能按 UTF-8 硬解。
            Charset charset = txtContentDecoder.detectCharset(file);
            String text = new String(
                    content.inputStream().readNBytes(512 * 1024),
                    charset
            ).trim();
            if (!text.isEmpty() && text.charAt(0) == '﻿') {
                text = text.substring(1).trim();
            }
            return text.isBlank() ? null : text;
        } catch (IOException | RuntimeException exception) {
            log.warn("读取文本对象失败: fileNodeId={}", file.id(), exception);
            return null;
        }
    }

    private MusicArtist artist(UUID ownerUserId, String name) {
        return artistRepository.findByOwnerUserIdAndNameIgnoreCase(ownerUserId, name)
                .orElseGet(() -> {
                    MusicArtist created = new MusicArtist();
                    created.setOwnerUserId(ownerUserId);
                    created.setName(name);
                    created.setTrackCount(0);
                    created.setAlbumCount(0);
                    return artistRepository.save(created);
                });
    }

    private MusicAlbum album(UUID ownerUserId, String title, String artistName) {
        return albumRepository.findByOwnerUserIdAndTitleIgnoreCase(ownerUserId, title)
                .orElseGet(() -> {
                    MusicAlbum created = new MusicAlbum();
                    created.setOwnerUserId(ownerUserId);
                    created.setTitle(title);
                    created.setArtistName(artistName);
                    created.setTrackCount(0);
                    return albumRepository.save(created);
                });
    }

    private boolean isAudioFile(FileDescriptor file) {
        if (!NodeType.FILE.getValue().equals(file.nodeType())) {
            return false;
        }
        // 排除视频转码派生的音频文件（如 AC3→AAC 提取的 audio_only.aac）
        if ("DERIVED".equals(file.sourceType())) {
            return false;
        }
        String mimeType = file.mimeType();
        if (mimeType != null && mimeType.toLowerCase(Locale.ROOT).startsWith("audio/")) {
            return true;
        }
        return switch (formatFromFileName(file.name())) {
            case "mp3", "flac", "aac", "m4a", "ogg", "opus", "wav", "aiff", "alac" -> true;
            default -> false;
        };
    }

    private boolean isLrcFile(FileDescriptor file) {
        return NodeType.FILE.getValue().equals(file.nodeType()) && "lrc".equals(formatFromFileName(file.name()));
    }

    private String titleFromFileName(String fileName) {
        String name = fileName == null ? "Unknown Track" : fileName.trim();
        int dotIndex = name.lastIndexOf('.');
        return dotIndex <= 0 ? name : name.substring(0, dotIndex);
    }

    private String formatFromFileName(String fileName) {
        if (fileName == null) {
            return "";
        }
        int dotIndex = fileName.lastIndexOf('.');
        return dotIndex < 0 || dotIndex == fileName.length() - 1
                ? ""
                : fileName.substring(dotIndex + 1).toLowerCase(Locale.ROOT);
    }

    private String firstText(String first, String fallback) {
        return first == null || first.isBlank() ? fallback : first;
    }

    /**
     * 从音频文件名解析 title/artist/album，用于无标签文件的元数据兜底。
     * 支持常见命名模式：
     *   "title - artist[album].ext"  → 偏爱 - 张芸京[破天荒]
     *   "artist - title.ext"         → 张芸京 - 偏爱
     *   "01. title - artist.ext"     → 05. 偏爱 - 张芸京
     *   "01 - artist - title.ext"    → 05 - 张芸京 - 偏爱
     *   "title.ext"                  → 偏爱（仅 title）
     */
    private MusicFileNameGuess parseFileName(String fileName) {
        if (fileName == null || fileName.isBlank()) {
            return MusicFileNameGuess.empty();
        }
        // 去掉扩展名
        String name = titleFromFileName(fileName).trim();
        if (name.isEmpty()) {
            return MusicFileNameGuess.empty();
        }

        // 去掉前导序号 "01. " / "01 - " / "01_" 等
        name = name.replaceFirst("^\\d{1,3}[.\\-_\\s]+", "").trim();

        // 模式1: "title - artist[album]"  或  "title-artist[album]"
        var bracketMatch = Pattern.compile("^(.+?)\\s*-\\s*(.+?)\\[(.+?)\\]$");
        var m1 = bracketMatch.matcher(name);
        if (m1.matches()) {
            return new MusicFileNameGuess(
                    cleanGuess(m1.group(1)),
                    cleanGuess(m1.group(2)),
                    cleanGuess(m1.group(3))
            );
        }

        // 模式2: "title - artist"（无 album）
        var dashMatch = Pattern.compile("^(.+?)\\s+-\\s+(.+)$");
        var m2 = dashMatch.matcher(name);
        if (m2.matches()) {
            String left = m2.group(1).trim();
            String right = m2.group(2).trim();
            // 启发式：如果左侧包含中文且较短（≤6字符），可能是 title；右侧可能是 artist
            // 反之亦然。这里默认采用 "title - artist" 模式
            return new MusicFileNameGuess(cleanGuess(left), cleanGuess(right), null);
        }

        // 模式3: 仅 title（无分隔符）
        return new MusicFileNameGuess(cleanGuess(name), null, null);
    }

    private String cleanGuess(String value) {
        if (value == null) return null;
        String cleaned = value.trim();
        return cleaned.isEmpty() ? null : cleaned;
    }

    private record MusicFileNameGuess(String title, String artistName, String albumTitle) {
        static MusicFileNameGuess empty() {
            return new MusicFileNameGuess(null, null, null);
        }
    }

    private Integer parseNullableInt(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            // 处理 "3/12" 格式（取斜杠前的数字）
            String trimmed = value.contains("/") ? value.substring(0, value.indexOf('/')).trim() : value.trim();
            return Integer.parseInt(trimmed);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    private String basePathKey(String path) {
        if (path == null || path.isBlank()) {
            return "";
        }
        String normalized = path.trim().toLowerCase(Locale.ROOT);
        int dotIndex = normalized.lastIndexOf('.');
        return dotIndex <= 0 ? normalized : normalized.substring(0, dotIndex);
    }

    private void recordTrackUpdated(UUID ownerUserId, MusicTrack track) {
        syncEventService.record(
                ownerUserId,
                SyncScope.MUSIC,
                "MUSIC_TRACK",
                track.getId().toString(),
                SyncAction.UPDATED,
                track.getVersion(),
                Map.of()
        );
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
        // 失败任务不是“已完成”：进度必须停在真实扫描位置，避免进度条瞬间跳满。
        return switch (job.getStatus()) {
            case "COMPLETED" -> 100;
            case "RUNNING" -> 50;
            default -> 0;
        };
    }
}
