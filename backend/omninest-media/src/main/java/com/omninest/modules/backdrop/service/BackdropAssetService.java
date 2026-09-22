package com.omninest.modules.backdrop.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.backdrop.config.BackdropRuntimeConfigService;
import com.omninest.modules.backdrop.domain.BackdropAsset;
import com.omninest.modules.backdrop.domain.BackdropAssetStatus;
import com.omninest.modules.backdrop.domain.BackdropMediaType;
import com.omninest.modules.backdrop.domain.BackdropWebPlaybackPolicy;
import com.omninest.modules.backdrop.dto.BackdropDtos.BackdropAssetDto;
import com.omninest.modules.backdrop.repository.BackdropAssetRepository;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileIngressStagingService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import net.coobird.thumbnailator.Thumbnails;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.multipart.MultipartFile;

/**
 * 背景素材应用服务。
 *
 * <p>上传链路:限流 → 扩展名与大小校验 → staging 流式写入并计算 SHA-256 → 魔数校验 →
 * 用户级去重 → 数量预检 → 存储预留 → 事务内落行(PROCESSING) → 隔离桶暂存并受理
 * BACKDROP_SECURITY_SCAN 异步任务 → 立即返回 PROCESSING。Worker 扫描通过后由
 * {@link #completeStagedAsset} 发布对象与缩略图并置 READY;检测到威胁或重试耗尽则
 * 标记 FAILED、释放预留并通知用户。进程崩溃窗口由对账任务兜底。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class BackdropAssetService {

    private static final String RESOURCE_TYPE = "BACKDROP";
    private static final String ASSET_TYPE_ORIGINAL = "ORIGINAL";
    private static final String ASSET_TYPE_PLAYBACK = "PLAYBACK";
    private static final String ASSET_TYPE_THUMBNAIL = "THUMBNAIL";
    private static final String RESERVATION_SOURCE_TYPE = "BACKDROP_UPLOAD";
    private static final String ORIGINAL_BASE_NAME = "original";
    private static final String THUMBNAIL_BASE_NAME = "thumbnail";

    private static String originalFileName(String extension) {
        return ORIGINAL_BASE_NAME + "." + extension;
    }
    private static final String DEFAULT_TITLE = "背景素材";
    private static final Set<String> IMAGE_EXTENSIONS = Set.of("jpg", "jpeg", "png", "webp", "gif");
    private static final Set<String> VIDEO_EXTENSIONS = Set.of("mp4", "webm", "mov", "m4v");
    private static final int THUMBNAIL_MAX_WIDTH = 1024;
    private static final int THUMBNAIL_MAX_HEIGHT = 1024;
    private static final double THUMBNAIL_QUALITY = 0.82;
    private static final Duration VIDEO_THUMBNAIL_TIMEOUT = Duration.ofSeconds(30);
    private static final Duration VIDEO_PLAYBACK_ENCODE_TIMEOUT = Duration.ofSeconds(90);
    private static final Duration VIDEO_CODEC_PROBE_TIMEOUT = Duration.ofSeconds(15);
    private static final Duration RESERVATION_TTL = Duration.ofHours(6);
    private static final Duration UPLOAD_RATE_WINDOW = Duration.ofHours(1);

    private static final boolean WEBP_AVAILABLE;
    static {
        boolean available = false;
        try {
            available = javax.imageio.ImageIO.getImageWritersByFormatName("webp").hasNext();
        } catch (Exception ignored) {
            // WebP 编码器不可用
        }
        WEBP_AVAILABLE = available;
    }

    private final BackdropAssetRepository backdropAssetRepository;
    private final BackdropRuntimeConfigService runtimeConfigService;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final FileQueryService fileQueryService;
    private final StorageQuotaService storageQuotaService;
    private final UserStorageCommand userStorageCommand;
    private final FileIngressStagingService ingressStagingService;
    private final BackdropScanTaskService backdropScanTaskService;
    private final RateLimitService rateLimitService;
    private final BackdropVideoThumbnailExtractor videoThumbnailExtractor;
    private final TransactionTemplate transactionTemplate;

    /**
     * 创建背景素材应用服务。
     *
     * @param backdropAssetRepository 素材仓储
     * @param runtimeConfigService 运行时配置服务
     * @param derivedAssetStorageService 派生资产存储服务
     * @param fileQueryService 文件查询服务
     * @param storageQuotaService 存储配额服务
     * @param userStorageCommand 用户存储命令端口
     * @param ingressStagingService 隔离暂存与扫描服务
     * @param backdropScanTaskService 扫描任务服务
     * @param rateLimitService 限流服务
     * @param transactionManager 事务管理器
     */
    public BackdropAssetService(
            BackdropAssetRepository backdropAssetRepository,
            BackdropRuntimeConfigService runtimeConfigService,
            DerivedAssetStorageService derivedAssetStorageService,
            FileQueryService fileQueryService,
            StorageQuotaService storageQuotaService,
            UserStorageCommand userStorageCommand,
            FileIngressStagingService ingressStagingService,
            BackdropScanTaskService backdropScanTaskService,
            RateLimitService rateLimitService,
            BackdropVideoThumbnailExtractor videoThumbnailExtractor,
            PlatformTransactionManager transactionManager
    ) {
        this.backdropAssetRepository = backdropAssetRepository;
        this.runtimeConfigService = runtimeConfigService;
        this.derivedAssetStorageService = derivedAssetStorageService;
        this.fileQueryService = fileQueryService;
        this.storageQuotaService = storageQuotaService;
        this.userStorageCommand = userStorageCommand;
        this.ingressStagingService = ingressStagingService;
        this.backdropScanTaskService = backdropScanTaskService;
        this.rateLimitService = rateLimitService;
        this.videoThumbnailExtractor = videoThumbnailExtractor;
        this.transactionTemplate = new TransactionTemplate(transactionManager);
    }

    /**
     * 查询用户的背景素材列表。
     *
     * @param ownerUserId 归属用户 ID
     * @return 按更新时间倒序的素材 DTO 列表
     */
    @org.springframework.transaction.annotation.Transactional(readOnly = true)
    public List<BackdropAssetDto> listAssets(UUID ownerUserId) {
        return backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(ownerUserId).stream()
                .map(this::toDto)
                .toList();
    }

    /**
     * 上传背景素材,全链路同步完成。
     *
     * @param ownerUserId 归属用户 ID
     * @param file 上传文件
     * @return 素材 DTO(READY)
     */
    public BackdropAssetDto uploadAsset(UUID ownerUserId, MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "背景素材文件不能为空");
        }
        if (!rateLimitService.tryAcquire(
                "backdrop:upload:" + ownerUserId, runtimeConfigService.uploadRatePerHour(), UPLOAD_RATE_WINDOW)) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "上传过于频繁，请稍后再试");
        }
        String clientExtension = extractClientExtension(file.getOriginalFilename());
        UUID assetId = UUID.randomUUID();
        Path stagingFile = null;
        try {
            stagingFile = Files.createTempFile("backdrop-upload-", "." + clientExtension);
            long writtenBytes;
            String sha256;
            try (InputStream input = file.getInputStream()) {
                MessageDigest digest = MessageDigest.getInstance("SHA-256");
                try (DigestInputStream digestInput = new DigestInputStream(input, digest);
                     java.io.OutputStream output = Files.newOutputStream(stagingFile)) {
                    writtenBytes = digestInput.transferTo(output);
                }
                sha256 = HexFormat.of().formatHex(digest.digest());
            } catch (NoSuchAlgorithmException ex) {
                throw new IllegalStateException("SHA-256 算法不可用", ex);
            }
            DetectedMedia media = detectMedia(stagingFile, clientExtension);
            enforceSizeLimit(writtenBytes, media, clientExtension);
            Optional<BackdropAsset> existing =
                    backdropAssetRepository.findByOwnerUserIdAndSha256(ownerUserId, sha256);
            if (existing.isPresent()) {
                return reuseExistingAsset(ownerUserId, existing.get(), stagingFile, media);
            }
            long usableCount = backdropAssetRepository.countByOwnerUserIdAndStatusNot(
                    ownerUserId, BackdropAssetStatus.FAILED);
            if (usableCount >= runtimeConfigService.maxAssetsPerUser()) {
                throw new BusinessException(ErrorCode.BACKDROP_QUOTA_EXCEEDED, "背景素材数量已达上限");
            }
            storageQuotaService.reserve(
                    ownerUserId, RESERVATION_SOURCE_TYPE, assetId, writtenBytes, Instant.now().plus(RESERVATION_TTL));
            UUID ingressItemId = null;
            try {
                createAssetRow(ownerUserId, assetId, file.getOriginalFilename(), media, writtenBytes, sha256);
                ingressItemId = ingressStagingService.stage(
                        ownerUserId, "BACKDROP", assetId,
                        originalFileName(media.extension()), media.mimeType(), stagingFile);
                UUID scanTaskId = backdropScanTaskService.enqueueScanTask(
                        ownerUserId, assetId, ingressItemId, originalFileName(media.extension()));
                storageQuotaService.extendReservation(
                        RESERVATION_SOURCE_TYPE, assetId, Instant.now().plus(RESERVATION_TTL));
                BackdropAsset processing = backdropAssetRepository.findById(assetId)
                        .orElseThrow(() -> new BusinessException(ErrorCode.BACKDROP_NOT_FOUND, "背景素材不存在"));
                log.info("背景素材上传受理安全扫描: userId={}, assetId={}, mediaType={}, size={}, taskId={}",
                        ownerUserId, assetId, media.mediaType(), writtenBytes, scanTaskId);
                return toDto(processing);
            } catch (RuntimeException ex) {
                compensateFailedUpload(ownerUserId, assetId, ingressItemId);
                if (ex instanceof BusinessException businessException) {
                    throw businessException;
                }
                log.warn("背景素材上传受理失败: userId={}, assetId={}", ownerUserId, assetId, ex);
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "背景素材处理失败");
            }
        } catch (IOException ex) {
            log.warn("背景素材读取失败: userId={}, assetId={}", ownerUserId, assetId, ex);
            safeReleaseReservation(assetId);
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "背景素材读取失败");
        } finally {
            deleteStagingQuietly(stagingFile);
        }
    }

    /**
     * 删除背景素材。
     * 数据行与配额先在同一事务内处理(DB-first),对象删除在事务提交后执行,
     * 对象删除失败时由对账任务清理孤儿节点。
     *
     * @param ownerUserId 归属用户 ID
     * @param assetId 素材 ID
     */
    public void deleteAsset(UUID ownerUserId, UUID assetId) {
        transactionTemplate.executeWithoutResult(status -> {
            BackdropAsset asset = backdropAssetRepository.findByIdAndOwnerUserId(assetId, ownerUserId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.BACKDROP_NOT_FOUND, "背景素材不存在"));
            backdropAssetRepository.delete(asset);
            if (asset.getStatus() == BackdropAssetStatus.PROCESSING) {
                safeReleaseReservation(assetId);
            } else {
                userStorageCommand.decrementUsage(ownerUserId, asset.getFileSize());
            }
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    deleteDerivedQuietly(ownerUserId, asset.getFileNodeId());
                    deleteDerivedQuietly(ownerUserId, asset.getPlaybackFileId());
                    deleteDerivedQuietly(ownerUserId, asset.getThumbFileId());
                }
            });
        });
        log.info("背景素材已删除: userId={}, assetId={}", ownerUserId, assetId);
    }

    /**
     * 删除当前用户全部背景素材。DB-first,单条失败不中断其余删除。
     *
     * @param ownerUserId 归属用户 ID
     * @return 删除结果:成功与失败条数
     */
    public DeleteAllResult deleteAllAssets(UUID ownerUserId) {
        List<UUID> assetIds = backdropAssetRepository.findByOwnerUserIdOrderByUpdatedAtDesc(ownerUserId)
                .stream()
                .map(BackdropAsset::getId)
                .toList();
        int deleted = 0;
        int failed = 0;
        for (UUID assetId : assetIds) {
            try {
                deleteAsset(ownerUserId, assetId);
                deleted++;
            } catch (BusinessException ex) {
                if (ex.errorCode().getCode() == ErrorCode.BACKDROP_NOT_FOUND.getCode()) {
                    continue;
                }
                failed++;
                log.warn("背景素材批量删除单项失败: userId={}, assetId={}, code={}",
                        ownerUserId, assetId, ex.errorCode().getCode());
            } catch (RuntimeException ex) {
                failed++;
                log.warn("背景素材批量删除单项异常: userId={}, assetId={}", ownerUserId, assetId, ex);
            }
        }
        log.info("背景素材批量删除完成: userId={}, requested={}, deleted={}, failed={}",
                ownerUserId, assetIds.size(), deleted, failed);
        return new DeleteAllResult(deleted, failed);
    }

    /**
     * 批量清空结果。
     *
     * @param deleted 成功删除数量
     * @param failed 失败数量
     */
    public record DeleteAllResult(int deleted, int failed) {
    }

    private BackdropAssetDto reuseExistingAsset(
            UUID ownerUserId, BackdropAsset existing, Path stagingFile, DetectedMedia media) {
        if (existing.getStatus() == BackdropAssetStatus.READY
                || existing.getStatus() == BackdropAssetStatus.PROCESSING) {
            return toDto(existing);
        }
        UUID ingressItemId = null;
        try {
            deleteDerivedQuietly(ownerUserId, existing.getFileNodeId());
            deleteDerivedQuietly(ownerUserId, existing.getPlaybackFileId());
            deleteDerivedQuietly(ownerUserId, existing.getThumbFileId());
            existing.setFileNodeId(null);
            existing.setPlaybackFileId(null);
            existing.setThumbFileId(null);
            existing.setFailReason(null);
            ingressItemId = ingressStagingService.stage(
                    ownerUserId, "BACKDROP", existing.getId(),
                    originalFileName(media.extension()), media.mimeType(), stagingFile);
            existing.setStatus(BackdropAssetStatus.PROCESSING);
            backdropAssetRepository.save(existing);
            backdropScanTaskService.enqueueScanTask(
                    ownerUserId, existing.getId(), ingressItemId, originalFileName(media.extension()));
            log.info("背景素材重新受理安全扫描: userId={}, assetId={}", ownerUserId, existing.getId());
            return toDto(existing);
        } catch (RuntimeException ex) {
            if (ingressItemId != null) {
                ingressStagingService.releaseObject(ingressItemId);
            }
            if (ex instanceof BusinessException businessException) {
                throw businessException;
            }
            log.warn("背景素材重新受理失败,保留 FAILED 状态等待重试: userId={}, assetId={}",
                    ownerUserId, existing.getId(), ex);
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "背景素材处理失败");
        }
    }

    private void createAssetRow(
            UUID ownerUserId, UUID assetId, String clientFileName,
            DetectedMedia media, long sizeBytes, String sha256) {
        transactionTemplate.executeWithoutResult(status -> {
            long usableCount = backdropAssetRepository.countByOwnerUserIdAndStatusNot(
                    ownerUserId, BackdropAssetStatus.FAILED);
            if (usableCount >= runtimeConfigService.maxAssetsPerUser()) {
                throw new BusinessException(ErrorCode.BACKDROP_QUOTA_EXCEEDED, "背景素材数量已达上限");
            }
            BackdropAsset asset = new BackdropAsset();
            asset.setId(assetId);
            asset.setOwnerUserId(ownerUserId);
            asset.setTitle(resolveTitle(clientFileName));
            asset.setMediaType(media.mediaType());
            asset.setFileSize(sizeBytes);
            asset.setSha256(sha256);
            backdropAssetRepository.save(asset);
        });
    }

    /**
     * 发布收尾:基于 freshly 加载的实例做且仅做一次 merge 保存,写入节点引用与 READY 状态。
     * 关键约束:实体带 @Version,连续对同一游离引用多次 save 会因版本不递增触发 StaleObjectState。
     */
    private BackdropAsset finalizePublishedAsset(
            UUID ownerUserId, UUID assetId, UUID fileNodeId, UUID playbackFileId,
            UUID thumbFileId, ImageDimensions dimensions, String videoCodec) {
        BackdropAsset asset = backdropAssetRepository.findById(assetId)
                .orElseThrow(() -> new BusinessException(ErrorCode.BACKDROP_NOT_FOUND, "背景素材不存在"));
        asset.setFileNodeId(fileNodeId);
        asset.setPlaybackFileId(playbackFileId);
        asset.setThumbFileId(thumbFileId);
        asset.setVideoCodec(videoCodec);
        asset.setStatus(BackdropAssetStatus.READY);
        if (dimensions != null) {
            asset.setWidth(dimensions.width());
            asset.setHeight(dimensions.height());
        }
        return backdropAssetRepository.save(asset);
    }

    private ImageDimensions readImageDimensions(Path stagingFile, DetectedMedia media) {
        if (media.mediaType() == BackdropMediaType.VIDEO) {
            return null;
        }
        try {
            java.awt.image.BufferedImage image = javax.imageio.ImageIO.read(stagingFile.toFile());
            if (image == null) {
                return null;
            }
            return new ImageDimensions(image.getWidth(), image.getHeight());
        } catch (IOException | RuntimeException ex) {
            log.debug("背景素材尺寸解析失败: extension={}, message={}", media.extension(), ex.getMessage());
            return null;
        }
    }

    /**
     * 为视频生成 ≤1080p 播放衍生文件,降低客户端解码成本;失败不阻断上传。
     *
     * <p>当前有意不接线:壁纸按原片播放,见 {@code completeStagedAsset} 的 playbackFileId 传空。
     * 保留该实现供后续按素材生成兼容版本时复用,删除前需先确认 Web 端兼容策略定稿。</p>
     */
    /**
     * 探测视频编码名，仅用于客户端 Web 端可播提示；图片与探测失败返回空，不影响发布结果。
     */
    private String probeVideoCodecForNotice(Path stagingFile, DetectedMedia media) {
        if (media.mediaType() != BackdropMediaType.VIDEO) {
            return null;
        }
        return videoThumbnailExtractor.probeVideoCodec(stagingFile, VIDEO_CODEC_PROBE_TIMEOUT).orElse(null);
    }

    private UUID generateAndStorePlayback(
            UUID ownerUserId, UUID assetId, Path stagingFile, DetectedMedia media, UUID publishedNodeId) {
        if (media.mediaType() != BackdropMediaType.VIDEO) {
            return null;
        }
        Path playbackFile = null;
        try {
            Optional<Path> scaled = videoThumbnailExtractor.scaleForWallpaperPlayback(
                    stagingFile, VIDEO_PLAYBACK_ENCODE_TIMEOUT);
            if (scaled.isEmpty()) {
                return null;
            }
            playbackFile = scaled.get();
            return derivedAssetStorageService.store(
                    ownerUserId, RESOURCE_TYPE, assetId, ASSET_TYPE_PLAYBACK,
                    "playback.mp4", "video/mp4", playbackFile);
        } catch (RuntimeException ex) {
            log.warn("壁纸播放衍生存储失败,回退原始视频: userId={}, assetId={}",
                    ownerUserId, assetId, ex);
            return null;
        } finally {
            if (playbackFile != null) {
                try {
                    Files.deleteIfExists(playbackFile);
                } catch (IOException ex) {
                    log.debug("播放衍生临时文件清理失败: {}", ex.getMessage());
                }
            }
        }
    }

    private UUID generateAndStoreThumbnail(
            UUID ownerUserId, UUID assetId, Path stagingFile, DetectedMedia media, UUID publishedNodeId) {
        if (media.mediaType() == BackdropMediaType.VIDEO) {
            return generateAndStoreVideoThumbnail(ownerUserId, assetId, stagingFile, publishedNodeId);
        }
        if (media.mediaType() != BackdropMediaType.IMAGE) {
            return null;
        }
        Path thumbnailFile = null;
        try {
            thumbnailFile = Files.createTempFile("backdrop-thumb-", "." + thumbnailExtension());
            Thumbnails.of(stagingFile.toFile())
                    .size(THUMBNAIL_MAX_WIDTH, THUMBNAIL_MAX_HEIGHT)
                    .keepAspectRatio(true)
                    .outputQuality(THUMBNAIL_QUALITY)
                    .outputFormat(thumbnailFormat())
                    .toFile(thumbnailFile.toFile());
            return derivedAssetStorageService.store(
                    ownerUserId, RESOURCE_TYPE, assetId, ASSET_TYPE_THUMBNAIL,
                    THUMBNAIL_BASE_NAME + "." + thumbnailFormat(),
                    thumbnailMimeType(), thumbnailFile);
        } catch (IOException ex) {
            throw new UncheckedIOException("背景素材缩略图生成失败", ex);
        }
    }

    /**
     * 提取视频首帧作为预览缩略图。抽帧失败不阻断上传主流程,仅返回空并保留占位预览。
     */
    private UUID generateAndStoreVideoThumbnail(
            UUID ownerUserId, UUID assetId, Path stagingFile, UUID publishedNodeId) {
        Path thumbnailFile = null;
        try {
            Optional<Path> extracted = videoThumbnailExtractor.extractFirstFrame(
                    ownerUserId, publishedNodeId, stagingFile, VIDEO_THUMBNAIL_TIMEOUT);
            if (extracted.isEmpty()) {
                return null;
            }
            thumbnailFile = extracted.get();
            return derivedAssetStorageService.store(
                    ownerUserId, RESOURCE_TYPE, assetId, ASSET_TYPE_THUMBNAIL,
                    THUMBNAIL_BASE_NAME + ".jpg",
                    "image/jpeg", thumbnailFile);
        } catch (RuntimeException ex) {
            log.warn("背景视频缩略图生成失败,保留无预览状态: userId={}, assetId={}",
                    ownerUserId, assetId, ex);
            return null;
        } finally {
            if (thumbnailFile != null) {
                try {
                    Files.deleteIfExists(thumbnailFile);
                } catch (IOException ex) {
                    log.debug("背景视频缩略图临时文件清理失败: {}", ex.getMessage());
                }
            }
        }
    }

    private void compensateFailedUpload(UUID ownerUserId, UUID assetId, UUID ingressItemId) {
        safeReleaseReservation(assetId);
        try {
            if (ingressItemId != null) {
                ingressStagingService.releaseObject(ingressItemId);
            }
            backdropAssetRepository.findById(assetId).ifPresent(asset -> {
                deleteDerivedQuietly(ownerUserId, asset.getFileNodeId());
                deleteDerivedQuietly(ownerUserId, asset.getPlaybackFileId());
                deleteDerivedQuietly(ownerUserId, asset.getThumbFileId());
                backdropAssetRepository.delete(asset);
            });
        } catch (RuntimeException ex) {
            log.warn("背景素材上传补偿未完全成功,等待对账兜底: userId={}, assetId={}", ownerUserId, assetId, ex);
        }
    }

    private void deleteDerivedQuietly(UUID ownerUserId, UUID fileNodeId) {
        if (fileNodeId == null) {
            return;
        }
        try {
            derivedAssetStorageService.deleteOwned(ownerUserId, fileNodeId);
        } catch (RuntimeException ex) {
            log.warn("背景派生对象删除失败,等待对账兜底: userId={}, fileNodeId={}", ownerUserId, fileNodeId, ex);
        }
    }

    private void safeReleaseReservation(UUID assetId) {
        try {
            storageQuotaService.releaseReservation(RESERVATION_SOURCE_TYPE, assetId);
        } catch (RuntimeException ex) {
            log.warn("背景素材配额预留释放失败: assetId={}", assetId, ex);
        }
    }

    /**
     * 完成暂存素材的发布:读取暂存对象、存储原始节点、生成缩略图并置 READY。
     * 由安全扫描 Worker 在扫描通过后调用;失败时清理本次派生节点、标记 FAILED 并释放预留。
     *
     * @param ownerUserId 归属用户 ID
     * @param assetId 素材 ID
     * @param ingressItemId 入库记录 ID
     * @param originalFileName 暂存对象原始文件名
     */
    public void completeStagedAsset(UUID ownerUserId, UUID assetId, UUID ingressItemId, String originalFileName) {
        Path stagingFile = null;
        try {
            stagingFile = ingressStagingService.copyToTempFile(ingressItemId);
            DetectedMedia media = detectMedia(stagingFile, extensionOf(originalFileName));
            UUID publishedNodeId = derivedAssetStorageService.store(
                    ownerUserId, RESOURCE_TYPE, assetId, ASSET_TYPE_ORIGINAL,
                    originalFileName, media.mimeType(), stagingFile);
            ImageDimensions dimensions = readImageDimensions(stagingFile, media);
            // 不做服务端降质衍生:壁纸默认原片,由客户端可选本地缓存。
            UUID thumbNodeId = generateAndStoreThumbnail(
                    ownerUserId, assetId, stagingFile, media, publishedNodeId);
            String videoCodec = probeVideoCodecForNotice(stagingFile, media);
            finalizePublishedAsset(
                    ownerUserId, assetId, publishedNodeId, null, thumbNodeId, dimensions, videoCodec);
            BackdropAsset asset = backdropAssetRepository.findById(assetId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.BACKDROP_NOT_FOUND, "背景素材不存在"));
            storageQuotaService.settleReservation(RESERVATION_SOURCE_TYPE, assetId, asset.getFileSize());
            ingressStagingService.markAvailable(ingressItemId, publishedNodeId);
            log.info("背景素材异步发布完成: userId={}, assetId={}", ownerUserId, assetId);
        } catch (IOException ex) {
            BusinessException wrapped = new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "背景素材暂存对象读取失败");
            failProcessingAsset(ownerUserId, assetId, wrapped);
            throw wrapped;
        } catch (RuntimeException ex) {
            failProcessingAsset(ownerUserId, assetId, ex);
            throw ex;
        } finally {
            deleteStagingQuietly(stagingFile);
        }
    }

    private void failProcessingAsset(UUID ownerUserId, UUID assetId, RuntimeException cause) {
        try {
            BackdropAsset asset = backdropAssetRepository.findById(assetId).orElse(null);
            if (asset == null || asset.getStatus() == BackdropAssetStatus.READY) {
                return;
            }
            deleteDerivedQuietly(ownerUserId, asset.getFileNodeId());
            deleteDerivedQuietly(ownerUserId, asset.getPlaybackFileId());
            deleteDerivedQuietly(ownerUserId, asset.getThumbFileId());
            asset.setFileNodeId(null);
            asset.setPlaybackFileId(null);
            asset.setThumbFileId(null);
            asset.setStatus(BackdropAssetStatus.FAILED);
            asset.setFailReason(cause.getMessage() == null
                    ? "安全扫描后发布失败"
                    : cause.getMessage().substring(0, Math.min(cause.getMessage().length(), 200)));
            backdropAssetRepository.save(asset);
            safeReleaseReservation(assetId);
        } catch (RuntimeException settleException) {
            log.warn("背景素材失败状态落盘失败,等待对账兜底: assetId={}", assetId, settleException);
        }
    }

    private String extensionOf(String originalFileName) {
        if (originalFileName == null) {
            return "bin";
        }
        int dotIndex = originalFileName.lastIndexOf('.');
        return dotIndex < 0 || dotIndex == originalFileName.length() - 1
                ? "bin"
                : originalFileName.substring(dotIndex + 1);
    }

    private void enforceSizeLimit(long actualBytes, DetectedMedia media, String clientExtension) {
        long maxBytes = media.mediaType() == BackdropMediaType.VIDEO
                ? runtimeConfigService.maxVideoBytes()
                : runtimeConfigService.maxImageBytes();
        if (actualBytes > maxBytes) {
            throw new BusinessException(ErrorCode.BACKDROP_FILE_TOO_LARGE,
                    "背景素材文件过大,上限为 " + maxBytes + " 字节");
        }
        boolean clientIsImage = IMAGE_EXTENSIONS.contains(clientExtension);
        boolean clientIsVideo = VIDEO_EXTENSIONS.contains(clientExtension);
        if (media.mediaType() == BackdropMediaType.VIDEO && clientIsImage
                || media.mediaType() != BackdropMediaType.VIDEO && clientIsVideo) {
            throw new BusinessException(ErrorCode.BACKDROP_UNSUPPORTED_FORMAT, "文件扩展名与实际内容不一致");
        }
    }

    private DetectedMedia detectMedia(Path stagingFile, String clientExtension) throws IOException {
        byte[] head;
        try (InputStream input = Files.newInputStream(stagingFile)) {
            head = input.readNBytes(32);
        }
        DetectedMedia media = detectByMagic(head);
        if (media == null) {
            throw new BusinessException(ErrorCode.BACKDROP_UNSUPPORTED_FORMAT,
                    "仅支持 JPG/PNG/WebP/GIF 图片或 MP4/WebM/MOV 视频");
        }
        return media;
    }

    private DetectedMedia detectByMagic(byte[] head) {
        if (head.length >= 3 && head[0] == (byte) 0xFF && head[1] == (byte) 0xD8 && head[2] == (byte) 0xFF) {
            return new DetectedMedia(BackdropMediaType.IMAGE, "image/jpeg", "jpg");
        }
        if (matchesAt(head, 0, new byte[]{(byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A})) {
            return new DetectedMedia(BackdropMediaType.IMAGE, "image/png", "png");
        }
        if (matchesAt(head, 0, "GIF87a".getBytes(StandardCharsets.US_ASCII))
                || matchesAt(head, 0, "GIF89a".getBytes(StandardCharsets.US_ASCII))) {
            return new DetectedMedia(BackdropMediaType.GIF, "image/gif", "gif");
        }
        if (head.length >= 12
                && matchesAt(head, 0, "RIFF".getBytes(StandardCharsets.US_ASCII))
                && matchesAt(head, 8, "WEBP".getBytes(StandardCharsets.US_ASCII))) {
            return new DetectedMedia(BackdropMediaType.IMAGE, "image/webp", "webp");
        }
        if (head.length >= 12 && matchesAt(head, 4, "ftyp".getBytes(StandardCharsets.US_ASCII))) {
            if (matchesAt(head, 8, "qt  ".getBytes(StandardCharsets.US_ASCII))) {
                return new DetectedMedia(BackdropMediaType.VIDEO, "video/quicktime", "mov");
            }
            return new DetectedMedia(BackdropMediaType.VIDEO, "video/mp4", "mp4");
        }
        if (head.length >= 4
                && head[0] == 0x1A && head[1] == 0x45 && head[2] == (byte) 0xDF && head[3] == (byte) 0xA3) {
            return new DetectedMedia(BackdropMediaType.VIDEO, "video/webm", "webm");
        }
        return null;
    }

    private boolean matchesAt(byte[] bytes, int offset, byte[] expected) {
        if (bytes.length < offset + expected.length) {
            return false;
        }
        for (int index = 0; index < expected.length; index++) {
            if (bytes[offset + index] != expected[index]) {
                return false;
            }
        }
        return true;
    }

    private String extractClientExtension(String originalFileName) {
        String fileName = originalFileName == null ? "" : originalFileName;
        int separatorIndex = Math.max(fileName.lastIndexOf('/'), fileName.lastIndexOf('\\'));
        if (separatorIndex >= 0) {
            fileName = fileName.substring(separatorIndex + 1);
        }
        int dotIndex = fileName.lastIndexOf('.');
        if (dotIndex < 0 || dotIndex == fileName.length() - 1) {
            throw new BusinessException(ErrorCode.BACKDROP_UNSUPPORTED_FORMAT, "无法识别的文件扩展名");
        }
        String extension = fileName.substring(dotIndex + 1).toLowerCase(java.util.Locale.ROOT);
        if (!IMAGE_EXTENSIONS.contains(extension) && !VIDEO_EXTENSIONS.contains(extension)) {
            throw new BusinessException(ErrorCode.BACKDROP_UNSUPPORTED_FORMAT,
                    "仅支持 JPG/PNG/WebP/GIF 图片或 MP4/WebM/MOV/M4V 视频");
        }
        return extension;
    }

    private String resolveTitle(String clientFileName) {
        String fileName = clientFileName == null ? "" : clientFileName;
        int separatorIndex = Math.max(fileName.lastIndexOf('/'), fileName.lastIndexOf('\\'));
        if (separatorIndex >= 0) {
            fileName = fileName.substring(separatorIndex + 1);
        }
        int dotIndex = fileName.lastIndexOf('.');
        if (dotIndex > 0) {
            fileName = fileName.substring(0, dotIndex);
        }
        String title = fileName.trim();
        if (title.isEmpty()) {
            return DEFAULT_TITLE;
        }
        return title.length() > 200 ? title.substring(0, 200) : title;
    }

    private BackdropAssetDto toDto(BackdropAsset asset) {
        // 默认下发原片:不擅自降质;客户端可选本地缓存降低网络抖动。
        FileDownloadUrlDto content = safeDownloadUrl(asset.getOwnerUserId(), asset.getFileNodeId());
        FileDownloadUrlDto thumb = safeDownloadUrl(asset.getOwnerUserId(), asset.getThumbFileId());
        return new BackdropAssetDto(
                asset.getId(),
                asset.getTitle(),
                asset.getMediaType().getValue(),
                asset.getStatus().name(),
                asset.getFailReason(),
                content == null ? null : content.downloadUrl(),
                content == null ? null : content.expiresAt(),
                thumb == null ? null : thumb.downloadUrl(),
                thumb == null ? null : thumb.expiresAt(),
                asset.getWidth(),
                asset.getHeight(),
                asset.getDurationMs(),
                asset.getFileSize(),
                asset.getUpdatedAt(),
                asset.getVideoCodec(),
                BackdropWebPlaybackPolicy.isWebPlayable(asset.getVideoCodec())
        );
    }

    private FileDownloadUrlDto safeDownloadUrl(UUID ownerUserId, UUID fileId) {
        if (fileId == null) {
            return null;
        }
        try {
            return fileQueryService.createDownloadUrl(ownerUserId, fileId);
        } catch (RuntimeException ex) {
            log.warn("背景素材签名 URL 生成失败: userId={}, fileId={}", ownerUserId, fileId, ex);
            return null;
        }
    }

    private String thumbnailFormat() {
        return WEBP_AVAILABLE ? "webp" : "jpg";
    }

    private String thumbnailMimeType() {
        return WEBP_AVAILABLE ? "image/webp" : "image/jpeg";
    }

    private String thumbnailExtension() {
        return "." + thumbnailFormat();
    }

    private void deleteStagingQuietly(Path stagingFile) {
        if (stagingFile == null) {
            return;
        }
        try {
            Files.deleteIfExists(stagingFile);
        } catch (IOException ex) {
            log.debug("背景素材 staging 清理失败: {}", ex.getMessage());
        }
    }

    /**
     * 魔数探测结果。
     *
     * @param mediaType 媒体类型
     * @param mimeType 规范化 MIME
     * @param extension 规范化扩展名
     */
    private record DetectedMedia(BackdropMediaType mediaType, String mimeType, String extension) {
    }

    /**
     * 服务端解析的展示尺寸。
     *
     * @param width 宽度像素
     * @param height 高度像素
     */
    private record ImageDimensions(int width, int height) {
    }
}
