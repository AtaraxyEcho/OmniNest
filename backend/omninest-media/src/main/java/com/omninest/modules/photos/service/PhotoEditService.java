package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.domain.PhotoEditVersion;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.dto.PhotoDtos.EditRequest;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoEditVersionDto;
import com.omninest.modules.photos.repository.PhotoEditVersionRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.geom.AffineTransform;
import java.awt.image.AffineTransformOp;
import java.awt.image.BufferedImage;
import java.awt.image.ByteLookupTable;
import java.awt.image.ConvolveOp;
import java.awt.image.DataBufferInt;
import java.awt.image.Kernel;
import java.awt.image.LookupOp;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
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

    private final PhotoEditVersionRepository editVersionRepository;
    private final PhotoItemRepository photoItemRepository;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final MediaSyncEventService syncEventService;
    private final PhotoSourceFileService sourceFileService;
    private final PhotoInputGuard inputGuard;
    private final StorageQuotaService storageQuotaService;
    private final FileMetadataQueryService fileMetadataQueryService;
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
            MediaSyncEventService syncEventService,
            PhotoSourceFileService sourceFileService,
            PhotoInputGuard inputGuard,
            StorageQuotaService storageQuotaService,
            FileMetadataQueryService fileMetadataQueryService,
            TransactionTemplate transactionTemplate,
            @Value("${photo.edit.max-history-versions:5}") int maxHistoryVersions,
            @Value("${photo.edit.max-concurrent:2}") int maxConcurrentEdits) {
        this.editVersionRepository = editVersionRepository;
        this.photoItemRepository = photoItemRepository;
        this.derivedAssetStorageService = derivedAssetStorageService;
        this.syncEventService = syncEventService;
        this.sourceFileService = sourceFileService;
        this.inputGuard = inputGuard;
        this.storageQuotaService = storageQuotaService;
        this.fileMetadataQueryService = fileMetadataQueryService;
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
        storageQuotaService.checkQuota(ownerUserId, bytes);
        storageQuotaService.incrementUsage(ownerUserId, bytes);
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

        int nextVersion = nextVersionNumber(photoId);
        String fileName = photoId + "_v" + nextVersion + ".jpg";
        // 二次编辑必须从当前活动的全分辨率文件起步：从 coverFileId 起步会把已经编辑过的照片
        // 反复压回缩略图分辨率（缩略图任务产出上限 1024px）。
        UUID sourceFileId = photo.activeOrSourceFileId();

        // 图像解码、变换与对象存储写入在事务外执行
        UUID fileId = transformAndStore(
                ownerUserId,
                photoId,
                sourceFileId,
                fileName,
                request
        );

        // DB 持久化使用短事务
        PhotoEditVersion version = new PhotoEditVersion();
        version.setOwnerUserId(ownerUserId);
        version.setPhotoId(photoId);
        version.setVersionNumber(nextVersion);
        version.setEditType(request.editType());
        version.setEditParams(request.editParams());
        version.setFileId(fileId);
        transactionTemplate.executeWithoutResult(status -> {
            editVersionRepository.save(version);
            photo.setCoverFileId(fileId);
            photo.setActiveFileId(fileId);
            photoItemRepository.save(photo);
            enforceMaxVersions(ownerUserId, photoId);
            syncEventService.record(
                    ownerUserId,
                    SyncScope.PHOTOS,
                    "PHOTO_ITEM",
                    photoId.toString(),
                    SyncAction.UPDATED,
                    photo.getVersion(),
                    Map.of("editVersion", nextVersion)
            );
        });

        return toDto(version);
    }

    /**
     * 保存外部编辑器（如 Flutter 端 pro_image_editor）产出的整图结果为新版本。
     *
     * <p>与 {@link #applyEdit} 的参数式编辑不同，本方法直接接收编辑完成的
     * 图像字节，不再在服务端做二次变换。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     * @param image 编辑后的图像字节（JPEG）
     * @return 新增的编辑版本
     */
    public PhotoEditVersionDto applyEditedImage(
            UUID ownerUserId,
            UUID photoId,
            byte[] image
    ) {
        PhotoItem photo = photoItemRepository.findById(photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        if (!photo.getOwnerUserId().equals(ownerUserId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权编辑此照片");
        }
        if (image == null || image.length == 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "编辑结果为空");
        }

        int nextVersion = nextVersionNumber(photoId);
        String fileName = photoId + "_v" + nextVersion + ".jpg";
        inputGuard.validateFileSize(image.length, false);

        UUID fileId;
        Path staged = null;
        try {
            // 外部编辑器回传的字节未经任何内容校验：落对象存储前先按与 applyEdit 相同的
            // 魔数与像素上限复核，否则客户端可以自称 image/jpeg 写入任意内容。
            staged = Files.createTempFile("omninest-photo-edit-input-", ".jpg");
            Files.write(staged, image);
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
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "照片编辑文件处理失败");
        } finally {
            deleteQuietly(staged);
        }
        chargeEditVersionQuota(ownerUserId, image.length);

        PhotoEditVersion version = new PhotoEditVersion();
        version.setOwnerUserId(ownerUserId);
        version.setPhotoId(photoId);
        version.setVersionNumber(nextVersion);
        version.setEditType("EXTERNAL");
        version.setEditParams(Map.of("source", "pro_image_editor"));
        version.setFileId(fileId);

        transactionTemplate.executeWithoutResult(status -> {
            editVersionRepository.save(version);
            photo.setCoverFileId(fileId);
            photo.setActiveFileId(fileId);
            photoItemRepository.save(photo);
            enforceMaxVersions(ownerUserId, photoId);
            syncEventService.record(
                    ownerUserId,
                    SyncScope.PHOTOS,
                    "PHOTO_ITEM",
                    photoId.toString(),
                    SyncAction.UPDATED,
                    photo.getVersion(),
                    Map.of("editVersion", nextVersion)
            );
        });

        return toDto(version);
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
        PhotoItem photo = photoItemRepository.findById(photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        photo.setCoverFileId(version.getFileId());
        photo.setActiveFileId(version.getFileId());
        photoItemRepository.save(photo);
    }

    private UUID transformAndStore(
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
            chargeEditVersionQuota(ownerUserId, Files.size(editedFile));
            return fileId;
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
            BufferedImage image = source.image();
            BufferedImage result = switch (editType.toUpperCase()) {
                case "ROTATE" -> applyRotation(image, params);
                case "CROP" -> applyCrop(image, params, source.subsample());
                case "BRIGHTNESS" -> applyBrightness(image, params);
                case "CONTRAST" -> applyContrast(image, params);
                case "FILTER" -> applyFilter(image, params);
                case "SATURATION" -> applySaturation(image, params);
                default -> throw new BusinessException(ErrorCode.PARAM_ERROR, "不支持的编辑类型: " + editType);
            };
            inputGuard.validateDimensions(result.getWidth(), result.getHeight());
            // 带透明通道的源图（PNG/WebP 解码为 ARGB）无法直接写 JPEG：OpenJDK 的 JPEG writer
            // 不支持含 Alpha 的色彩空间，ImageIO.write 会直接返回 false，表现为「编辑操作失败」。
            return ImageIO.write(ensureOpaqueRgb(result), "jpg", outputFile.toFile());
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

    /**
     * 在 ARGB/RGB 整型画布上逐像素处理，避免 getRGB/setRGB 的逐点颜色模型转换。
     */
    private BufferedImage copyToIntRgb(BufferedImage image) {
        BufferedImage result = new BufferedImage(
                image.getWidth(), image.getHeight(), BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = result.createGraphics();
        try {
            graphics.drawImage(image, 0, 0, null);
        } finally {
            graphics.dispose();
        }
        return result;
    }

    private int[] pixelData(BufferedImage image) {
        return ((DataBufferInt) image.getRaster().getDataBuffer()).getData();
    }

    /**
     * 将可能含透明通道的图像铺到白色底上转成 RGB。
     *
     * <p>裁剪、亮度、对比度与卷积滤镜都保留源图类型，只有 saturation/灰度/怀旧分支自带 RGB 画布，
     * 因此写出前统一兜一次。</p>
     */
    private BufferedImage ensureOpaqueRgb(BufferedImage image) {
        if (!image.getColorModel().hasAlpha()) {
            return image;
        }
        BufferedImage rgb = new BufferedImage(
                image.getWidth(), image.getHeight(), BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = rgb.createGraphics();
        try {
            graphics.setColor(Color.WHITE);
            graphics.fillRect(0, 0, image.getWidth(), image.getHeight());
            graphics.drawImage(image, 0, 0, null);
        } finally {
            graphics.dispose();
        }
        return rgb;
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

    /** 饱和度调整：factor 1 为原图，0 为灰度，2 为两倍饱和度。 */
    private BufferedImage applySaturation(BufferedImage image, Map<String, Object> params) {
        float factor = ((Number) params.getOrDefault("factor", 1.0f)).floatValue();
        BufferedImage result = copyToIntRgb(image);
        int[] pixels = pixelData(result);
        for (int index = 0; index < pixels.length; index++) {
            int rgb = pixels[index];
            int r = (rgb >> 16) & 0xFF;
            int g = (rgb >> 8) & 0xFF;
            int b = rgb & 0xFF;
            float gray = 0.299f * r + 0.587f * g + 0.114f * b;
            int nr = clampColor(Math.round(gray + (r - gray) * factor));
            int ng = clampColor(Math.round(gray + (g - gray) * factor));
            int nb = clampColor(Math.round(gray + (b - gray) * factor));
            pixels[index] = (nr << 16) | (ng << 8) | nb;
        }
        return result;
    }

    private int clampColor(int value) {
        return Math.min(255, Math.max(0, value));
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

    private BufferedImage applyBrightness(BufferedImage image, Map<String, Object> params) {
        float factor = ((Number) params.getOrDefault("factor", 1.0f)).floatValue();
        byte[] lookup = new byte[256];
        for (int i = 0; i < 256; i++) {
            lookup[i] = (byte) Math.min(255, Math.max(0, (int) (i * factor)));
        }
        LookupOp op = new LookupOp(new ByteLookupTable(0, lookup), null);
        return op.filter(image, null);
    }

    private BufferedImage applyContrast(BufferedImage image, Map<String, Object> params) {
        float factor = ((Number) params.getOrDefault("factor", 1.0f)).floatValue();
        byte[] lookup = new byte[256];
        for (int i = 0; i < 256; i++) {
            int val = (int) (((i - 128) * factor) + 128);
            lookup[i] = (byte) Math.min(255, Math.max(0, val));
        }
        LookupOp op = new LookupOp(new ByteLookupTable(0, lookup), null);
        return op.filter(image, null);
    }

    private BufferedImage applyFilter(BufferedImage image, Map<String, Object> params) {
        String filterName = (String) params.getOrDefault("name", "none");
        return switch (filterName.toLowerCase()) {
            case "grayscale" -> applyGrayscale(image);
            case "sepia" -> applySepia(image);
            case "blur" -> applyBlur(image);
            case "sharpen" -> applySharpen(image);
            default -> image;
        };
    }

    private BufferedImage applyGrayscale(BufferedImage image) {
        BufferedImage result = copyToIntRgb(image);
        int[] pixels = pixelData(result);
        for (int index = 0; index < pixels.length; index++) {
            int rgb = pixels[index];
            int r = (rgb >> 16) & 0xFF;
            int g = (rgb >> 8) & 0xFF;
            int b = rgb & 0xFF;
            int gray = (int) (0.299 * r + 0.587 * g + 0.114 * b);
            pixels[index] = (gray << 16) | (gray << 8) | gray;
        }
        return result;
    }

    private BufferedImage applySepia(BufferedImage image) {
        BufferedImage result = copyToIntRgb(image);
        int[] pixels = pixelData(result);
        for (int index = 0; index < pixels.length; index++) {
            int rgb = pixels[index];
            int r = (rgb >> 16) & 0xFF;
            int g = (rgb >> 8) & 0xFF;
            int b = rgb & 0xFF;
            int newR = Math.min(255, (int) (0.393 * r + 0.769 * g + 0.189 * b));
            int newG = Math.min(255, (int) (0.349 * r + 0.686 * g + 0.168 * b));
            int newB = Math.min(255, (int) (0.272 * r + 0.534 * g + 0.131 * b));
            pixels[index] = (newR << 16) | (newG << 8) | newB;
        }
        return result;
    }

    private BufferedImage applyBlur(BufferedImage image) {
        float[] kernel = {
                1f / 9, 1f / 9, 1f / 9,
                1f / 9, 1f / 9, 1f / 9,
                1f / 9, 1f / 9, 1f / 9
        };
        ConvolveOp op = new ConvolveOp(new Kernel(3, 3, kernel), ConvolveOp.EDGE_NO_OP, null);
        return op.filter(image, null);
    }

    private BufferedImage applySharpen(BufferedImage image) {
        float[] kernel = {
                0, -1, 0,
                -1, 5, -1,
                0, -1, 0
        };
        ConvolveOp op = new ConvolveOp(new Kernel(3, 3, kernel), ConvolveOp.EDGE_NO_OP, null);
        return op.filter(image, null);
    }

    private void enforceMaxVersions(UUID ownerUserId, UUID photoId) {
        List<PhotoEditVersion> versions = editVersionRepository.findByPhotoIdOrderByVersionNumberDesc(photoId);
        if (versions.size() <= maxHistoryVersions) {
            return;
        }
        List<PhotoEditVersion> toDelete = versions.subList(maxHistoryVersions, versions.size());
        // 同步清理已删除版本的派生文件，避免 MinIO 孤儿对象。
        for (PhotoEditVersion version : toDelete) {
            refundDeletedVersionQuota(ownerUserId, version);
        }
        editVersionRepository.deleteAll(toDelete);
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

    /**
     * 物理删除超出保留上限的派生版本节点，并按写入时加计的字节退还配额。
     *
     * <p>写入时 {@code chargeEditVersionQuota} 对派生节点全额加计，节点被物理删除后
     * 不再进入 {@code sumFileSizeForUsers} 重算基数；此处必须在节点确实删除成功后按同一
     * 口径扣减，否则实时用量长期虚高。删除失败或节点缺失时不退还，避免与每日对账重复扣减。</p>
     */
    private void refundDeletedVersionQuota(UUID ownerUserId, PhotoEditVersion version) {
        if (version.getFileId() == null) {
            return;
        }
        long sizeBytes = fileMetadataQueryService.findById(version.getFileId())
                .map(FileDescriptor::sizeBytes)
                .orElse(0L);
        boolean deleted;
        try {
            deleted = derivedAssetStorageService.deleteOwned(ownerUserId, version.getFileId());
        } catch (RuntimeException ex) {
            log.warn("旧编辑版本派生文件清理失败: versionId={}, fileId={}",
                    version.getId(), version.getFileId(), ex);
            return;
        }
        if (deleted && sizeBytes > 0) {
            storageQuotaService.decrementUsage(ownerUserId, sizeBytes);
        }
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
