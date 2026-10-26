package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FilePurgeOrigin;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.domain.PhotoEditVersion;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.dto.PhotoDtos.EditRequest;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoEditVersionDto;
import com.omninest.modules.photos.repository.PhotoEditVersionRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.awt.Graphics2D;
import java.awt.geom.AffineTransform;
import java.awt.image.AffineTransformOp;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Semaphore;
import javax.imageio.ImageIO;
import javax.imageio.ImageReadParam;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 照片编辑服务，提供裁剪、旋转、亮度/对比度、滤镜等非破坏性编辑操作。
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class PhotoEditService {

    /** 编辑解码上限：超过时在解码阶段等间隔抽样，避免在受限堆内展开 100MP 画布。 */
    private static final long MAX_EDIT_DECODE_PIXELS = 24_000_000L;

    /** 流式落盘缓冲区大小。 */
    private static final int COPY_BUFFER_BYTES = 64 * 1024;

    private final PhotoEditVersionRepository editVersionRepository;
    private final PhotoItemRepository photoItemRepository;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final FileDeletionService fileDeletionService;
    private final MediaSyncEventService syncEventService;
    private final PhotoSourceFileService sourceFileService;
    private final PhotoInputGuard inputGuard;
    private final StorageQuotaService storageQuotaService;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final PhotoThumbnailService photoThumbnailService;
    private final TransactionTemplate transactionTemplate;
    private final int maxHistoryVersions;

    /**
     * 同一时刻的编辑解码数上限。
     *
     * <p>单张 24MP 的整型画布约 96MB；512MB 堆下放开并发会让多张画布与 HTTP 线程
     * 同时驻留，触发 {@code ExitOnOutOfMemoryError}。槽位取不到时直接拒绝，不排队。</p>
     */
    private final Semaphore editSlots;

    public PhotoEditService(
            PhotoEditVersionRepository editVersionRepository,
            PhotoItemRepository photoItemRepository,
            DerivedAssetStorageService derivedAssetStorageService,
            FileDeletionService fileDeletionService,
            MediaSyncEventService syncEventService,
            PhotoSourceFileService sourceFileService,
            PhotoInputGuard inputGuard,
            StorageQuotaService storageQuotaService,
            FileMetadataQueryService fileMetadataQueryService,
            PhotoThumbnailService photoThumbnailService,
            TransactionTemplate transactionTemplate,
            @Value("${photo.edit.max-history-versions:5}") int maxHistoryVersions,
            @Value("${photo.edit.max-concurrent:2}") int maxConcurrentEdits) {
        this.editVersionRepository = editVersionRepository;
        this.photoItemRepository = photoItemRepository;
        this.derivedAssetStorageService = derivedAssetStorageService;
        this.fileDeletionService = fileDeletionService;
        this.syncEventService = syncEventService;
        this.sourceFileService = sourceFileService;
        this.inputGuard = inputGuard;
        this.storageQuotaService = storageQuotaService;
        this.fileMetadataQueryService = fileMetadataQueryService;
        this.photoThumbnailService = photoThumbnailService;
        this.transactionTemplate = transactionTemplate;
        this.maxHistoryVersions = maxHistoryVersions;
        this.editSlots = new Semaphore(Math.max(1, maxConcurrentEdits), true);
    }

    /**
     * 编辑版本产生的派生文件计入所有者个人配额。
     *
     * <p>派生资产默认不计个人配额，每日对账与彻底删除释放都排除
     * {@code source_type = 'DERIVED'}；编辑版本是用户显式生成且写入时已全额加计的例外，
     * 因此必须留在账本基数内，否则实时用量会长期高于重算结果、并在夜间被抹掉。
     * 该例外与 {@code FileMetricsRepository#sumFileSizeForUsers} 和
     * {@code FilePurgeStateService#isQuotaCountedNode} 的派生路径判定同源，三处必须同口径。</p>
     */
    private void chargeEditVersionQuota(UUID ownerUserId, long bytes) {
        storageQuotaService.chargeUsage(ownerUserId, bytes);
    }

    /**
     * 应用编辑操作，生成新版本。
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     * @param request 编辑请求
     * @return 新建编辑版本
     */
    public PhotoEditVersionDto applyEdit(UUID ownerUserId, UUID photoId, EditRequest request) {
        // 读取与校验不占用事务
        PhotoItem photo = photoItemRepository.findById(photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        if (!photo.getOwnerUserId().equals(ownerUserId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权编辑此照片");
        }

        // 二次编辑必须从当前活动的全分辨率文件起步：从 coverFileId 起步会把已经编辑过的照片
        // 反复压回缩略图分辨率（缩略图任务产出上限 1024px）。
        UUID sourceFileId = photo.activeOrSourceFileId();
        String fileName = photoId + "_edit_" + UUID.randomUUID() + ".jpg";

        // 图像解码、变换与对象存储写入在事务外执行
        StoredEdit stored = transformAndStore(
                ownerUserId,
                photoId,
                sourceFileId,
                fileName,
                request
        );

        return persistVersion(
                ownerUserId,
                photo,
                stored.fileId(),
                stored.thumbnailFileId(),
                stored.sizeBytes(),
                request.editType(),
                request.editParams()
        );
    }

    /**
     * 保存外部编辑器（如 Flutter 端 pro_image_editor）产出的整图结果为新版本。
     *
     * <p>与 {@link #applyEdit} 的参数式编辑不同，本方法直接接收编辑完成的
     * 图像流，不再在服务端做二次变换。请求体必须流式落盘：最高 128MiB 的图片
     * 先在 JVM 堆内分配 {@code byte[]} 时，512MB 堆下少量并发即可触发 OOM。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     * @param declaredBytes Content-Length；未知时为负数
     * @param imageStream 编辑后的图像流（JPEG）
     * @return 新增的编辑版本
     */
    public PhotoEditVersionDto applyEditedImage(
            UUID ownerUserId,
            UUID photoId,
            long declaredBytes,
            InputStream imageStream
    ) {
        PhotoItem photo = photoItemRepository.findById(photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        if (!photo.getOwnerUserId().equals(ownerUserId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权编辑此照片");
        }
        if (declaredBytes == 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "编辑结果为空");
        }
        if (declaredBytes > 0) {
            // 声明长度先挡一刀，避免明显超限的请求占用编辑槽位与磁盘带宽。
            inputGuard.validateFileSize(declaredBytes, false);
        }
        if (!editSlots.tryAcquire()) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "图像编辑任务过多，请稍后重试");
        }

        String fileName = photoId + "_edit_" + UUID.randomUUID() + ".jpg";
        UUID fileId;
        UUID thumbFileId = null;
        Path staged = null;
        long storedBytes;
        try {
            // 外部编辑器回传的字节未经任何内容校验：落对象存储前先按与 applyEdit 相同的
            // 魔数与像素上限复核，否则客户端可以自称 image/jpeg 写入任意内容。
            staged = Files.createTempFile("omninest-photo-edit-input-", ".jpg");
            storedBytes = copyBounded(imageStream, staged, inputGuard.maxFileBytes(false));
            inputGuard.validateFileSize(storedBytes, false);
            PhotoInputGuard.ImageDimensions dimensions = inputGuard.inspectForDecode(staged, fileName);
            inputGuard.validateDimensions(dimensions.width(), dimensions.height());
            fileId = derivedAssetStorageService.store(
                    ownerUserId,
                    "PHOTO_ITEM",
                    photoId,
                    "EDIT_VERSION",
                    fileName,
                    "image/jpeg",
                    staged
            );
            // 编辑产物同样生成 1024px 缩略图，网格/相册不能回退到全尺寸原图。
            thumbFileId = photoThumbnailService.generateAndStoreFile(
                    ownerUserId, fileId, staged, fileName);
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "照片编辑文件处理失败");
        } finally {
            deleteQuietly(staged);
            editSlots.release();
        }

        return persistVersion(
                ownerUserId,
                photo,
                fileId,
                thumbFileId,
                storedBytes,
                "EXTERNAL",
                Map.of("source", "pro_image_editor")
        );
    }

    /**
     * 在短事务内分配版本号、计入配额并保存版本与照片状态。
     *
     * <p>版本号与配额必须和版本行、照片指针在同一事务内提交。事务失败时已写入对象存储的
     * 派生文件必须回收，否则会留下配额未计但对象存在的孤儿资产。</p>
     */
    private PhotoEditVersionDto persistVersion(
            UUID ownerUserId,
            PhotoItem photo,
            UUID fileId,
            UUID thumbnailFileId,
            long sizeBytes,
            String editType,
            Map<String, Object> editParams
    ) {
        PhotoEditVersion version = new PhotoEditVersion();
        version.setOwnerUserId(ownerUserId);
        version.setPhotoId(photo.getId());
        version.setEditType(editType);
        version.setEditParams(editParams);
        version.setFileId(fileId);
        List<EvictedVersion> evicted = new ArrayList<>();
        try {
            transactionTemplate.executeWithoutResult(status -> {
                int versionNumber = nextVersionNumber(photo.getId());
                version.setVersionNumber(versionNumber);
                chargeEditVersionQuota(ownerUserId, sizeBytes);
                editVersionRepository.save(version);
                // 封面优先使用派生缩略图；生成失败时保留旧缩略图，不能把全尺寸编辑图写进列表。
                if (thumbnailFileId != null) {
                    photo.setCoverFileId(thumbnailFileId);
                }
                photo.setActiveFileId(fileId);
                photoItemRepository.save(photo);
                evicted.addAll(enforceMaxVersions(ownerUserId, photo.getId()));
                syncEventService.record(
                        ownerUserId,
                        SyncScope.PHOTOS,
                        "PHOTO_ITEM",
                        photo.getId().toString(),
                        SyncAction.UPDATED,
                        photo.getVersion(),
                        Map.of("editVersion", versionNumber)
                );
            });
        } catch (RuntimeException exception) {
            deleteDerivedQuietly(ownerUserId, fileId);
            deleteDerivedQuietly(ownerUserId, thumbnailFileId);
            throw exception;
        }
        // 对象存储删除必须等版本行提交后再做：事务回滚时版本仍指向这些文件，
        // 提前删对象只会留下指向空内容的版本记录。
        for (EvictedVersion item : evicted) {
            cleanupEvictedVersion(ownerUserId, item);
        }
        return toDto(version);
    }

    private void deleteDerivedQuietly(UUID ownerUserId, UUID fileId) {
        try {
            derivedAssetStorageService.deleteOwned(ownerUserId, fileId);
        } catch (RuntimeException exception) {
            log.warn("编辑事务失败后清理派生文件失败: fileId={}", fileId);
        }
    }

    /**
     * 列出照片的所有编辑版本。
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     * @return 编辑版本列表
     */
    @Transactional(readOnly = true)
    public List<PhotoEditVersionDto> listVersions(UUID ownerUserId, UUID photoId) {
        photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        return editVersionRepository.findByPhotoIdOrderByVersionNumberDesc(photoId)
                .stream()
                .map(this::toDto)
                .toList();
    }

    /**
     * 回滚到指定版本。
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     * @param versionId 编辑版本 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void revertToVersion(UUID ownerUserId, UUID photoId, UUID versionId) {
        PhotoEditVersion version = editVersionRepository.findByIdAndOwnerUserId(versionId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "版本不存在"));
        if (!version.getPhotoId().equals(photoId)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "版本与照片不匹配");
        }
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        photo.setCoverFileId(
                photoThumbnailService.findStoredThumbnailFileNodeId(ownerUserId, version.getFileId())
                        .orElse(photo.getCoverFileId()));
        photo.setActiveFileId(version.getFileId());
        photoItemRepository.save(photo);
        syncEventService.record(
                ownerUserId,
                SyncScope.PHOTOS,
                "PHOTO_ITEM",
                photoId.toString(),
                SyncAction.UPDATED,
                photo.getVersion(),
                Map.of("activeVersion", version.getVersionNumber())
        );
    }

    /**
     * 恢复未经编辑的原始照片。
     *
     * <p>非破坏性编辑的版本链不包含 v0，必须提供显式入口把活动指针清空并回退封面，
     * 否则用户首次编辑后无法回到原图。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void revertToOriginal(UUID ownerUserId, UUID photoId) {
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        photo.setActiveFileId(null);
        photo.setCoverFileId(
                photoThumbnailService.findStoredThumbnailFileNodeId(ownerUserId, photo.getFileNodeId())
                        .orElse(photo.getFileNodeId()));
        photoItemRepository.save(photo);
        syncEventService.record(
                ownerUserId,
                SyncScope.PHOTOS,
                "PHOTO_ITEM",
                photoId.toString(),
                SyncAction.UPDATED,
                photo.getVersion(),
                Map.of("activeVersion", 0)
        );
    }

    private StoredEdit transformAndStore(
            UUID ownerUserId,
            UUID photoId,
            UUID sourceFileId,
            String fileName,
            EditRequest request
    ) {
        if (!editSlots.tryAcquire()) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "图像编辑任务过多，请稍后重试");
        }
        Path editedFile = null;
        try (PhotoSourceFileService.StagedPhotoFile source = sourceFileService.stageOwned(
                ownerUserId,
                sourceFileId
        )) {
            inputGuard.inspectForDecode(source.path(), source.fileName());
            editedFile = Files.createTempFile("omninest-photo-edit-", ".jpg");
            if (!applyTransform(source.path(), editedFile, request.editType(), request.editParams())) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "编辑操作失败");
            }
            UUID fileId = derivedAssetStorageService.store(
                    ownerUserId,
                    "PHOTO_ITEM",
                    photoId,
                    "EDIT_VERSION",
                    fileName,
                    "image/jpeg",
                    editedFile
            );
            UUID thumbFileId = photoThumbnailService.generateAndStoreFile(
                    ownerUserId, fileId, editedFile, fileName);
            return new StoredEdit(fileId, thumbFileId, Files.size(editedFile));
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "照片编辑文件处理失败");
        } finally {
            deleteQuietly(editedFile);
            editSlots.release();
        }
    }

    private boolean applyTransform(
            Path imageFile,
            Path outputFile,
            String editType,
            Map<String, Object> params
    ) {
        try {
            EditSource source = readForEdit(imageFile);
            if (source == null) {
                return false;
            }
            // 统一转成三通道 RGB 画布：索引色 PNG/GIF 的 type 为 0 或 TYPE_BYTE_INDEXED，
            // 直接构造同类型画布或套单表 LookupOp 会抛 ImagingOpException。
            BufferedImage image = PhotoEditImageOps.copyToIntRgb(source.image());
            BufferedImage result = switch (editType.toUpperCase()) {
                case "ROTATE" -> applyRotation(image, params);
                case "CROP" -> applyCrop(image, params, source.subsample());
                case "BRIGHTNESS" -> PhotoEditImageOps.applyBrightness(image, params);
                case "CONTRAST" -> PhotoEditImageOps.applyContrast(image, params);
                case "FILTER" -> PhotoEditImageOps.applyFilter(image, params);
                case "SATURATION" -> PhotoEditImageOps.applySaturation(image, params);
                default -> throw new BusinessException(ErrorCode.PARAM_ERROR, "不支持的编辑类型: " + editType);
            };
            inputGuard.validateDimensions(result.getWidth(), result.getHeight());
            // 带透明通道的源图（PNG/WebP 解码为 ARGB）无法直接写 JPEG：OpenJDK 的 JPEG writer
            // 不支持含 Alpha 的色彩空间，ImageIO.write 会直接返回 false，表现为「编辑操作失败」。
            return ImageIO.write(PhotoEditImageOps.ensureOpaqueRgb(result), "jpg", outputFile.toFile());
        } catch (BusinessException ex) {
            throw ex;
        } catch (Exception ex) {
            log.warn("图片编辑失败: editType={}, error={}", editType, ex.getMessage());
            return false;
        }
    }

    /**
     * 按需抽样解码编辑源图。
     *
     * <p>超过 {@link #MAX_EDIT_DECODE_PIXELS} 时用 ImageReadParam 在解码阶段抽样，
     * 不先展开全尺寸 BufferedImage；返回的 subsample 供裁剪坐标换算。</p>
     */
    private EditSource readForEdit(Path imageFile) throws IOException {
        try (ImageInputStream input = ImageIO.createImageInputStream(imageFile.toFile())) {
            if (input == null) {
                return null;
            }
            Iterator<ImageReader> readers = ImageIO.getImageReaders(input);
            if (!readers.hasNext()) {
                return null;
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(input, true, true);
                int width = reader.getWidth(0);
                int height = reader.getHeight(0);
                long pixels = (long) width * height;
                int step = 1;
                while (pixels / ((long) step * step) > MAX_EDIT_DECODE_PIXELS) {
                    step++;
                }
                ImageReadParam param = reader.getDefaultReadParam();
                if (step > 1) {
                    param.setSourceSubsampling(step, step, 0, 0);
                }
                return new EditSource(reader.read(0, param), step);
            } finally {
                reader.dispose();
            }
        }
    }

    private record EditSource(BufferedImage image, int subsample) {
    }

    private record StoredEdit(UUID fileId, UUID thumbnailFileId, long sizeBytes) {
    }

    /**
     * 带字节上限地把请求体写入临时文件，超限立即失败，不在堆内缓冲整张图。
     */
    private long copyBounded(InputStream input, Path target, long maxBytes) throws IOException {
        if (input == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "编辑结果为空");
        }
        byte[] buffer = new byte[COPY_BUFFER_BYTES];
        long totalBytes = 0;
        try (OutputStream output = Files.newOutputStream(target)) {
            int readBytes;
            while ((readBytes = input.read(buffer)) >= 0) {
                if (readBytes == 0) {
                    continue;
                }
                totalBytes += readBytes;
                if (totalBytes > maxBytes) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR, "照片文件大小超出限制");
                }
                output.write(buffer, 0, readBytes);
            }
        }
        if (totalBytes == 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "编辑结果为空");
        }
        return totalBytes;
    }

    private void deleteQuietly(Path file) {
        if (file == null) {
            return;
        }
        try {
            Files.deleteIfExists(file);
        } catch (IOException exception) {
            log.debug("照片编辑临时文件清理失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    private BufferedImage applyRotation(BufferedImage image, Map<String, Object> params) {
        double angle = ((Number) params.getOrDefault("angle", 90)).doubleValue();
        // 90/270 度旋转交换画布宽高，避免角落被原尺寸画布裁掉。
        long turns = Math.round(Math.abs(angle) / 90.0);
        if (turns % 2 == 1) {
            boolean clockwise = angle > 0;
            BufferedImage rotated = new BufferedImage(
                    image.getHeight(), image.getWidth(), image.getType());
            Graphics2D g = rotated.createGraphics();
            if (clockwise) {
                g.translate(rotated.getWidth(), 0);
                g.rotate(Math.toRadians(90));
            } else {
                g.translate(0, rotated.getHeight());
                g.rotate(Math.toRadians(-90));
            }
            g.drawImage(image, 0, 0, null);
            g.dispose();
            return rotated;
        }
        double radians = Math.toRadians(angle);
        AffineTransform transform = AffineTransform.getRotateInstance(radians,
                image.getWidth() / 2.0, image.getHeight() / 2.0);
        AffineTransformOp op = new AffineTransformOp(transform, AffineTransformOp.TYPE_BILINEAR);
        return op.filter(image, null);
    }

    private BufferedImage applyCrop(BufferedImage image, Map<String, Object> params, int subsample) {
        int scale = Math.max(1, subsample);
        int x = ((Number) params.getOrDefault("x", 0)).intValue() / scale;
        int y = ((Number) params.getOrDefault("y", 0)).intValue() / scale;
        int w = ((Number) params.getOrDefault("width", image.getWidth() * scale)).intValue() / scale;
        int h = ((Number) params.getOrDefault("height", image.getHeight() * scale)).intValue() / scale;
        x = Math.max(0, Math.min(x, image.getWidth() - 1));
        y = Math.max(0, Math.min(y, image.getHeight() - 1));
        w = Math.max(1, Math.min(w, image.getWidth() - x));
        h = Math.max(1, Math.min(h, image.getHeight() - y));
        return image.getSubimage(x, y, w, h);
    }

    private List<EvictedVersion> enforceMaxVersions(UUID ownerUserId, UUID photoId) {
        List<PhotoEditVersion> versions = editVersionRepository.findByPhotoIdOrderByVersionNumberDesc(photoId);
        if (versions.size() <= maxHistoryVersions) {
            return List.of();
        }
        List<PhotoEditVersion> toDelete = new ArrayList<>(versions.subList(maxHistoryVersions, versions.size()));
        List<EvictedVersion> evicted = new ArrayList<>(toDelete.size());
        for (PhotoEditVersion version : toDelete) {
            if (version.getFileId() == null) {
                continue;
            }
            long sizeBytes = fileMetadataQueryService.findById(version.getFileId())
                    .map(FileDescriptor::sizeBytes)
                    .orElse(0L);
            UUID thumbnailFileId = photoThumbnailService
                    .findStoredThumbnailFileNodeId(ownerUserId, version.getFileId())
                    .orElse(null);
            evicted.add(new EvictedVersion(photoId, version.getFileId(), thumbnailFileId, sizeBytes));
        }
        editVersionRepository.deleteAll(toDelete);
        return evicted;
    }

    /**
     * 事务提交后回收被淘汰版本的主图与派生缩略图。
     *
     * <p>配额只在主图节点确实删除成功后按写入口径扣减；删除失败保留用量，
     * 交给每日对账重算，避免与对账重复扣减。</p>
     */
    private void cleanupEvictedVersion(UUID ownerUserId, EvictedVersion evicted) {
        boolean deleted = deleteEvictedNode(
                ownerUserId, evicted.photoId(), evicted.fileId(), "主图");
        if (evicted.thumbnailFileId() != null) {
            deleteEvictedNode(
                    ownerUserId, evicted.photoId(), evicted.thumbnailFileId(), "缩略图");
        }
        if (deleted && evicted.sizeBytes() > 0) {
            try {
                storageQuotaService.decrementUsage(ownerUserId, evicted.sizeBytes());
            } catch (RuntimeException ex) {
                log.warn("旧编辑版本配额退还失败: fileId={}", evicted.fileId(), ex);
            }
        }
    }

    /**
     * 删除被淘汰版本的派生节点；对象存储失败时登记 FILE_PURGE 补偿任务，
     * 由任务重试与每日配额对账兜底，避免节点永久失去清理线索。
     */
    private boolean deleteEvictedNode(UUID ownerUserId, UUID photoId, UUID fileId, String assetLabel) {
        try {
            return derivedAssetStorageService.deleteOwned(ownerUserId, fileId);
        } catch (RuntimeException ex) {
            log.warn("旧编辑版本{}清理失败，登记补偿任务: fileId={}", assetLabel, fileId, ex);
            try {
                fileDeletionService.deletePermanently(
                        ownerUserId,
                        fileId,
                        false,
                        new FilePurgeOrigin("PHOTOS", photoId),
                        null
                );
                log.warn("旧编辑版本{}已登记补偿清理任务: fileId={}", assetLabel, fileId);
            } catch (RuntimeException scheduleFailure) {
                log.error("旧编辑版本{}补偿任务登记失败，需依赖后续对账清理: ownerUserId={}, photoId={}, fileId={}",
                        assetLabel, ownerUserId, photoId, fileId, scheduleFailure);
            }
            return false;
        }
    }

    /**
     * 被淘汰版本的待清理资产。
     *
     * @param photoId 所属照片 ID
     * @param fileId 主图节点 ID
     * @param thumbnailFileId 缩略图节点 ID，可为 null
     * @param sizeBytes 主图字节数
     */
    private record EvictedVersion(
            UUID photoId,
            UUID fileId,
            UUID thumbnailFileId,
            long sizeBytes
    ) {
    }

    /**
     * 计算下一个编辑版本号。
     *
     * <p>必须取现存最大版本号加一，不能用「条数 + 1」：保留上限会裁掉最早的版本，
     * 裁满后条数恒等于上限，算出的版本号反复撞在同一个值上，版本列表排序与回滚标识随之错乱。</p>
     *
     * @param photoId 照片 ID
     * @return 下一个版本号
     */
    private int nextVersionNumber(UUID photoId) {
        return editVersionRepository.findFirstByPhotoIdOrderByVersionNumberDesc(photoId)
                .map(version -> version.getVersionNumber() + 1)
                .orElse(1);
    }

    private PhotoEditVersionDto toDto(PhotoEditVersion version) {
        return new PhotoEditVersionDto(
                version.getId(),
                version.getVersionNumber(),
                version.getEditType(),
                version.getEditParams(),
                version.getCreatedAt()
        );
    }
}
