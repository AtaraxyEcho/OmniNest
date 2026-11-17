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
import lombok.extern.slf4j.Slf4j;
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
@Slf4j
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
        cancelInternal(ownerUserId, uploadId, false);
    }

    /**
     * 供后台清理任务强制取消滞留会话。
     *
     * <p>用户侧取消必须拒绝 {@code FINALIZING}/{@code SCANNING}；但清理任务面对的是
     * 超过 TTL 的僵尸会话，任务早已不在运行，继续拒绝会让会话行、隔离对象与配额
     * 预留永久泄漏。</p>
     *
     * @param ownerUserId 会话所有者
     * @param uploadId 上传会话标识
     */
    void forceCancelForCleanup(UUID ownerUserId, String uploadId) {
        cancelInternal(ownerUserId, uploadId, true);
    }

    private void cancelInternal(UUID ownerUserId, String uploadId, boolean force) {
        CancelTarget target = transactionTemplate.execute(
                status -> prepare(ownerUserId, uploadId, force));
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

    /**
     * 内容丢失（合并产物与 multipart 均不存在）时把会话落到 EXPIRED 并释放预留。
     *
     * <p>进入 EXPIRED 后不会再走完成或取消路径，预留必须在这里释放，否则共享空间与
     * 个人配额都会被一条死会话永久占住。</p>
     *
     * @param ownerUserId 会话所有者
     * @param uploadId 上传会话标识
     */
    void expireForContentLoss(UUID ownerUserId, String uploadId) {
        try {
            transactionTemplate.executeWithoutResult(status -> {
                FileUploadSession session = sessionRepository
                        .findByUploadIdAndOwnerUserId(uploadId, ownerUserId)
                        .orElse(null);
                if (session == null
                        || UploadStatus.COMPLETED.getValue().equals(session.getStatus())
                        || UploadStatus.SCANNING.getValue().equals(session.getStatus())) {
                    return;
                }
                String previousStatus = session.getStatus();
                boolean reservationLive = !UploadStatus.REJECTED.getValue().equals(previousStatus)
                        && !UploadStatus.CANCELLED.getValue().equals(previousStatus)
                        && !UploadStatus.EXPIRED.getValue().equals(previousStatus);
                session.setStatus(UploadStatus.EXPIRED.getValue());
                if (reservationLive && session.getQuotaReservationId() != null) {
                    storageQuotaService.releaseReservation("UPLOAD", session.getId());
                    session.setQuotaReservationId(null);
                }
                if (reservationLive && session.getSpaceType() == SpaceType.SHARED) {
                    sharedSpaceQuotaService.releaseReservation(session.getTotalSizeBytes());
                }
                sessionRepository.save(session);
            });
        } catch (RuntimeException exception) {
            log.warn("上传会话过期状态落库失败: uploadId={}, errorType={}",
                    uploadId, exception.getClass().getSimpleName());
        }
    }

    private CancelTarget prepare(UUID ownerUserId, String uploadId, boolean force) {
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
        if (!force
                && (UploadStatus.FINALIZING.getValue().equals(status)
                || UploadStatus.SCANNING.getValue().equals(status))) {
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
