package com.omninest.modules.photos.service;

import com.omninest.common.processing.TempStagingPort;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import java.awt.image.BufferedImage;
import java.nio.file.Path;
import java.util.UUID;
import javax.imageio.ImageIO;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.imaging.ImageInfo;
import org.apache.commons.imaging.Imaging;
import org.springframework.stereotype.Service;

/**
 * RAW 图片预览服务，使用 Apache Commons Imaging 将 RAW 文件转换为 JPEG。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoRawPreviewService {

    private final DerivedAssetStorageService derivedAssetStorageService;
    private final PhotoInputGuard inputGuard;
    private final TempStagingPort tempStagingPort;

    private static final String RESOURCE_TYPE = "PHOTO_ITEM";
    private static final String ASSET_TYPE = "RAW_PREVIEW";

    /**
     * 创建 RAW 文件的 JPEG 预览并存储到 MinIO。
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     * @param rawFile RAW 本地文件
     * @return 存储后的 FileNode ID，调用方可用于生成下载 URL
     */
    public UUID createPreview(UUID ownerUserId, UUID photoId, Path rawFile) {
        Path previewFile = null;
        try {
            ImageInfo imageInfo = Imaging.getImageInfo(rawFile.toFile());
            inputGuard.validateDimensions(imageInfo.getWidth(), imageInfo.getHeight());
            BufferedImage image = Imaging.getBufferedImage(rawFile.toFile());
            if (image == null) {
                return null;
            }
            inputGuard.validateDimensions(image.getWidth(), image.getHeight());
            previewFile = tempStagingPort.createTempFile(
                    "photo-raw-preview", "omninest-photo-raw-preview-", ".jpg");
            if (!ImageIO.write(image, "jpg", previewFile.toFile())) {
                return null;
            }
            String previewFileName = photoId + "_raw_preview.jpg";
            return derivedAssetStorageService.store(
                    ownerUserId,
                    RESOURCE_TYPE,
                    photoId,
                    ASSET_TYPE,
                    previewFileName,
                    "image/jpeg",
                    previewFile
            );
        } catch (Exception ex) {
            log.warn("RAW 转 JPEG 失败", ex);
            return null;
        } finally {
            deleteQuietly(previewFile);
        }
    }

    private void deleteQuietly(Path file) {
        tempStagingPort.deleteQuietly(file);
    }
}
