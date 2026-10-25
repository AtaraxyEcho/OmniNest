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
    private final FileVersionService fileVersionService;
    private final FileContentChangePublisher fileContentChangePublisher;
    private final StorageQuotaService storageQuotaService;
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
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
            requireActualSizeWithinDeclaration(item, inspection);
            ingressLifecycleService.markClean(item.getId(), inspection.sha256());
            applyInspectionCorrections(item, inspection);
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
                    item.getTargetName(),
                    item.getSourceType(),
                    item.getUploadSessionId() != null ? item.getUploadSessionId() : item.getSourceTaskId()
            );
        } catch (BusinessException exception) {
            if (exception.errorCode() == ErrorCode.FILE_SECURITY_REJECTED) {
                settleTerminalFailure(item, true, exception.errorCode().name(), exception.getMessage(),
                        "文件未通过安全扫描", "文件「" + item.getTargetName() + "」检测到安全威胁，已拒绝入库",
                        "SECURITY_THREAT");
                throw new FileIngressRejectedException(exception.getMessage(), exception);
            }
            throw exception;
        }
        if (inspection.status() == MalwareScanGateway.Status.INFECTED) {
            settleTerminalFailure(item, true, ErrorCode.FILE_SECURITY_REJECTED.name(), inspection.message(),
                    "文件未通过安全扫描", "文件「" + item.getTargetName() + "」检测到安全威胁，已拒绝入库",
                    "SECURITY_THREAT");
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
                "文件完整性校验失败", "文件「" + item.getTargetName() + "」服务端摘要与声明不一致，已拒绝入库",
                "SECURITY_SCAN_FAILED");
        throw new FileIngressRejectedException("服务端计算的文件摘要与客户端声明不一致");
    }

    /**
     * 实际字节数超过申报值时拒绝入库：预签名直传未限制大小，
     * 低报大小是绕过配额预留的唯一路径，必须在晋升前核对。
     */
    private void requireActualSizeWithinDeclaration(FileIngressItem item, InspectionResult inspection) {
        if (inspection.actualSizeBytes() < 0 || inspection.actualSizeBytes() <= item.getSizeBytes()) {
            return;
        }
        settleTerminalFailure(item, false, ErrorCode.FILE_UPLOAD_FAILED.name(), "实际大小超过申报大小",
                "文件大小校验失败", "文件「" + item.getTargetName() + "」实际大小超过申报大小，已拒绝入库",
                "SECURITY_SCAN_FAILED");
        throw new FileIngressRejectedException("实际大小超过申报大小");
    }

    /**
     * 以服务端事实修正入库记录：实际字节数与魔数探测的 MIME。
     * 实际小于申报时按实际值结算配额；探测无结论（null）时保留客户端声明。
     */
    private void applyInspectionCorrections(FileIngressItem item, InspectionResult inspection) {
        boolean changed = false;
        if (inspection.actualSizeBytes() >= 0 && inspection.actualSizeBytes() != item.getSizeBytes()) {
            item.setSizeBytes(inspection.actualSizeBytes());
            changed = true;
        }
        String detected = inspection.detectedMimeType();
        if (detected != null && !detected.equals(item.getMimeType())) {
            log.info("入库 MIME 按魔数修正: ingressItemId={}, declared={}, detected={}",
                    item.getId(), item.getMimeType(), detected);
            item.setMimeType(detected);
            changed = true;
        }
        if (changed) {
            ingressItemRepository.save(item);
        }
    }

    private PromotionOutcome promote(FileIngressItem item, String sha256, FileSecurityScanRequestedEvent event) {
        try {
            return copyAndPromote(item, sha256, event);
        } catch (BusinessException exception) {
            if (exception.errorCode() != ErrorCode.FILE_QUOTA_EXCEEDED) {
                throw exception;
            }
            // 容量在晋升阶段才失败时，事务已回滚；上传会话必须落到明确终态，
            // 否则会停在 SCANNING 并触发 Worker 的无效重试。
            settleTerminalFailure(item, true, ErrorCode.FILE_QUOTA_EXCEEDED.name(), "存储配额不足",
                    "文件上传失败", "文件「" + item.getTargetName() + "」存储配额不足，上传未完成",
                    "QUOTA_WARNING");
            removeObjectQuietly(quarantineKey(item), "清理文件晋升配额失败对象失败");
            throw new FileIngressRejectedException("存储配额不足", exception);
        }
    }

    private PromotionOutcome copyAndPromote(
            FileIngressItem item, String sha256, FileSecurityScanRequestedEvent event) {
        FileUploadSession session = item.getUploadSessionId() == null
                ? null
                : uploadSessionRepository.findById(item.getUploadSessionId()).orElse(null);
        if (session != null && session.getSpaceType() == SpaceType.SHARED) {
            // 复制对象前先做一次容量预检，避免超限时在对象存储留下无主副本；
            // 真正的并发上限仍由 increaseUsage 的原子条件更新兜底。
            sharedSpaceQuotaService.checkQuota(item.getSizeBytes());
        }
        ObjectStorageKey quarantineKey = quarantineKey(item);
        ObjectStorageKey targetKey = new ObjectStorageKey(item.getTargetBucket(), item.getTargetObjectKey());
        // 对象复制是外部网络 I/O，必须在数据库事务之外执行；事务只承担元数据落库。
        // 以服务端核实的魔数类型重写对象元数据，关闭"申报 text/html 而魔数判为
        // text/plain"时按存储 Content-Type 内联直出的窗口。
        try {
            objectStorageClient.copyObject(quarantineKey, targetKey, item.getMimeType());
        } catch (RuntimeException exception) {
            removeObjectQuietly(quarantineKey, "清理文件晋升失败隔离对象失败");
            removeObjectQuietly(targetKey, "清理文件晋升失败对象失败");
            throw exception;
        }
        try {
            return transactionTemplate.execute(
                    txStatus -> promoteInTransaction(item, sha256, event, quarantineKey, targetKey));
        } catch (RuntimeException exception) {
            removeObjectQuietly(quarantineKey, "清理文件晋升失败隔离对象失败");
            removeObjectQuietly(targetKey, "清理文件晋升失败对象失败");
            throw exception;
        }
    }

    private PromotionOutcome promoteInTransaction(
            FileIngressItem item,
            String sha256,
            FileSecurityScanRequestedEvent event,
            ObjectStorageKey quarantineKey,
            ObjectStorageKey targetKey) {
        FileUploadSession session = item.getUploadSessionId() == null
                ? null
                : uploadSessionRepository.findById(item.getUploadSessionId()).orElse(null);
        if (session != null && session.getTotalSizeBytes() != item.getSizeBytes()) {
            // 配额结算以服务端核实的实际大小为准
            session.setTotalSizeBytes(item.getSizeBytes());
        }
        FileObject savedObject = fileObjectRepository.save(toFileObject(item, sha256));
        boolean versionUpload = event.asVersionOfFileId() != null;
        FileNode promotedNode = versionUpload
                ? promoteAsVersion(item, event.asVersionOfFileId(), savedObject, session)
                : promoteAsNewNode(item, savedObject);
        UUID mediaAutoImportTaskId = null;
        if (session != null) {
            mediaAutoImportTaskId = applySessionResult(session, item, savedObject, promotedNode, versionUpload);
        }
        if (!versionUpload) {
            recordFileCreated(item.getOwnerUserId(), promotedNode);
        }
        registerFinalization(item.getId(), quarantineKey, targetKey, promotedNode.getId());
        return new PromotionOutcome(promotedNode.getId(), mediaAutoImportTaskId);
    }

    private FileNode promoteAsVersion(
            FileIngressItem item, UUID asVersionOfFileId, FileObject savedObject, FileUploadSession session) {
        FileNode target = fileNodeRepository
                .findByIdAndOwnerUserIdAndDeletedFalse(asVersionOfFileId, item.getOwnerUserId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "版本目标文件不存在"));
        // 会话创建后目标可能被移到另一空间：晋升前再核对一次，避免按旧空间结算配额。
        if (session != null && target.getSpaceType() != session.getSpaceType()) {
            throw new BusinessException(ErrorCode.CONFLICT, "版本目标空间已变化，请重新开始上传");
        }
        // 配额已由上传会话在 settleUploadQuota 按会话大小结算，这里不能再计一次。
        fileVersionService.saveNewVersion(
                item.getOwnerUserId(),
                asVersionOfFileId,
                savedObject.getId(),
                savedObject.getSizeBytes(),
                null,
                false);
        return target;
    }

    private FileNode promoteAsNewNode(FileIngressItem item, FileObject savedObject) {
        SpaceType spaceType = resolveSpaceType(item);
        FileNode parent = resolveParent(item.getOwnerUserId(), item.getTargetParentId(), spaceType);
        if (sameNameExists(item.getOwnerUserId(), spaceType, item.getTargetParentId(), item.getTargetName())) {
            settleTerminalFailure(item, false, ErrorCode.CONFLICT.name(), "晋升时目标目录已存在同名文件",
                    "文件入库冲突", "文件「" + item.getTargetName() + "」所在目录已存在同名文件，上传未完成",
                    "TASK_FAILED");
            throw new FileIngressRejectedException("晋升时目标目录已存在同名文件");
        }
        return fileNodeRepository.save(toFileNode(item, savedObject, parent, spaceType));
    }

    private UUID applySessionResult(
            FileUploadSession session,
            FileIngressItem item,
            FileObject savedObject,
            FileNode promotedNode,
            boolean versionUpload
    ) {
        // 版本上传已在 saveNewVersion 内发布过内容变更，重复发布会为同一文件
        // 生成两份媒体导入、索引、缩略图与文本提取任务。
        UUID mediaAutoImportTaskId = versionUpload
                ? null
                : fileContentChangePublisher.publish(promotedNode, savedObject, item.getOwnerUserId());
        session.setIngressItemId(item.getId());
        session.setResultFileNodeId(promotedNode.getId());
        session.setResultObjectId(savedObject.getId());
        settleUploadQuota(session, versionUpload);
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
            String notifyMessage,
            String notificationType
    ) {
        ingressLifecycleService.markFailed(item.getId(), rejected, errorCode, summary);
        rejectSession(item);
        notificationPublisher.notifyOrLog(
                item.getOwnerUserId(),
                notificationType,
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

    private void settleUploadQuota(FileUploadSession session, boolean versionUpload) {
        if (session.getSpaceType() != SpaceType.PERSONAL) {
            // 共享空间按实际字节结算：版本上传只增加新对象字节，文件数不增加，
            // 否则每传一个历史版本都会让 fileCount 虚增一。容量预检已在上游完成，
            // 并发上限由 increaseUsage 的原子条件更新兜底。
            sharedSpaceQuotaService.increaseUsage(session.getTotalSizeBytes(), versionUpload ? 0 : 1);
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

    private FileNode toFileNode(FileIngressItem item, FileObject object, FileNode parent, SpaceType spaceType) {
        FileNode file = new FileNode();
        file.setOwnerUserId(item.getOwnerUserId());
        file.setParentId(item.getTargetParentId());
        file.setNodeType(NodeType.FILE.getValue());
        file.setName(item.getTargetName());
        file.setNormalizedPath(resolveChildPath(parent, item.getTargetName()));
        file.setMimeType(item.getMimeType());
        file.setSizeBytes(item.getSizeBytes());
        file.setCurrentObjectId(object.getId());
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

    private FileNode resolveParent(UUID ownerUserId, UUID parentId, SpaceType spaceType) {
        if (parentId == null) {
            return null;
        }
        FileNode parent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(parentId, ownerUserId)
                .orElseGet(() -> spaceType == SpaceType.SHARED
                        ? fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(parentId, SpaceType.SHARED).orElse(null)
                        : null);
        if (parent == null) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在");
        }
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "父级节点不是文件夹");
        }
        if (parent.getSpaceType() != spaceType) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "父级目录与目标空间类型不一致");
        }
        return parent;
    }

    private boolean sameNameExists(UUID ownerUserId, SpaceType spaceType, UUID parentId, String fileName) {
        if (spaceType == SpaceType.SHARED) {
            if (parentId == null) {
                return fileNodeRepository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                        SpaceType.SHARED, fileName);
            }
            return fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                    SpaceType.SHARED, parentId, fileName);
        }
        if (parentId == null) {
            return fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                    ownerUserId, spaceType, fileName);
        }
        return fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                ownerUserId, spaceType, parentId, fileName);
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
