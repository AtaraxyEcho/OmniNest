package com.omninest.modules.photos.service;

import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.media.service.MediaImportHandler;
import com.omninest.modules.media.service.MediaImportResult;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 照片自动导入服务，上传图片文件后自动创建 PhotoItem 记录。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoAutoImportService implements MediaImportHandler {

    private static final Set<String> IMAGE_MIME_PREFIXES = Set.of(
            "image/jpeg", "image/png", "image/gif",
            "image/bmp", "image/tiff", "image/heic", "image/heif",
            "image/x-canon-cr2", "image/x-nikon-nef", "image/x-sony-arw",
            "image/x-adobe-dng"
    );

    private final PhotoAdminService photoAdminService;

    @Override
    public String module() {
        return "PHOTOS";
    }

    @Override
    public boolean supports(FileUploadedEvent event) {
        return isImageFile(event.mimeType());
    }

    @Override
    public MediaImportResult importFile(FileUploadedEvent event) {
        photoAdminService.importSinglePhoto(event.ownerUserId(), event.fileNodeId());
        log.info("照片自动导入完成: fileNodeId={}, fileName={}",
                event.fileNodeId(), event.fileName());
        return new MediaImportResult(module(), event.fileNodeId());
    }

    /**
     * 尝试自动导入上传的图片文件。
     * 如果是图片文件，触发单张导入并返回 fileNodeId。
     * 幂等安全：已导入的照片会自动跳过。
     */
    public Optional<UUID> importUploadedFile(FileUploadedEvent event) {
        if (!supports(event)) {
            return Optional.empty();
        }
        return Optional.of(importFile(event).resourceId());
    }

    private boolean isImageFile(String mimeType) {
        if (mimeType == null) {
            return false;
        }
        String lower = mimeType.toLowerCase(Locale.ROOT);
        return IMAGE_MIME_PREFIXES.stream().anyMatch(lower::startsWith);
    }
}
