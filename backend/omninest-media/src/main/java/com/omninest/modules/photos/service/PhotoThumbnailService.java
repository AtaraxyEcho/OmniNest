package com.omninest.modules.photos.service;

import com.omninest.modules.media.domain.AssetType;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import java.util.UUID;
import javax.imageio.ImageIO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.coobird.thumbnailator.Thumbnails;
import org.springframework.stereotype.Service;

/**
 * 图片缩略图生成服务。
 *
 * <p>使用 Thumbnailator 将原始图片压缩为 1024×1024 以内的 WebP 缩略图，
 * 并通过 {@link DerivedAssetStorageService} 持久化到 MinIO。
 * WebP 编码器由 webp-imageio 依赖提供；若 JVM 缺少该编码器则自动回退到 JPEG。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoThumbnailService {

    private final DerivedAssetStorageService derivedAssetStorageService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final PhotoSourceFileService sourceFileService;
    private final PhotoInputGuard inputGuard;

    // 1024 长边在高 DPI 屏幕的网格/列表场景达到视网膜级清晰度。
    private static final int MAX_THUMBNAIL_WIDTH = 1024;
    private static final int MAX_THUMBNAIL_HEIGHT = 1024;
    private static final double QUALITY = 0.82;

    private static final boolean WEBP_AVAILABLE;
    static {
        boolean available = false;
        try {
            available = ImageIO.getImageWritersByFormatName("webp").hasNext();
        } catch (Exception ignored) {
            // WebP 不可用
        }
        WEBP_AVAILABLE = available;
    }

    private static final String OUTPUT_FORMAT = WEBP_AVAILABLE ? "webp" : "jpg";
    private static final String MIME_TYPE = WEBP_AVAILABLE ? "image/webp" : "image/jpeg";
    private static final String FILE_NAME = WEBP_AVAILABLE ? "thumb.webp" : "thumb.jpg";

    /**
     * 检查指定源照片的缩略图元数据和物理对象是否可用。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 源照片文件节点 ID
     * @return 缩略图可用时返回 true
     */
    public boolean hasStoredThumbnail(UUID ownerUserId, UUID fileNodeId) {
        return derivedAssetStorageService.isAvailable(
                ownerUserId,
                ResourceType.PHOTO_ITEM.getValue(),
                fileNodeId,
                AssetType.POSTER.getValue(),
                FILE_NAME
        );
    }

    /**
     * 查询已存在缩略图的派生文件节点 ID，供调用方在不重新生成的情况下回填封面引用。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 源照片文件节点 ID
     * @return 缩略图派生文件节点 ID；不可用时返回空
     */
    public Optional<UUID> findStoredThumbnailFileNodeId(UUID ownerUserId, UUID fileNodeId) {
        return derivedAssetStorageService.findStoredFileNodeId(
                ownerUserId,
                ResourceType.PHOTO_ITEM.getValue(),
                fileNodeId,
                AssetType.POSTER.getValue(),
                FILE_NAME
        );
    }

    /**
     * 从图片输入流生成缩略图并存储到 MinIO。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId  关联的文件节点 ID
     * @param imageStream 图片输入流
     * @param fileName    原始文件名
     * @return 缩略图的 FileNode UUID，失败时返回 null
     */
    public UUID generateAndStore(UUID ownerUserId, UUID fileNodeId, InputStream imageStream, String fileName) {
        try (PhotoSourceFileService.StagedPhotoFile source = sourceFileService.stageInput(
                imageStream,
                fileName,
                null
        )) {
            return generateAndStoreFile(ownerUserId, fileNodeId, source.path(), source.fileName());
        } catch (BusinessException ex) {
            log.warn("缩略图输入暂存失败: fileNodeId={}, error={}", fileNodeId, ex.getMessage());
            return null;
        } catch (Exception ex) {
            log.warn("缩略图生成失败: fileNodeId={}", fileNodeId, ex);
            return null;
        }
    }

    /**
     * 从本地照片文件生成缩略图并存储到 MinIO。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 关联的文件节点 ID
     * @param sourceFile 本地照片文件
     * @param fileName 原始文件名
     * @return 缩略图的 FileNode UUID，失败时返回 null
     */
    public UUID generateAndStoreFile(UUID ownerUserId, UUID fileNodeId, Path sourceFile, String fileName) {
        Path outputFile = null;
        try {
            if (!fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)) {
                log.info("源文件已删除或正在永久删除，跳过缩略图生成: fileNodeId={}", fileNodeId);
                return null;
            }
            inputGuard.inspectForDecode(sourceFile, fileName);
            outputFile = createOutputPath();
            Thumbnails.of(sourceFile.toFile())
                    .size(MAX_THUMBNAIL_WIDTH, MAX_THUMBNAIL_HEIGHT)
                    .keepAspectRatio(true)
                    .outputFormat(OUTPUT_FORMAT)
                    .outputQuality(QUALITY)
                    .toFile(outputFile.toFile());
            if (!fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)) {
                log.info("源文件在缩略图生成期间进入永久删除流程，放弃写入: fileNodeId={}", fileNodeId);
                return null;
            }
            return derivedAssetStorageService.store(
                    ownerUserId,
                    ResourceType.PHOTO_ITEM.getValue(),
                    fileNodeId,
                    AssetType.POSTER.getValue(),
                    FILE_NAME,
                    MIME_TYPE,
                    outputFile
            );
        } catch (BusinessException ex) {
            log.warn("缩略图输入校验失败: fileNodeId={}, error={}", fileNodeId, ex.getMessage());
            return null;
        } catch (Exception ex) {
            log.warn("Thumbnailator 处理失败: fileNodeId={}", fileNodeId, ex);
            return null;
        } finally {
            deleteQuietly(outputFile);
        }
    }

    private Path createOutputPath() throws IOException {
        Path outputFile = Files.createTempFile("omninest-photo-thumbnail-", "." + OUTPUT_FORMAT);
        Files.deleteIfExists(outputFile);
        return outputFile;
    }

    private void deleteQuietly(Path file) {
        if (file == null) {
            return;
        }
        try {
            Files.deleteIfExists(file);
        } catch (IOException exception) {
            log.debug("缩略图临时文件清理失败: errorType={}", exception.getClass().getSimpleName());
        }
    }
}
