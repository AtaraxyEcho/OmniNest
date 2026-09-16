package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.MalwareScanGateway;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.FileIngressItem;
import com.omninest.modules.file.repository.FileIngressItemRepository;
import com.omninest.modules.file.service.FileIngressSafetyService.InspectionResult;
import com.omninest.modules.file.service.FileIngressLifecycleService.IngressCommand;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 外部业务模块的隔离暂存与扫描服务：媒体模块只持有入库记录 ID，不接触对象键。
 * 暂存对象落入隔离桶并创建入库记录；扫描走统一 fail-closed 语义；
 * 终态拒绝抛出 {@link FileIngressRejectedException}，基础设施异常按可重试抛出。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileIngressStagingService {
    private final ObjectStorageClient objectStorageClient;
    private final ObjectStorageBuckets objectStorageBuckets;
    private final FileIngressLifecycleService ingressLifecycleService;
    private final FileIngressSafetyService ingressSafetyService;
    private final FileIngressItemRepository ingressItemRepository;

    /**
     * 将本地文件暂存至隔离桶并创建入库记录。
     *
     * @param ownerUserId 所属用户 ID
     * @param sourceType 来源类型（如 BACKDROP）
     * @param sourceId 来源业务 ID
     * @param fileName 暂存对象文件名
     * @param mimeType MIME 类型
     * @param file 本地暂存文件
     * @return 入库记录 ID
     */
    public UUID stage(UUID ownerUserId, String sourceType, UUID sourceId, String fileName, String mimeType, Path file) {
        ObjectStorageKey key = new ObjectStorageKey(
                objectStorageBuckets.quarantine(),
                "staged/" + sourceType.toLowerCase(Locale.ROOT) + "/" + ownerUserId + "/" + sourceId + "/" + fileName
        );
        objectStorageClient.putObject(key, file, mimeType);
        long sizeBytes;
        try {
            sizeBytes = Files.size(file);
        } catch (IOException exception) {
            objectStorageClient.removeObject(key);
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "无法读取暂存文件大小");
        }
        return ingressLifecycleService.open(new IngressCommand(
                ownerUserId,
                sourceType,
                sourceId,
                null,
                key.bucket(),
                key.objectKey(),
                "",
                "",
                null,
                fileName,
                sizeBytes,
                mimeType
        ));
    }

    /**
     * 执行安全扫描并回写入库状态。
     *
     * @param ingressItemId 入库记录 ID
     * @return 扫描结果（仅 CLEAN/SKIPPED 会返回）
     */
    public InspectionResult scan(UUID ingressItemId) {
        FileIngressItem item = requireItem(ingressItemId);
        ingressLifecycleService.markScanning(ingressItemId);
        InspectionResult inspection;
        try {
            inspection = ingressSafetyService.inspect(
                    quarantineKey(item),
                    item.getSizeBytes(),
                    item.getSourceType(),
                    item.getSourceTaskId() != null ? item.getSourceTaskId() : ingressItemId
            );
        } catch (BusinessException exception) {
            if (exception.errorCode() == ErrorCode.FILE_SECURITY_REJECTED) {
                ingressLifecycleService.markFailed(
                        ingressItemId, true, exception.errorCode().name(), exception.getMessage());
                throw new FileIngressRejectedException(exception.getMessage(), exception);
            }
            throw exception;
        }
        if (inspection.status() == MalwareScanGateway.Status.INFECTED) {
            ingressLifecycleService.markFailed(
                    ingressItemId, true, ErrorCode.FILE_SECURITY_REJECTED.name(), inspection.message());
            throw new FileIngressRejectedException(inspection.message());
        }
        ingressLifecycleService.markClean(ingressItemId, inspection.sha256());
        return inspection;
    }

    /**
     * 将暂存对象复制到调用方自有临时文件，调用方负责删除。
     *
     * @param ingressItemId 入库记录 ID
     * @return 临时文件路径
     */
    public Path copyToTempFile(UUID ingressItemId) {
        FileIngressItem item = requireItem(ingressItemId);
        Path tempFile = null;
        try {
            tempFile = Files.createTempFile("ingress-staged-", safeSuffix(item.getTargetName()));
            try (InputStream inputStream =
                         objectStorageClient.getObject(quarantineKey(item))) {
                inputStream.transferTo(Files.newOutputStream(tempFile));
            }
            return tempFile;
        } catch (IOException | RuntimeException exception) {
            deleteTempQuietly(tempFile);
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "无法读取暂存对象");
        }
    }

    /**
     * 标记入库记录已发布为正式节点并清理暂存对象。
     *
     * @param ingressItemId 入库记录 ID
     * @param resultFileNodeId 正式节点 ID
     */
    public void markAvailable(UUID ingressItemId, UUID resultFileNodeId) {
        ingressLifecycleService.markAvailable(ingressItemId, resultFileNodeId);
        releaseObject(ingressItemId);
    }

    /**
     * 清理暂存对象（入库记录保留，终态记录由保留期回收任务处理）。
     *
     * @param ingressItemId 入库记录 ID
     */
    public void releaseObject(UUID ingressItemId) {
        ingressItemRepository.findById(ingressItemId).ifPresent(item ->
                objectStorageClient.removeObject(quarantineKey(item)));
    }

    private FileIngressItem requireItem(UUID ingressItemId) {
        return ingressItemRepository.findById(ingressItemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "暂存入库记录不存在"));
    }

    private ObjectStorageKey quarantineKey(FileIngressItem item) {
        return new ObjectStorageKey(item.getQuarantineBucket(), item.getQuarantineObjectKey());
    }

    private String safeSuffix(String fileName) {
        if (fileName == null) {
            return ".bin";
        }
        int dotIndex = fileName.lastIndexOf('.');
        if (dotIndex < 0 || dotIndex == fileName.length() - 1) {
            return ".bin";
        }
        String extension = fileName.substring(dotIndex + 1).toLowerCase(Locale.ROOT);
        return extension.matches("[a-z0-9]{1,10}") ? "." + extension : ".bin";
    }

    private void deleteTempQuietly(Path tempFile) {
        if (tempFile == null) {
            return;
        }
        try {
            Files.deleteIfExists(tempFile);
        } catch (IOException exception) {
            // 临时文件清理失败不阻断主流程
        }
    }
}
