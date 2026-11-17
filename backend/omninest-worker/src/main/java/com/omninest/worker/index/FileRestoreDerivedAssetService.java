package com.omninest.worker.index;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.dto.FileObjectDescriptor;
import com.omninest.modules.file.event.FileRestoredEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.photos.service.PhotoThumbnailService;
import java.io.InputStream;
import java.util.Locale;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 文件恢复后的源对象校验与图片缩略图修复服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class FileRestoreDerivedAssetService {

    private static final Set<String> SUPPORTED_IMAGE_MIME_TYPES = Set.of(
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "image/bmp"
    );

    private final FileLifecycleGuard fileLifecycleGuard;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final ObjectStorageClient objectStorageClient;
    private final PhotoThumbnailService photoThumbnailService;

    /**
     * 校验恢复文件的源对象，并在图片缩略图缺失时重新生成。
     *
     * @param event 文件恢复事件
     */
    public void validateAndRepair(FileRestoredEvent event) {
        FileDescriptor file = fileLifecycleGuard.requireOwnedWritable(
                event.ownerUserId(),
                event.fileNodeId()
        );
        FileObjectDescriptor object = requireAvailableObject(file);
        if (!isSupportedImage(file.mimeType())
                || photoThumbnailService.hasStoredThumbnail(event.ownerUserId(), event.fileNodeId())) {
            return;
        }

        ObjectStorageKey key = new ObjectStorageKey(object.bucketName(), object.objectKey());
        try (InputStream input = objectStorageClient.getObject(key)) {
            if (photoThumbnailService.generateAndStore(
                    event.ownerUserId(),
                    event.fileNodeId(),
                    input,
                    file.name()
            ) == null) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "恢复文件缩略图重建失败");
            }
        } catch (BusinessException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "恢复文件缩略图读取失败");
        }
        log.info("恢复文件缩略图已重建: fileNodeId={}", event.fileNodeId());
    }

    private FileObjectDescriptor requireAvailableObject(FileDescriptor file) {
        if (file.currentObjectId() == null) {
            throw new BusinessException(ErrorCode.FILE_OBJECT_MISSING, "恢复文件缺少当前对象引用");
        }
        FileObjectDescriptor object = fileMetadataQueryService.findObjectById(file.currentObjectId())
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.FILE_OBJECT_MISSING,
                        "恢复文件对象元数据不存在"
                ));
        ObjectStorageKey key = new ObjectStorageKey(object.bucketName(), object.objectKey());
        if (!objectStorageClient.objectExists(key)) {
            throw new BusinessException(ErrorCode.FILE_OBJECT_MISSING, "恢复文件物理对象不存在");
        }
        return object;
    }

    private boolean isSupportedImage(String mimeType) {
        if (mimeType == null || mimeType.isBlank()) {
            return false;
        }
        return SUPPORTED_IMAGE_MIME_TYPES.contains(mimeType.trim().toLowerCase(Locale.ROOT));
    }
}
