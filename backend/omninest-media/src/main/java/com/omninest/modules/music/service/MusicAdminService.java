package com.omninest.modules.music.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FilePermissionService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicArtist;
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
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.UUID;
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
        scanJobRepository.save(job);

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
            Set<UUID> affectedArtistIds = new HashSet<>();
            Set<UUID> affectedAlbumIds = new HashSet<>();
            int visited = 0;

            for (FileDescriptor file : nodes) {
                visited++;
                if (isAudioFile(file)) {
                    FileDescriptor sidecarLyrics = lyricFilesByBasePath.get(
                            basePathKey(file.normalizedPath())
                    );
                    try {
                        // 逐文件独立事务：单个文件下载/解析/落库失败不阻塞整库扫描。
                        transactionTemplate.executeWithoutResult(status ->
                                importAudioFileCached(ownerUserId, file, sidecarLyrics,
                                        artistCache, albumCache, affectedArtistIds, affectedAlbumIds)
                        );
                        imported++;
                    } catch (Exception perFileError) {
                        log.warn("音乐扫描单文件失败，跳过继续: jobId={}, errorType={}",
                                jobId, perFileError.getClass().getSimpleName());
                    }
                }
                if (!nodes.isEmpty() && (visited == nodes.size() || visited % 20 == 0)) {
                    int progress = 10 + (int) Math.floor((visited * 80.0) / nodes.size());
                    taskRecordService.updateExecution(jobId, "SCANNING", progress);
                }
            }

            // 批量刷新统计
            catalogService.refreshStatisticsBatch(ownerUserId, affectedArtistIds, affectedAlbumIds);
            job.setStatus(TaskStatus.COMPLETED.getValue());
            job.setScannedFiles(imported);
            job.setMessage("音乐库扫描完成，已处理 " + imported + " 个音频文件");
            taskRecordService.markCompleted(jobId, Map.of("imported", imported));
            // 扫描入库改变音乐仪表盘统计与最近列表，需失效缓存。
            readThroughCache.invalidate("omninest:dashboard:music:" + ownerUserId);
            syncEventService.invalidate(
                    ownerUserId,
                    SyncScope.MUSIC,
                    "MUSIC_LIBRARY",
                    Map.of("source", "SCAN", "imported", imported)
            );
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

    @Transactional(rollbackFor = Exception.class)
    public MusicTrackDto updateTrack(UUID ownerUserId, UUID trackId, UpdateMusicTrackRequest request) {
        log.info("更新音乐曲目: trackId={}", trackId);
        MusicTrack track = musicLibraryService.requireTrack(ownerUserId, trackId);
        UUID previousArtistId = track.getArtistId();
        UUID previousAlbumId = track.getAlbumId();

        // 同步 music_artists / music_albums 实体，重关联 FK
        String artistName = request.artistName() != null ? request.artistName().trim() : track.getArtistName();
        String albumTitle = request.albumTitle() != null ? request.albumTitle().trim() : track.getAlbumTitle();
        var artist = catalogService.resolveArtist(ownerUserId, artistName, null, null);
        var album = catalogService.resolveAlbum(ownerUserId, albumTitle, artistName, null, null, null, null);

        track.setTitle(request.title().trim());
        track.setArtistName(artistName);
        track.setAlbumTitle(albumTitle);
        track.setGenre(request.genre());
        track.setLyricsRaw(request.lyricsRaw());
        track.setCoverFileId(request.coverFileId());
        track.setArtistId(artist.getId());
        track.setAlbumId(album.getId());
        track.setMetadataStatus(MetadataStatus.MANUAL.getValue());
        trackRepository.save(track);
        catalogService.refreshStatistics(ownerUserId, previousArtistId, previousAlbumId, track);
        recordTrackUpdated(ownerUserId, track);
        return musicLibraryService.toTrackDto(track, false);
    }

    @Transactional(rollbackFor = Exception.class)
    public MusicTrackDto applyLyrics(UUID ownerUserId, UUID trackId, String lyrics) {
        log.info("应用歌词: trackId={}", trackId);
        MusicTrack track = musicLibraryService.requireTrack(ownerUserId, trackId);
        track.setLyricsRaw(lyrics);
        trackRepository.save(track);
        recordTrackUpdated(ownerUserId, track);
        log.info("歌词已应用: trackId={}, length={}", trackId, lyrics != null ? lyrics.length() : 0);
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
        // 查找同目录同名 .lrc 歌词文件
        String baseName = titleFromFileName(file.name());
        FileDescriptor sidecarLyrics = fileMetadataQueryService
                .listOwnedActiveChildren(ownerUserId, file.parentId())
                .stream()
                .filter(node -> isLrcFile(node) && titleFromFileName(node.name()).equals(baseName))
                .findFirst()
                .orElse(null);
        importAudioFile(ownerUserId, file, sidecarLyrics);
        // 单曲导入改变音乐仪表盘统计与最近列表，需失效缓存。
        readThroughCache.invalidate("omninest:dashboard:music:" + ownerUserId);
        syncEventService.invalidate(
                ownerUserId,
                SyncScope.MUSIC,
                "MUSIC_LIBRARY",
                Map.of("source", "SINGLE_IMPORT")
        );
    }

    private void importAudioFile(UUID ownerUserId, FileDescriptor file, FileDescriptor sidecarLyrics) {
        var existingTrack = trackRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, file.id());
        MusicTrack track = existingTrack.orElseGet(() -> {
            MusicTrack created = new MusicTrack();
            created.setOwnerUserId(ownerUserId);
            created.setFileNodeId(file.id());
            return created;
        });
        UUID previousArtistId = track.getArtistId();
        UUID previousAlbumId = track.getAlbumId();
        MusicMetadataExtractor.Metadata metadata = extractMetadata(file);
        String lyricsRaw = firstText(metadata.lyricsRaw(), readTextObject(sidecarLyrics));

        // 文件名解析兜底：当 ID3/Vorbis 标签缺失时，从文件名提取 title/artist/album
        MusicFileNameGuess fileNameGuess = parseFileName(file.name());
        String title = firstText(metadata.title(), firstText(fileNameGuess.title(), titleFromFileName(file.name())));
        String artistName = firstText(metadata.artistName(), firstText(fileNameGuess.artistName(), "Unknown Artist"));
        String albumTitle = firstText(metadata.albumTitle(), firstText(fileNameGuess.albumTitle(), "Unknown Album"));
        MusicArtist artist = artist(ownerUserId, artistName);
        MusicAlbum album = album(ownerUserId, albumTitle, artistName);
        track.setTitle(title);
        track.setArtistName(artistName);
        track.setAlbumTitle(albumTitle);
        track.setGenre(metadata.genre());
        track.setLyricsRaw(lyricsRaw);
        track.setTrackNumber(parseNullableInt(metadata.trackNumber()));
        track.setDiscNumber(parseNullableInt(metadata.discNumber()));
        track.setBitrate(metadata.bitrate());
        track.setSampleRate(metadata.sampleRate());
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
        if (metadata.coverDataUrl() != null && !metadata.coverDataUrl().isBlank()) {
            track.getProviderMetadata().put("coverDataUrl", metadata.coverDataUrl());
        }
        track.setMetadataStatus(metadata.hasAnyValue() || hasText(lyricsRaw) ? MetadataStatus.MATCHED.getValue() : MetadataStatus.PENDING.getValue());
        trackRepository.save(track);
        catalogService.refreshStatistics(ownerUserId, previousArtistId, previousAlbumId, track);
    }

    /**
     * 带缓存的音频文件导入。使用 artist/album 缓存减少 DB 查询，
     * 收集受影响的 ID 用于后续批量刷新统计。
     */
    private void importAudioFileCached(
            UUID ownerUserId, FileDescriptor file, FileDescriptor sidecarLyrics,
            Map<String, MusicArtist> artistCache, Map<String, MusicAlbum> albumCache,
            Set<UUID> affectedArtistIds, Set<UUID> affectedAlbumIds
    ) {
        var existingTrack = trackRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, file.id());
        MusicTrack track = existingTrack.orElseGet(() -> {
            MusicTrack created = new MusicTrack();
            created.setOwnerUserId(ownerUserId);
            created.setFileNodeId(file.id());
            return created;
        });
        UUID previousArtistId = track.getArtistId();
        UUID previousAlbumId = track.getAlbumId();
        MusicMetadataExtractor.Metadata metadata = extractMetadata(file);
        String lyricsRaw = firstText(metadata.lyricsRaw(), readTextObject(sidecarLyrics));

        MusicFileNameGuess fileNameGuess = parseFileName(file.name());
        String title = firstText(metadata.title(), firstText(fileNameGuess.title(), titleFromFileName(file.name())));
        String artistName = firstText(metadata.artistName(), firstText(fileNameGuess.artistName(), "Unknown Artist"));
        String albumTitle = firstText(metadata.albumTitle(), firstText(fileNameGuess.albumTitle(), "Unknown Album"));

        // 使用缓存的 artist/album 解析
        String artistCacheKey = ownerUserId + "|" + artistName.toLowerCase(Locale.ROOT);
        MusicArtist artist = artistCache.get(artistCacheKey);
        if (artist == null) {
            artist = artist(ownerUserId, artistName);
            artistCache.put(artistCacheKey, artist);
        }
        String albumCacheKey = ownerUserId + "|" + albumTitle.toLowerCase(Locale.ROOT);
        MusicAlbum album = albumCache.get(albumCacheKey);
        if (album == null) {
            album = album(ownerUserId, albumTitle, artistName);
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
        if (metadata.coverDataUrl() != null && !metadata.coverDataUrl().isBlank()) {
            track.getProviderMetadata().put("coverDataUrl", metadata.coverDataUrl());
        }
        track.setMetadataStatus(metadata.hasAnyValue() || hasText(lyricsRaw) ? MetadataStatus.MATCHED.getValue() : MetadataStatus.PENDING.getValue());
        trackRepository.save(track);

        // 收集受影响的 ID（不逐个刷新，最后批量刷新）
        if (previousArtistId != null) affectedArtistIds.add(previousArtistId);
        affectedArtistIds.add(artist.getId());
        if (previousAlbumId != null) affectedAlbumIds.add(previousAlbumId);
        affectedAlbumIds.add(album.getId());
    }

    private MusicMetadataExtractor.Metadata extractMetadata(FileDescriptor file) {
        try (FileContentStream content = fileQueryService.openOwnedFileContent(
                file.ownerUserId(),
                file.id())) {
            return metadataExtractor.extract(content.inputStream(), file.name(), file.mimeType());
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
            String text = new String(
                    content.inputStream().readNBytes(512 * 1024),
                    StandardCharsets.UTF_8
            ).trim();
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
        return switch (job.getStatus()) {
            case "COMPLETED" -> 100;
            case "FAILED" -> 100;
            case "RUNNING" -> 50;
            default -> 0;
        };
    }
}
