package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.UploadStatus;
import com.omninest.modules.file.repository.FileUploadPartRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 上传会话取消状态机。
 *
 * <p>先在短事务内把会话置为 {@code CANCELLED}，再在事务外中止对象存储，最后删除会话。
 * 完成流程持有 {@code FINALIZING}/{@code SCANNING} 时拒绝取消：分片合并或安全扫描任务
 * 已经受理，删除对象会让任务进入不可恢复的失败态。</p>
 *
 * @author OmniNest
 */
@Service
public class FileUploadCancellationService {

    private final FileUploadSessionRepository sessionRepository;
    private final FileUploadPartRepository partRepository;
    private final StorageQuotaService storageQuotaService;
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
    private final ObjectStorageClient objectStorageClient;
    private final TransactionTemplate transactionTemplate;

    public FileUploadCancellationService(
            FileUploadSessionRepository sessionRepository,
            FileUploadPartRepository partRepository,
            StorageQuotaService storageQuotaService,
            SharedSpaceQuotaService sharedSpaceQuotaService,
            ObjectStorageClient objectStorageClient,
            TransactionTemplate transactionTemplate
    ) {
        this.sessionRepository = sessionRepository;
        this.partRepository = partRepository;
        this.storageQuotaService = storageQuotaService;
        this.sharedSpaceQuotaService = sharedSpaceQuotaService;
        this.objectStorageClient = objectStorageClient;
        this.transactionTemplate = transactionTemplate;
    }

    void cancel(UUID ownerUserId, String uploadId) {
        CancelTarget target = transactionTemplate.execute(
                status -> prepare(ownerUserId, uploadId));
        if (target == null) {
            return;
        }
        ObjectStorageKey key = new ObjectStorageKey(target.targetBucket(), target.targetObjectKey());
        // 外部中止在数据库事务之外执行：失败时会话保持 CANCELLED，客户端可重试取消。
        if (target.direct()) {
            if (objectStorageClient.objectExists(key)) {
                objectStorageClient.removeObject(key);
            }
        } else {
            objectStorageClient.abortMultipartUpload(key, target.uploadId());
        }
        transactionTemplate.executeWithoutResult(
                status -> finish(ownerUserId, uploadId, target.quotaAlreadyReleased()));
    }

    private CancelTarget prepare(UUID ownerUserId, String uploadId) {
        FileUploadSession session = sessionRepository
                .findForUpdateByUploadIdAndOwnerUserId(uploadId, ownerUserId)
                .orElse(null);
        if (session == null) {
            return null;
        }
        String status = session.getStatus();
        if (UploadStatus.COMPLETED.getValue().equals(status)) {
            return null;
        }
        if (UploadStatus.FINALIZING.getValue().equals(status)
                || UploadStatus.SCANNING.getValue().equals(status)) {
            throw new BusinessException(ErrorCode.CONFLICT, "上传正在完成或安全扫描，不能取消");
        }
        if (!UploadStatus.CANCELLED.getValue().equals(status)) {
            session.setStatus(UploadStatus.CANCELLED.getValue());
            sessionRepository.save(session);
        }
        return new CancelTarget(
                session.getTargetBucket(),
                session.getTargetObjectKey(),
                session.getUploadId(),
                isDirectUpload(session),
                // REJECTED 会话的共享预留已在终态失败结算中释放，清理任务再次取消时不得重扣。
                UploadStatus.REJECTED.getValue().equals(status)
        );
    }

    private void finish(UUID ownerUserId, String uploadId, boolean quotaAlreadyReleased) {
        FileUploadSession current = sessionRepository
                .findForUpdateByUploadIdAndOwnerUserId(uploadId, ownerUserId)
                .orElse(null);
        if (current == null) {
            return;
        }
        if (!UploadStatus.CANCELLED.getValue().equals(current.getStatus())) {
            throw new BusinessException(ErrorCode.CONFLICT, "上传状态已变化，取消未完成");
        }
        partRepository.deleteByUploadSessionId(current.getId());
        if (current.getQuotaReservationId() != null) {
            storageQuotaService.releaseReservation("UPLOAD", current.getId());
        }
        if (current.getSpaceType() == SpaceType.SHARED && !quotaAlreadyReleased) {
            // 预留释放与会话删除同事务提交：重试取消时若会话已删，不会再重复扣减。
            sharedSpaceQuotaService.releaseReservation(current.getTotalSizeBytes());
        }
        sessionRepository.delete(current);
    }

    private boolean isDirectUpload(FileUploadSession session) {
        return session.getUploadId() != null && session.getUploadId().startsWith("DIRECT-");
    }

    private record CancelTarget(
            String targetBucket,
            String targetObjectKey,
            String uploadId,
            boolean direct,
            boolean quotaAlreadyReleased
    ) {
    }
}
