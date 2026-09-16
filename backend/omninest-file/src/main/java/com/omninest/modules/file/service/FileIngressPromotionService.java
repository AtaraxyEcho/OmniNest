package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.MalwareScanGateway;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.file.domain.FileIngressItem;
import com.omninest.modules.file.domain.FileIngressStatus;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.UploadStatus;
import com.omninest.modules.file.event.FileSecurityScanRequestedEvent;
import com.omninest.modules.file.repository.FileIngressItemRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.file.service.FileIngressSafetyService.InspectionResult;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 安全扫描通过后的文件晋升服务：复制对象、创建文件节点并回写上传会话终态。
 * 入库记录状态是幂等依据：AVAILABLE 直接成功，CLEAN 从发布段续跑，其余全量重扫。
 * 晋升事务由 TransactionTemplate 包裹，扫描本身不持有数据库事务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileIngressPromotionService {
    private final FileIngressItemRepository ingressItemRepository;
    private final FileIngressLifecycleService ingressLifecycleService;
    private final FileIngressSafetyService ingressSafetyService;
    private final FileUploadSessionRepository uploadSessionRepository;
    private final FileObjectRepository fileObjectRepository;
    private final FileNodeRepository fileNodeRepository;
    private final FileManagerService fileManagerService;
    private final FileContentChangePublisher fileContentChangePublisher;
    private final StorageQuotaService storageQuotaService;
    private final ObjectStorageClient objectStorageClient;
    private final UserSyncEventRecorder syncEventRecorder;
    private final NotificationPublisher notificationPublisher;
    private final TransactionTemplate transactionTemplate;

    /**
     * 处理一条安全扫描任务消息。
     *
     * @param event 扫描任务消息
     * @return 晋升结果：fileNodeId 为空表示跳过或未晋升
     */
    public PromotionOutcome process(FileSecurityScanRequestedEvent event) {
        FileIngressItem item = ingressItemRepository.findById(event.ingressItemId()).orElse(null);
        if (item == null) {
            log.warn("安全扫描任务缺少入库记录，跳过: taskId={}, ingressItemId={}",
                    event.taskId(), event.ingressItemId());
            return PromotionOutcome.skipped();
        }
        if (item.getStatus() == FileIngressStatus.AVAILABLE) {
            log.info("入库记录已晋升，跳过重复扫描: ingressItemId={}", item.getId());
            return PromotionOutcome.skipped();
        }
        String sha256;
        if (item.getStatus() == FileIngressStatus.CLEAN) {
            sha256 = item.getSha256();
        } else {
            ingressLifecycleService.markScanning(item.getId());
            InspectionResult inspection = scanQuietly(item);
            ensureShaMatches(item, event, inspection);
            ingressLifecycleService.markClean(item.getId(), inspection.sha256());
            sha256 = inspection.sha256();
        }
        return promote(item, sha256, event);
    }

    /**
     * 晋升执行结果，供任务结果回写与前端等待晋升后消费。
     *
     * @param fileNodeId 晋升后的文件节点 ID
     * @param mediaAutoImportTaskId 媒体自动导入任务 ID
     */
    public record PromotionOutcome(UUID fileNodeId, UUID mediaAutoImportTaskId) {
        public static PromotionOutcome skipped() {
            return new PromotionOutcome(null, null);
        }
    }

    private InspectionResult scanQuietly(FileIngressItem item) {
        InspectionResult inspection;
        try {
            inspection = ingressSafetyService.inspect(
                    quarantineKey(item),
                    item.getSizeBytes(),
                    item.getSourceType(),
                    item.getUploadSessionId() != null ? item.getUploadSessionId() : item.getSourceTaskId()
            );
        } catch (BusinessException exception) {
            if (exception.errorCode() == ErrorCode.FILE_SECURITY_REJECTED) {
                settleTerminalFailure(item, true, exception.errorCode().name(), exception.getMessage(),
                        "文件未通过安全扫描", "文件「" + item.getTargetName() + "」检测到安全威胁，已拒绝入库");
                throw new FileIngressRejectedException(exception.getMessage(), exception);
            }
            throw exception;
        }
        if (inspection.status() == MalwareScanGateway.Status.INFECTED) {
            settleTerminalFailure(item, true, ErrorCode.FILE_SECURITY_REJECTED.name(), inspection.message(),
                    "文件未通过安全扫描", "文件「" + item.getTargetName() + "」检测到安全威胁，已拒绝入库");
            throw new FileIngressRejectedException(inspection.message());
        }
        return inspection;
    }

    private void ensureShaMatches(
            FileIngressItem item,
            FileSecurityScanRequestedEvent event,
            InspectionResult inspection
    ) {
        if (event.declaredSha256() == null || event.declaredSha256().isBlank()) {
            return;
        }
        if (event.declaredSha256().equalsIgnoreCase(inspection.sha256())) {
            return;
        }
        settleTerminalFailure(item, false, ErrorCode.FILE_UPLOAD_FAILED.name(), "服务端计算的文件摘要与客户端声明不一致",
                "文件完整性校验失败", "文件「" + item.getTargetName() + "」服务端摘要与声明不一致，已拒绝入库");
        throw new FileIngressRejectedException("服务端计算的文件摘要与客户端声明不一致");
    }

    private PromotionOutcome promote(FileIngressItem item, String sha256, FileSecurityScanRequestedEvent event) {
        return transactionTemplate.execute(txStatus -> promoteInTransaction(item, sha256, event));
    }

    private PromotionOutcome promoteInTransaction(
            FileIngressItem item, String sha256, FileSecurityScanRequestedEvent event) {
        FileUploadSession session = item.getUploadSessionId() == null
                ? null
                : uploadSessionRepository.findById(item.getUploadSessionId()).orElse(null);
        ObjectStorageKey quarantineKey = quarantineKey(item);
        ObjectStorageKey targetKey = new ObjectStorageKey(item.getTargetBucket(), item.getTargetObjectKey());
        objectStorageClient.copyObject(quarantineKey, targetKey);
        FileObject savedObject = fileObjectRepository.save(toFileObject(item, sha256));
        FileNode promotedNode = event.asVersionOfFileId() != null
                ? promoteAsVersion(item, event.asVersionOfFileId(), savedObject)
                : promoteAsNewNode(item, savedObject);
        UUID mediaAutoImportTaskId = null;
        if (session != null) {
            mediaAutoImportTaskId = applySessionResult(session, item, savedObject, promotedNode);
        }
        if (event.asVersionOfFileId() == null) {
            recordFileCreated(item.getOwnerUserId(), promotedNode);
        }
        registerFinalization(item.getId(), quarantineKey, targetKey, promotedNode.getId());
        return new PromotionOutcome(promotedNode.getId(), mediaAutoImportTaskId);
    }

    private FileNode promoteAsVersion(FileIngressItem item, UUID asVersionOfFileId, FileObject savedObject) {
        FileNode target = fileNodeRepository
                .findByIdAndOwnerUserIdAndDeletedFalse(asVersionOfFileId, item.getOwnerUserId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "版本目标文件不存在"));
        fileManagerService.saveNewVersion(
                item.getOwnerUserId(),
                asVersionOfFileId,
                savedObject.getId(),
                savedObject.getSizeBytes(),
                null);
        return target;
    }

    private FileNode promoteAsNewNode(FileIngressItem item, FileObject savedObject) {
        FileNode parent = resolveParent(item.getOwnerUserId(), item.getTargetParentId());
        if (sameNameExists(item.getOwnerUserId(), item.getTargetParentId(), item.getTargetName())) {
            settleTerminalFailure(item, false, ErrorCode.CONFLICT.name(), "晋升时目标目录已存在同名文件",
                    "文件入库冲突", "文件「" + item.getTargetName() + "」所在目录已存在同名文件，上传未完成");
            throw new FileIngressRejectedException("晋升时目标目录已存在同名文件");
        }
        return fileNodeRepository.save(toFileNode(item, savedObject, parent));
    }

    private UUID applySessionResult(
            FileUploadSession session,
            FileIngressItem item,
            FileObject savedObject,
            FileNode promotedNode
    ) {
        UUID mediaAutoImportTaskId =
                fileContentChangePublisher.publish(promotedNode, savedObject, item.getOwnerUserId());
        session.setIngressItemId(item.getId());
        session.setResultFileNodeId(promotedNode.getId());
        session.setResultObjectId(savedObject.getId());
        settleUploadQuota(session);
        session.setUploadedParts(session.getTotalParts());
        session.setStatus(UploadStatus.COMPLETED.getValue());
        session.setCompletionTaskId(mediaAutoImportTaskId);
        uploadSessionRepository.save(session);
        return mediaAutoImportTaskId;
    }

    private void settleTerminalFailure(
            FileIngressItem item,
            boolean rejected,
            String errorCode,
            String summary,
            String notifyTitle,
            String notifyMessage
    ) {
        ingressLifecycleService.markFailed(item.getId(), rejected, errorCode, summary);
        rejectSession(item);
        notificationPublisher.notifyOrLog(
                item.getOwnerUserId(),
                "FILE_SECURITY",
                notifyTitle,
                notifyMessage,
                Map.of("ingressItemId", item.getId().toString())
        );
    }

    private void rejectSession(FileIngressItem item) {
        if (item.getUploadSessionId() == null) {
            return;
        }
        uploadSessionRepository.findById(item.getUploadSessionId()).ifPresent(session -> {
            if (session.getQuotaReservationId() != null) {
                storageQuotaService.releaseReservation("UPLOAD", session.getId());
                session.setQuotaReservationId(null);
            }
            session.setStatus(UploadStatus.REJECTED.getValue());
            uploadSessionRepository.save(session);
        });
    }

    private void settleUploadQuota(FileUploadSession session) {
        if (session.getSpaceType() != SpaceType.PERSONAL) {
            return;
        }
        if (session.getQuotaReservationId() == null) {
            storageQuotaService.checkQuota(session.getOwnerUserId(), session.getTotalSizeBytes());
            storageQuotaService.incrementUsage(session.getOwnerUserId(), session.getTotalSizeBytes());
            return;
        }
        storageQuotaService.settleReservation("UPLOAD", session.getId(), session.getTotalSizeBytes());
    }

    private void registerFinalization(
            UUID ingressId,
            ObjectStorageKey quarantineKey,
            ObjectStorageKey targetKey,
            UUID fileNodeId
    ) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            ingressLifecycleService.markAvailable(ingressId, fileNodeId);
            objectStorageClient.removeObject(quarantineKey);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCompletion(int txStatus) {
                if (txStatus == TransactionSynchronization.STATUS_COMMITTED) {
                    markAvailableQuietly(ingressId, fileNodeId);
                    removeObjectQuietly(quarantineKey, "清理文件入库隔离对象失败");
                    return;
                }
                markFailedQuietly(ingressId);
                removeObjectQuietly(targetKey, "清理文件晋升对象失败");
            }
        });
    }

    private void markAvailableQuietly(UUID ingressId, UUID fileNodeId) {
        try {
            ingressLifecycleService.markAvailable(ingressId, fileNodeId);
        } catch (RuntimeException exception) {
            log.warn("更新文件入库可用状态失败: ingressId={}, errorType={}",
                    ingressId, exception.getClass().getSimpleName());
        }
    }

    private void markFailedQuietly(UUID ingressId) {
        try {
            ingressLifecycleService.markFailed(
                    ingressId,
                    false,
                    ErrorCode.FILE_UPLOAD_FAILED.name(),
                    "文件业务元数据提交失败"
            );
        } catch (RuntimeException exception) {
            log.warn("更新文件入库失败状态失败: ingressId={}, errorType={}",
                    ingressId, exception.getClass().getSimpleName());
        }
    }

    private void removeObjectQuietly(ObjectStorageKey key, String message) {
        try {
            objectStorageClient.removeObject(key);
        } catch (RuntimeException exception) {
            log.warn("{}: bucket={}, errorType={}", message, key.bucket(), exception.getClass().getSimpleName());
        }
    }

    private ObjectStorageKey quarantineKey(FileIngressItem item) {
        return new ObjectStorageKey(item.getQuarantineBucket(), item.getQuarantineObjectKey());
    }

    private FileObject toFileObject(FileIngressItem item, String sha256) {
        FileObject fileObject = new FileObject();
        fileObject.setBucketName(item.getTargetBucket());
        fileObject.setObjectKey(item.getTargetObjectKey());
        fileObject.setSha256(sha256);
        fileObject.setSizeBytes(item.getSizeBytes());
        fileObject.setMimeType(item.getMimeType());
        return fileObject;
    }

    private FileNode toFileNode(FileIngressItem item, FileObject object, FileNode parent) {
        FileNode file = new FileNode();
        file.setOwnerUserId(item.getOwnerUserId());
        file.setParentId(item.getTargetParentId());
        file.setNodeType(NodeType.FILE.getValue());
        file.setName(item.getTargetName());
        file.setNormalizedPath(resolveChildPath(parent, item.getTargetName()));
        file.setMimeType(item.getMimeType());
        file.setSizeBytes(item.getSizeBytes());
        file.setCurrentObjectId(object.getId());
        SpaceType spaceType = resolveSpaceType(item);
        file.setSpaceType(spaceType);
        if (spaceType == SpaceType.SHARED) {
            file.setUploadedBy(item.getOwnerUserId());
        }
        return file;
    }

    private SpaceType resolveSpaceType(FileIngressItem item) {
        return item.getUploadSessionId() == null
                ? SpaceType.PERSONAL
                : uploadSessionRepository.findById(item.getUploadSessionId())
                        .map(FileUploadSession::getSpaceType)
                        .orElse(SpaceType.PERSONAL);
    }

    private FileNode resolveParent(UUID ownerUserId, UUID parentId) {
        if (parentId == null) {
            return null;
        }
        FileNode parent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(parentId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在"));
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "父级节点不是文件夹");
        }
        return parent;
    }

    private boolean sameNameExists(UUID ownerUserId, UUID parentId, String fileName) {
        if (parentId == null) {
            return fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(ownerUserId, fileName);
        }
        return fileNodeRepository.existsByOwnerUserIdAndParentIdAndNameAndDeletedFalse(ownerUserId, parentId, fileName);
    }

    private String resolveChildPath(FileNode parent, String childName) {
        if (parent == null) {
            return "/" + childName;
        }
        return parent.getNormalizedPath() + "/" + childName;
    }

    private void recordFileCreated(UUID ownerUserId, FileNode file) {
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId,
                SyncScope.FILES,
                "FILE_NODE",
                file.getId().toString(),
                SyncAction.CREATED,
                null,
                Map.of("source", "UPLOAD")
        ));
    }
}
