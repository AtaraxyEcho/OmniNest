package com.omninest.modules.photos.service;

import com.omninest.common.ai.ImageAnalysisGateway;
import com.omninest.common.ai.ImageAnalysisGateway.ContentAnalysis;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.coobird.thumbnailator.Thumbnails;
import org.springframework.stereotype.Service;

/**
 * 照片图像分析服务。
 * 负责 OCR 与视觉标签的编排、原图哈希幂等短路和大图下采样。
 * 始终注册为 Bean，由调用方通过 PhotosRuntimeConfigService.isAiEnabled() 做运行时开关检查。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoAiService {

    public static final String EXPECTED_OCR_VERSION = PhotoContentAnalysisService.EXPECTED_OCR_VERSION;
    public static final String OCR_LAYOUT_SOURCE = PhotoContentAnalysisService.OCR_LAYOUT_SOURCE;

    private static final String HINT_AUTO = "AUTO";
    private static final String HINT_TEXT_GRAPHIC = "TEXT_GRAPHIC";
    private static final String HINT_NATURAL_PHOTO = "NATURAL_PHOTO";
    private static final long MAX_DIRECT_ORIGINAL_BYTES = 2L * 1024 * 1024;
    private static final long MAX_DOWNSAMPLE_SOURCE_BYTES = 32L * 1024 * 1024;
    private static final int MAX_DIRECT_ORIGINAL_SIDE = 2560;
    private static final int OCR_DOWNSAMPLE_MAX_SIDE = 2048;
    private static final double OCR_DOWNSAMPLE_QUALITY = 0.82;

    private final ImageAnalysisGateway imageAnalysisGateway;
    private final PhotoLabelPolicy labelPolicy;
    private final PhotoContentAnalysisService contentAnalysisService;
    private final PhotosRuntimeConfigService configService;
    private final PhotoItemRepository photoItemRepository;
    private final PhotoFileDetector fileDetector;
    private final FileQueryService fileQueryService;
    private final FileLifecycleGuard fileLifecycleGuard;

    /**
     * 处理单张照片：OCR、视觉标签、幂等短路与索引投递。
     *
     * @param ownerUserId 所属用户标识
     * @param photoId 照片标识
     * @param triggerImmediateIndex 成功后是否立即投递单图搜索索引
     */
    public void processPhoto(UUID ownerUserId, UUID photoId, boolean triggerImmediateIndex) {
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "照片不存在"));
        requirePhotoProcessable(ownerUserId, photo);

        String originalContentHash = contentHash(photo);
        String expectedPipeline = configService.expectedPipelineVersion();
        if (expectedPipeline != null
                && contentAnalysisService.isAlreadyAnalyzed(
                        ownerUserId,
                        photoId,
                        originalContentHash,
                        expectedPipeline
                )) {
            return;
        }
        if (originalContentHash != null && expectedPipeline != null && contentAnalysisService.tryCloneFromSameHash(
                ownerUserId,
                photo,
                originalContentHash,
                expectedPipeline,
                triggerImmediateIndex
        )) {
            log.info("相同原图哈希命中分析克隆: photoId={}", photoId);
            return;
        }

        boolean skipOcr = isOcrAlreadyUpToDate(photo);
        if (skipOcr && expectedPipeline != null && contentAnalysisService.tryShortCircuitDenseTextReanalysis(
                ownerUserId,
                photo,
                expectedPipeline,
                triggerImmediateIndex
        )) {
            log.info("密集文本照片继承 OCR 标签完成重分析: photoId={}", photoId);
            return;
        }

        String hint = computeAnalysisHint(photo);
        byte[] imageBytes = readAnalysisImageBytes(ownerUserId, photo, skipOcr);
        ContentAnalysis analysis = imageAnalysisGateway.analyzeContent(
                imageBytes,
                photoId + ".jpg",
                hint,
                skipOcr,
                configService.aiEndpoint(),
                configService.aiTimeoutSeconds()
        );
        requireValidAnalysis(analysis);

        ContentAnalysis mergedAnalysis = skipOcr
                ? contentAnalysisService.mergePreservedOcrObservations(ownerUserId, photoId, analysis)
                : analysis;
        List<PhotoLabelPolicy.PhotoLabel> labels = labelPolicy.classify(mergedAnalysis);
        contentAnalysisService.apply(
                ownerUserId,
                photoId,
                mergedAnalysis,
                labels,
                skipOcr,
                triggerImmediateIndex
        );
        log.info(
                "照片图像分析完成: photoId={}, skipOcr={}, labelCount={}, ocrTextLength={}",
                photoId,
                skipOcr,
                labels.size(),
                mergedAnalysis.ocrText() == null ? 0 : mergedAnalysis.ocrText().length()
        );
    }

    private boolean isOcrAlreadyUpToDate(PhotoItem photo) {
        if (photo.getProviderMetadata() == null) {
            return false;
        }
        Object version = photo.getProviderMetadata().get("ocrPipelineVersion");
        return EXPECTED_OCR_VERSION.equals(String.valueOf(version));
    }

    private String computeAnalysisHint(PhotoItem photo) {
        if (photo.getCameraMake() != null && !photo.getCameraMake().isBlank()) {
            return HINT_NATURAL_PHOTO;
        }
        String format = photo.getFormat() == null ? "" : photo.getFormat().toLowerCase(Locale.ROOT);
        if ("png".equals(format)) {
            return HINT_TEXT_GRAPHIC;
        }
        return HINT_AUTO;
    }

    private byte[] readAnalysisImageBytes(UUID ownerUserId, PhotoItem photo, boolean skipOcr) {
        if (skipOcr) {
            return readCompactImage(ownerUserId, photo);
        }
        if (photo.getFileNodeId() == null || isRaw(photo)) {
            return readCover(ownerUserId, photo);
        }
        if (photo.getFileSize() > MAX_DOWNSAMPLE_SOURCE_BYTES && photo.getCoverFileId() != null) {
            return readCover(ownerUserId, photo);
        }
        byte[] original = readFileBytes(ownerUserId, photo.getFileNodeId(), "照片原图");
        try {
            return maybeDownsample(photo, original);
        } catch (RuntimeException exception) {
            if (photo.getCoverFileId() == null) {
                throw exception;
            }
            log.warn("原图无法解码为分析输入，回退封面: photoId={}, errorType={}",
                    photo.getId(), exception.getClass().getSimpleName());
            return readCover(ownerUserId, photo);
        }
    }

    private byte[] readCompactImage(UUID ownerUserId, PhotoItem photo) {
        if (photo.getCoverFileId() != null) {
            return readFileBytes(ownerUserId, photo.getCoverFileId(), "照片封面");
        }
        if (photo.getFileNodeId() == null) {
            throw dependencyNotReady();
        }
        return maybeDownsample(photo, readFileBytes(ownerUserId, photo.getFileNodeId(), "照片原图"));
    }

    private byte[] readCover(UUID ownerUserId, PhotoItem photo) {
        if (photo.getCoverFileId() == null) {
            throw dependencyNotReady();
        }
        return readFileBytes(ownerUserId, photo.getCoverFileId(), "照片封面");
    }

    private boolean isRaw(PhotoItem photo) {
        String format = photo.getFormat();
        return format != null && fileDetector.isRaw("photo." + format);
    }

    private byte[] maybeDownsample(PhotoItem photo, byte[] original) {
        long longSide = resolveLongSide(photo, original);
        if (original.length <= MAX_DIRECT_ORIGINAL_BYTES && longSide <= MAX_DIRECT_ORIGINAL_SIDE) {
            return original;
        }
        return downsample(original);
    }

    private long resolveLongSide(PhotoItem photo, byte[] imageBytes) {
        if (photo.getWidth() != null && photo.getHeight() != null) {
            return Math.max(photo.getWidth(), photo.getHeight());
        }
        try (ImageInputStream imageInput = ImageIO.createImageInputStream(
                new ByteArrayInputStream(imageBytes))) {
            if (imageInput == null) {
                return Long.MAX_VALUE;
            }
            var readers = ImageIO.getImageReaders(imageInput);
            if (!readers.hasNext()) {
                return Long.MAX_VALUE;
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(imageInput, true, true);
                return Math.max(reader.getWidth(0), reader.getHeight(0));
            } finally {
                reader.dispose();
            }
        } catch (IOException exception) {
            return Long.MAX_VALUE;
        }
    }

    private byte[] downsample(byte[] original) {
        try {
            ByteArrayOutputStream output = new ByteArrayOutputStream(
                    Math.min(original.length, 1024 * 1024));
            Thumbnails.of(new ByteArrayInputStream(original))
                    .size(OCR_DOWNSAMPLE_MAX_SIDE, OCR_DOWNSAMPLE_MAX_SIDE)
                    .keepAspectRatio(true)
                    .outputFormat("jpg")
                    .outputQuality(OCR_DOWNSAMPLE_QUALITY)
                    .toOutputStream(output);
            return output.toByteArray();
        } catch (IOException exception) {
            throw new IllegalStateException("照片分析图像下采样失败", exception);
        }
    }

    private byte[] readFileBytes(UUID ownerUserId, UUID fileId, String description) {
        long maxImageBytes = imageAnalysisGateway.maxImageBytes();
        try (FileContentStream content = fileQueryService.openOwnedFileContent(ownerUserId, fileId)) {
            if (content.sizeBytes() > maxImageBytes) {
                log.warn(
                        "照片超过图像分析输入限制: fileId={}, sizeBytes={}, maxBytes={}",
                        fileId,
                        content.sizeBytes(),
                        maxImageBytes
                );
                throw new IllegalStateException(description + "超过图像分析输入大小限制");
            }
            ByteArrayOutputStream output = new ByteArrayOutputStream(
                    (int) Math.min(Math.max(content.sizeBytes(), 0), 8L * 1024 * 1024));
            byte[] chunk = new byte[8192];
            long totalBytes = 0;
            int bytesRead;
            try (InputStream stream = content.inputStream()) {
                while ((bytesRead = stream.read(chunk)) != -1) {
                    totalBytes += bytesRead;
                    if (totalBytes > maxImageBytes) {
                        throw new IllegalStateException(description + "超过图像分析输入大小限制");
                    }
                    output.write(chunk, 0, bytesRead);
                }
            }
            if (totalBytes == 0) {
                throw new IllegalStateException(description + "为空");
            }
            return output.toByteArray();
        } catch (BusinessException exception) {
            throw exception;
        } catch (IOException exception) {
            log.warn("读取{}失败: fileId={}", description, fileId, exception);
            throw new IllegalStateException("读取" + description + "失败", exception);
        }
    }

    private BusinessException dependencyNotReady() {
        // 封面由异步缩略图任务回填，导入后短暂缺失属预期；按依赖未就绪
        // 抛出以进入短间隔重试，与真实分析失败区分。
        return new BusinessException(
                ErrorCode.TASK_DEPENDENCY_NOT_READY,
                "照片封面尚未生成，等待缩略图任务回填"
        );
    }

    private void requirePhotoProcessable(UUID ownerUserId, PhotoItem photo) {
        fileLifecycleGuard.requireOwnedWritable(ownerUserId, photo.getFileNodeId());
        UUID coverFileId = photo.getCoverFileId();
        if (coverFileId != null && !coverFileId.equals(photo.getFileNodeId())) {
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, coverFileId);
        }
    }

    private void requireValidAnalysis(ContentAnalysis analysis) {
        if (analysis == null || analysis.observations() == null || analysis.schemaVersion() < 1) {
            throw new IllegalStateException("图像分析侧车返回了不完整的分析结果");
        }
    }

    private String contentHash(PhotoItem photo) {
        if (photo.getProviderMetadata() == null) {
            return null;
        }
        Object value = photo.getProviderMetadata().get("contentHash");
        return value == null ? null : value.toString();
    }
}
