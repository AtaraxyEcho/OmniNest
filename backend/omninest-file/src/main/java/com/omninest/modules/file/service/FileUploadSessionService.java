package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.UploadStatus;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.TokenBucketRateLimiter;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageCompletedPart;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.upload.FileUploadSettings;
import com.omninest.modules.file.config.FileUploadLimitsProperties;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FileUploadPart;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.dto.CompleteFileUploadPartRequest;
import com.omninest.modules.file.dto.CompleteFileUploadRequest;
import com.omninest.modules.file.dto.CreateFileUploadSessionRequest;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.dto.FileUploadPartDto;
import com.omninest.modules.file.dto.FileUploadPartsDto;
import com.omninest.modules.file.dto.FileUploadPolicyDto;
import com.omninest.modules.file.dto.FileUploadCompleteResultDto;
import com.omninest.modules.file.dto.FileUploadSessionDto;
import com.omninest.modules.file.service.FileIngressLifecycleService.IngressCommand;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.FileUploadPartRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaTypeFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.util.MimeType;

/**
 * 文件上传会话及上传完成事务服务。
 *
 * @author OmniNest
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class FileUploadSessionService {

    /** 创建会话时只预签名前若干分片，其余由客户端按需拉取，避免事务内生成 1000 个 URL。 */
    private static final int INITIAL_PRESIGNED_PARTS = 10;
    private static final Duration SCAN_WINDOW = Duration.ofHours(24);

    private final FileUploadSessionRepository fileUploadSessionRepository;
    private final FileUploadPartRepository fileUploadPartRepository;
    private final FileNodeRepository fileNodeRepository;
    private final FileObjectRepository fileObjectRepository;
    private final StorageQuotaService storageQuotaService;
    private final TokenBucketRateLimiter bandwidthLimiter;
    private final ObjectStorageClient objectStorageClient;
    private final FilePostProcessingTaskService postProcessingTaskService;
    private final ObjectStorageBuckets objectStorageBuckets;
    private final FileUploadSettings uploadSettings;
    private final FileUploadLimitsProperties uploadLimits;
    private final FileIngressLifecycleService ingressLifecycleService;
    private final FileIngressScanTaskService ingressScanTaskService;
    private final ConfigValueProvider configValueProvider;
    private final RuntimeConfigCache runtimeConfigCache;
    private final SharedSpaceService sharedSpaceService;
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
    private final FileContentChangePublisher fileContentChangePublisher;
    private final FileUploadCancellationService cancellationService;
    private final TransactionTemplate transactionTemplate;

    public FileUploadPolicyDto uploadPolicy() {
        return new FileUploadPolicyDto(
                uploadLimits.getDirectUploadMaxBytes(),
                uploadLimits.getDefaultPartSizeBytes(),
                uploadLimits.getMaxPartSizeBytes(),
                uploadLimits.getMaxTotalParts(),
                uploadLimits.getMaxConcurrentParts(),
                uploadLimits.maxFileSizeBytes(),
                uploadSettings.presignedUrlTtl().getSeconds(),
                uploadSettings.maxPresignedPartsPerSecond(),
                bandwidthLimitEnabled()
        );
    }

    public FileUploadSessionDto createSession(UUID ownerUserId, CreateFileUploadSessionRequest request) {
        // 确定目标空间类型
        SpaceType spaceType = SpaceType.PERSONAL;
        if (request.spaceType() != null) {
            try {
                spaceType = SpaceType.fromValue(request.spaceType());
            } catch (IllegalArgumentException e) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "不支持的空间类型: " + request.spaceType());
            }
        }

        requireActiveSessionBudget(ownerUserId);

        String fileName = normalizeFileName(request.fileName());
        UUID asVersionOfFileId = request.asVersionOfFileId();
        if (asVersionOfFileId != null) {
            FileNode versionTarget = fileNodeRepository
                    .findByIdAndOwnerUserIdAndDeletedFalse(asVersionOfFileId, ownerUserId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "目标文件不存在"));
            // 版本继承目标节点所在空间：客户端漏传或误传 spaceType 会把共享空间文件的
            // 新版本记进上传者个人配额，而删除共享文件时又按共享跳过个人扣减。
            spaceType = versionTarget.getSpaceType();
        }
        if (spaceType == SpaceType.SHARED) {
            // 共享空间上传必须具备 CAN_UPLOAD 角色能力；容量预占放在会话落库事务内。
            sharedSpaceService.requireSharedWrite(ownerUserId);
        } else {
            // 配额预检先于 multipart 初始化，避免配额不足时仍在隔离桶创建上传。
            storageQuotaService.checkQuota(ownerUserId, request.sizeBytes());
        }

        FileNode parent = resolveParent(ownerUserId, request.parentId(), spaceType);
        if (asVersionOfFileId == null) {
            if (spaceType == SpaceType.SHARED) {
                if (sameNameExists(ownerUserId, spaceType, request.parentId(), fileName)) {
                    throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
                }
            } else {
                checkActiveNameConflict(ownerUserId, spaceType, request.parentId(), fileName);
            }
        }

        String mimeType = normalizeMimeType(request.mimeType(), fileName);
        UUID sessionId = UUID.randomUUID();
        Instant expiresAt = Instant.now().plus(uploadSettings.sessionTtl());
        SpaceType targetSpaceType = spaceType;
        // 签名限流依赖 Redis，先于任何数据库事务与对象存储调用执行。
        checkBandwidthLimit(ownerUserId);
        if (request.partSizeBytes() == null && request.sizeBytes() <= uploadLimits.getDirectUploadMaxBytes()) {
            return transactionTemplate.execute(status -> createDirectSession(
                    ownerUserId,
                    request,
                    parent,
                    fileName,
                    mimeType,
                    targetSpaceType,
                    sessionId,
                    expiresAt,
                    reserveUploadQuota(ownerUserId, targetSpaceType, sessionId, request.sizeBytes(), expiresAt)
            ));
        }

        int partSizeBytes = resolvePartSizeBytes(request.sizeBytes(), request.partSizeBytes());
        int totalParts = resolveTotalParts(request.sizeBytes(), partSizeBytes);
        String bucket = objectStorageBuckets.quarantine();
        String objectKey = "uploads/" + ownerUserId + "/" + sessionId + "/" + fileName;
        ObjectStorageKey storageKey = new ObjectStorageKey(bucket, objectKey);
        // multipart 初始化是对象存储网络调用，不能占用数据库连接与事务。
        String uploadId = objectStorageClient.initiateMultipartUpload(storageKey, mimeType);
        try {
            return transactionTemplate.execute(status -> {
                UUID quotaReservationId = reserveUploadQuota(
                        ownerUserId, targetSpaceType, sessionId, request.sizeBytes(), expiresAt);
                FileUploadSession session = new FileUploadSession();
                session.setId(sessionId);
                session.setOwnerUserId(ownerUserId);
                session.setTargetParentId(parent == null ? null : parent.getId());
                session.setAsVersionOfFileId(asVersionOfFileId);
                session.setFileName(fileName);
                session.setTotalSizeBytes(request.sizeBytes());
                session.setPartSizeBytes(partSizeBytes);
                session.setTotalParts(totalParts);
                session.setUploadedParts(0);
                session.setMimeType(mimeType);
                session.setSha256(normalizeSha256(request.sha256()));
                session.setStatus(UploadStatus.CREATED.getValue());
                session.setUploadId(uploadId);
                session.setTargetBucket(bucket);
                session.setTargetObjectKey(objectKey);
                session.setExpiresAt(expiresAt);
                session.setQuotaReservationId(quotaReservationId);
                session.setSpaceType(targetSpaceType);
                FileUploadSession saved = fileUploadSessionRepository.save(session);
                List<FileUploadPart> parts = fileUploadPartRepository.saveAll(buildParts(saved));
                // 预签名消耗签名配额：一次会话只发首批，后续分片由按需接口限额拉取。
                return toSessionDto(saved, parts, true);
            });
        } catch (RuntimeException exception) {
            abortInitiatedUpload(storageKey, uploadId);
            throw exception;
        }
    }

    private UUID reserveUploadQuota(
            UUID ownerUserId,
            SpaceType spaceType,
            UUID sessionId,
            long sizeBytes,
            Instant expiresAt) {
        if (spaceType == SpaceType.SHARED) {
            // 与会话落库同事务：会话创建失败时预留随事务回滚，不会留下无主额度。
            sharedSpaceQuotaService.reserve(sizeBytes);
            return null;
        }
        return storageQuotaService.reserve(ownerUserId, "UPLOAD", sessionId, sizeBytes, expiresAt);
    }

    private void abortInitiatedUpload(ObjectStorageKey storageKey, String uploadId) {
        try {
            objectStorageClient.abortMultipartUpload(storageKey, uploadId);
        } catch (RuntimeException abortFailure) {
            // 落库已经失败，原异常优先抛出；残留 multipart 由隔离桶过期清理兜底。
            log.warn("上传会话落库失败后中止 multipart 失败: uploadId={}", uploadId, abortFailure);
        }
    }

    private FileUploadSessionDto createDirectSession(
            UUID ownerUserId,
            CreateFileUploadSessionRequest request,
            FileNode parent,
            String fileName,
            String mimeType,
            SpaceType spaceType,
            UUID sessionId,
            Instant expiresAt,
            UUID quotaReservationId
    ) {
        String bucket = objectStorageBuckets.quarantine();
        String objectKey = "uploads/" + ownerUserId + "/" + sessionId + "/" + fileName;

        FileUploadSession session = new FileUploadSession();
        session.setId(sessionId);
        session.setOwnerUserId(ownerUserId);
        session.setTargetParentId(parent == null ? null : parent.getId());
        session.setAsVersionOfFileId(request.asVersionOfFileId());
        session.setFileName(fileName);
        session.setTotalSizeBytes(request.sizeBytes());
        session.setPartSizeBytes(Math.toIntExact(Math.min(request.sizeBytes(), Integer.MAX_VALUE)));
        session.setTotalParts(1);
        session.setUploadedParts(0);
        session.setMimeType(mimeType);
        session.setSha256(normalizeSha256(request.sha256()));
        session.setStatus(UploadStatus.CREATED.getValue());
        session.setUploadId("DIRECT-" + sessionId);
        session.setTargetBucket(bucket);
        session.setTargetObjectKey(objectKey);
        session.setExpiresAt(expiresAt);
        session.setQuotaReservationId(quotaReservationId);
        session.setSpaceType(spaceType);
        FileUploadSession saved = fileUploadSessionRepository.save(session);
        return toSessionDto(saved, List.of(), true);
    }

    @Transactional(readOnly = true)
    public FileUploadPartsDto listParts(UUID ownerUserId, String uploadId) {
        FileUploadSession session = findSession(ownerUserId, uploadId);
        List<FileUploadPart> parts = fileUploadPartRepository.findByUploadSessionIdOrderByPartNumber(session.getId());
        return toPartsDto(session, parts, false);
    }

    @Transactional(rollbackFor = Exception.class, noRollbackFor = UploadSessionExpiredException.class)
    public FileUploadPartsDto completePart(
            UUID ownerUserId,
            String uploadId,
            int partNumber,
            CompleteFileUploadPartRequest request
    ) {
        // 不锁会话行、不读全量分片：3 路并发确认原会串行，1,000 分片产生百万行读取。
        FileUploadSession session = findSession(ownerUserId, uploadId);
        ensureCompletable(session);
        FileUploadPart part = fileUploadPartRepository.findByUploadSessionIdAndPartNumber(session.getId(), partNumber)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传分片不存在"));
        String eTag = normalizeETag(request == null ? null : request.eTag());
        int updated = fileUploadPartRepository.markPartCompleted(
                session.getId(), partNumber, eTag, UploadStatus.COMPLETED.getValue());
        if (updated == 0) {
            // 并发确认同一分片时，后到的请求读到的可能是更新前的快照，必须回查当前状态。
            part = fileUploadPartRepository.findByUploadSessionIdAndPartNumber(session.getId(), partNumber)
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传分片不存在"));
            if (!UploadStatus.COMPLETED.getValue().equals(part.getStatus())) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传分片状态异常");
            }
            // 已完成分片的重传：只刷新 ETag，不重复累加 uploaded_parts。
            // 否则最终合并会拿旧 ETag 去对 MinIO 的新分片，直接 InvalidPart。
            fileUploadPartRepository.updateCompletedPartETag(
                    session.getId(), partNumber, eTag, UploadStatus.COMPLETED.getValue());
        }
        if (updated > 0) {
            int sessionUpdated =
                    fileUploadSessionRepository.incrementUploadedParts(session.getId(), Instant.now());
            if (sessionUpdated == 0) {
                // 事务回滚会一并撤销上面的分片确认，不会留下半完成状态。
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传会话状态已变化");
            }
        }
        // 批量更新已清空持久化上下文；保留内存值仅用于构造当前分片的轻量响应。
        part.setETag(eTag);
        part.setStatus(UploadStatus.COMPLETED.getValue());
        Instant now = Instant.now();
        if (session.getExpiresAt().minus(Duration.ofHours(1)).isBefore(now)) {
            Instant newExpiresAt = now.plus(uploadSettings.sessionTtl());
            int extended = fileUploadSessionRepository.extendExpiresAtIfNeeded(
                    session.getId(), now.plus(Duration.ofHours(1)), newExpiresAt, now);
            if (extended > 0) {
                // 配额预留必须跟着会话一起延期：预留先到期会被回收成 EXPIRED 并释放额度，
                // 之后的结算遇 EXPIRED 直接空转，这笔上传量要等对账兜底才回到用量。
                storageQuotaService.extendReservation("UPLOAD", session.getId(), newExpiresAt);
            }
        }
        return toPartsDto(session, List.of(part), false);
    }

    /**
     * 完成上传会话。
     *
     * <p>分片合并是耗时外部 I/O，不能在持有数据库悲观锁与连接时执行。流程拆为三段：
     * 短事务校验并置 FINALIZING；无事务执行 MinIO 合并；短事务落扫描/入库状态。
     * 合并成功但后续事务失败时，重试会凭 {@code NoSuchUpload + objectExists} 幂等恢复。</p>
     */
    public FileUploadCompleteResultDto completeSession(
            UUID ownerUserId,
            String uploadId,
            CompleteFileUploadRequest request
    ) {
        MultipartCompletion completion;
        // 直传的存在性探测放在事务外：对象键在会话创建后不再变化，而一次 HEAD 的往返
        // 若留在持锁事务里，会把悲观锁与数据库连接一起占住。
        boolean directObjectReady = directObjectReady(ownerUserId, uploadId);
        try {
            completion = transactionTemplate.execute(
                    status -> prepareCompletion(ownerUserId, uploadId, request, directObjectReady));
        } catch (UploadSessionExpiredException exception) {
            markSessionExpired(ownerUserId, uploadId);
            throw exception;
        }
        if (completion == null) {
            throw new IllegalStateException("上传完成事务未返回结果");
        }
        if (completion.immediateResult() != null) {
            return completion.immediateResult();
        }
        try {
            completeMultipartObject(completion);
        } catch (UploadContentLostException exception) {
            // 合并没有产出对象且 multipart 已不存在：重试不可能成功，直接进入终态。
            markSessionExpired(ownerUserId, uploadId);
            throw exception;
        } catch (RuntimeException exception) {
            // 对象已经存在说明合并已成功，此时回退 FINALIZING 会让并发的成功线程
            // 在 finalize 阶段因状态不符而回滚；保持 FINALIZING 交给重试幂等恢复。
            if (!objectStorageClient.objectExists(completion.key())) {
                resetFinalizing(ownerUserId, uploadId);
            }
            throw exception;
        }
        try {
            FileUploadCompleteResultDto result = transactionTemplate.execute(
                    status -> finalizeCompletion(ownerUserId, uploadId));
            if (result == null) {
                throw new IllegalStateException("上传完成事务未返回结果");
            }
            return result;
        } catch (RuntimeException exception) {
            resetFinalizing(ownerUserId, uploadId);
            throw exception;
        }
    }

    private MultipartCompletion prepareCompletion(
            UUID ownerUserId,
            String uploadId,
            CompleteFileUploadRequest request,
            boolean directObjectReady
    ) {
        FileUploadSession session = findSessionForUpdate(ownerUserId, uploadId);
        if (UploadStatus.COMPLETED.getValue().equals(session.getStatus())) {
            return new MultipartCompletion(completedResult(session), null, null, List.of());
        }
        if (UploadStatus.SCANNING.getValue().equals(session.getStatus())) {
            return new MultipartCompletion(scanningResult(session), null, null, List.of());
        }
        boolean resuming = UploadStatus.FINALIZING.getValue().equals(session.getStatus());
        if (!resuming) {
            ensureCompletable(session);
        }
        if (isDirectUpload(session)) {
            return new MultipartCompletion(
                    completeDirectSession(ownerUserId, session, request, directObjectReady), null, null, List.of());
        }
        applyCompletedPartRequest(session, request == null ? null : request.parts());

        String sha256 = normalizeSha256(request == null ? null : request.sha256());
        if (sha256 != null && session.getSha256() != null && !session.getSha256().equalsIgnoreCase(sha256)) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "文件摘要不一致");
        }
        if (sha256 != null) {
            session.setSha256(sha256);
        }

        List<FileUploadPart> parts = fileUploadPartRepository.findByUploadSessionIdOrderByPartNumber(session.getId());
        ensureAllPartsCompleted(session, parts);

        resolveParent(ownerUserId, session.getTargetParentId(), session.getSpaceType());
        UUID asVersionOfFileId = resolveCompletionVersionTarget(ownerUserId, session, request);
        if (asVersionOfFileId == null
                && sameNameExists(ownerUserId, session.getSpaceType(), session.getTargetParentId(), session.getFileName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }

        ObjectStorageKey key = new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey());
        session.setStatus(UploadStatus.FINALIZING.getValue());
        fileUploadSessionRepository.save(session);
        return new MultipartCompletion(
                null,
                key,
                session.getUploadId(),
                toCompletedParts(parts)
        );
    }

    private void completeMultipartObject(MultipartCompletion completion) {
        try {
            objectStorageClient.completeMultipartUpload(
                    completion.key(), completion.s3UploadId(), completion.parts());
        } catch (RuntimeException exception) {
            if (objectStorageClient.objectExists(completion.key())) {
                // 上一次已完成合并但收尾事务失败：MinIO 对重复合并返回 NoSuchUpload，
                // 对象存在即可视为合并成功，继续落业务状态。
                log.info("分片合并已在上次尝试完成，继续完成会话: uploadId={}", completion.s3UploadId());
                return;
            }
            if (!objectStorageClient.multipartUploadExists(completion.key(), completion.s3UploadId())) {
                // 两次探测之间并发线程可能刚完成合并并销毁了 uploadId：
                // 不复核会把成功完成的会话误判为内容丢失并置为 EXPIRED。
                if (objectStorageClient.objectExists(completion.key())) {
                    log.info("并发合并已完成，继续完成会话: uploadId={}", completion.s3UploadId());
                    return;
                }
                log.warn("分片合并失败且 multipart 与合并结果均不存在: uploadId={}, errorType={}",
                        completion.s3UploadId(), exception.getClass().getSimpleName());
                throw new UploadContentLostException();
            }
            throw exception;
        }
    }

    private FileUploadCompleteResultDto finalizeCompletion(UUID ownerUserId, String uploadId) {
        FileUploadSession session = findSessionForUpdate(ownerUserId, uploadId);
        if (UploadStatus.SCANNING.getValue().equals(session.getStatus())) {
            return scanningResult(session);
        }
        if (!UploadStatus.FINALIZING.getValue().equals(session.getStatus())) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传会话状态不允许完成");
        }
        resolveParent(ownerUserId, session.getTargetParentId(), session.getSpaceType());
        UUID asVersionOfFileId = resolveCompletionVersionTarget(ownerUserId, session, null);
        if (asVersionOfFileId == null
                && sameNameExists(ownerUserId, session.getSpaceType(), session.getTargetParentId(), session.getFileName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }
        return dispatchSecurityScan(ownerUserId, session, asVersionOfFileId);
    }

    private void resetFinalizing(UUID ownerUserId, String uploadId) {
        try {
            transactionTemplate.executeWithoutResult(status -> {
                FileUploadSession session = findSessionForUpdate(ownerUserId, uploadId);
                if (UploadStatus.FINALIZING.getValue().equals(session.getStatus())) {
                    session.setStatus(UploadStatus.UPLOADING.getValue());
                    fileUploadSessionRepository.save(session);
                }
            });
        } catch (RuntimeException exception) {
            log.warn("上传会话 FINALIZING 状态回退失败: uploadId={}, errorType={}",
                    uploadId, exception.getClass().getSimpleName());
        }
    }

    private void markSessionExpired(UUID ownerUserId, String uploadId) {
        cancellationService.expireForContentLoss(ownerUserId, uploadId);
    }

    /**
     * 分片合并所需的不可变上下文；immediateResult 非空表示无需外部合并。
     */
    private record MultipartCompletion(
            FileUploadCompleteResultDto immediateResult,
            ObjectStorageKey key,
            String s3UploadId,
            List<ObjectStorageCompletedPart> parts
    ) {
    }

    /**
     * 版本目标只认创建会话时持久化的值。
     *
     * <p>创建阶段已按该目标确定空间、共享权限与配额；完成阶段再从请求读一次，
     * 客户端就能在两次调用之间把个人会话改成共享版本上传（或反过来）绕过校验。</p>
     */
    private UUID resolveCompletionVersionTarget(
            UUID ownerUserId,
            FileUploadSession session,
            CompleteFileUploadRequest request
    ) {
        UUID stored = session.getAsVersionOfFileId();
        UUID requested = request == null ? null : request.asVersionOfFileId();
        if (requested != null && !requested.equals(stored)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "版本目标与上传会话不一致");
        }
        if (stored == null) {
            return null;
        }
        FileNode target = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(stored, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "版本目标文件不存在"));
        if (target.getSpaceType() != session.getSpaceType()) {
            throw new BusinessException(ErrorCode.CONFLICT, "版本目标空间已变化，请重新开始上传");
        }
        return stored;
    }

    /**
     * 取消上传会话；状态机实现见 {@link FileUploadCancellationService}。
     *
     * @param ownerUserId 当前用户 ID
     * @param uploadId 上传会话 ID
     */
    public void cancelSession(UUID ownerUserId, String uploadId) {
        cancellationService.cancel(ownerUserId, uploadId);
    }

    /**
     * 重新发布已有文件的处理任务，用于恢复媒体模块与文件节点之间的派生数据。
     *
     * @param ownerUserId 当前用户 ID
     * @param fileId 文件节点 ID
     * @return 已重新提交处理的文件节点
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto reprocessExistingFile(UUID ownerUserId, UUID fileId) {
        FileNode file = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (!NodeType.FILE.getValue().equals(file.getNodeType()) || file.getCurrentObjectId() == null) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "仅支持重新处理具有存储对象的文件");
        }
        FileObject fileObject = fileObjectRepository.findById(file.getCurrentObjectId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件存储对象不存在"));
        UUID mediaAutoImportTaskId = publishFileUploadedAfterCommit(file, fileObject, ownerUserId);
        return toFileNodeDto(file, mediaAutoImportTaskId);
    }

    public FileUploadPartDto getPartUrl(UUID ownerUserId, String uploadId, int partNumber) {
        FileUploadSession session = findSession(ownerUserId, uploadId);
        ensureCompletable(session);

        // 带宽限速：控制 presigned URL 签发频率
        checkBandwidthLimit(ownerUserId);
        if (isDirectUpload(session)) {
            // 直传只有一个“分片”：复用该端点重签预签名 URL，供暂停超过有效期后恢复。
            ObjectStorageKey directKey =
                    new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey());
            Instant directExpiresAt = Instant.now().plus(uploadSettings.presignedUrlTtl());
            return new FileUploadPartDto(
                    1,
                    session.getTotalSizeBytes(),
                    UploadStatus.PENDING.getValue(),
                    null,
                    objectStorageClient.createUploadUrl(directKey, uploadSettings.presignedUrlTtl()).toString(),
                    directExpiresAt
            );
        }

        FileUploadPart part = fileUploadPartRepository
                .findByUploadSessionIdAndPartNumber(session.getId(), partNumber)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传分片不存在"));
        if (isCompletedPart(part)) {
            return new FileUploadPartDto(part.getPartNumber(), part.getSizeBytes(),
                    part.getStatus(), part.getETag(), null, null);
        }
        ObjectStorageKey key = new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey());
        Instant expiresAt = Instant.now().plus(uploadSettings.presignedUrlTtl());
        String url = objectStorageClient.createMultipartUploadPartUrl(
                key, session.getUploadId(), partNumber, uploadSettings.presignedUrlTtl()
        ).toString();
        return new FileUploadPartDto(part.getPartNumber(), part.getSizeBytes(),
                part.getStatus(), part.getETag(), url, expiresAt);
    }

    private void checkBandwidthLimit(UUID ownerUserId) {
        if (!bandwidthLimitEnabled()) {
            return;
        }
        TokenBucketRateLimiter.TokenBucketResult result = bandwidthLimiter.tryConsumeToken(
                "upload:" + ownerUserId,
                uploadSettings.presignedPartBurstCapacity(),
                uploadSettings.maxPresignedPartsPerSecond()
        );
        if (!result.allowed()) {
            throw new BusinessException(ErrorCode.RATE_LIMITED,
                    "上传请求过于频繁，请 %d 毫秒后重试".formatted(result.retryAfterMs()));
        }
    }

    @Transactional(rollbackFor = Exception.class)
    public FileUploadSessionDto extendSession(UUID ownerUserId, String uploadId) {
        FileUploadSession session = findSessionForUpdate(ownerUserId, uploadId);
        if (UploadStatus.COMPLETED.getValue().equals(session.getStatus())) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传会话已完成，无需延期");
        }
        if (UploadStatus.EXPIRED.getValue().equals(session.getStatus())) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传会话已过期，无法延期");
        }
        session.setExpiresAt(Instant.now().plus(uploadSettings.sessionTtl()));
        if (session.getQuotaReservationId() != null) {
            storageQuotaService.extendReservation("UPLOAD", session.getId(), session.getExpiresAt());
        }
        FileUploadSession saved = fileUploadSessionRepository.save(session);
        // 直传恢复必须重新签发预签名 URL，只延期会话无法避免 403。
        return toSessionDto(saved, List.of(), isDirectUpload(saved));
    }

    private FileUploadSession findSessionForUpdate(UUID ownerUserId, String uploadId) {
        return fileUploadSessionRepository
                .findForUpdateByUploadIdAndOwnerUserId(uploadId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "上传会话不存在"));
    }

    private FileUploadSession findSession(UUID ownerUserId, String uploadId) {
        return fileUploadSessionRepository.findByUploadIdAndOwnerUserId(uploadId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "上传会话不存在"));
    }

    private FileUploadCompleteResultDto completeDirectSession(
            UUID ownerUserId,
            FileUploadSession session,
            CompleteFileUploadRequest request,
            boolean objectReady
    ) {
        String sha256 = normalizeSha256(request == null ? null : request.sha256());
        if (sha256 != null && session.getSha256() != null && !session.getSha256().equalsIgnoreCase(sha256)) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "文件摘要不一致");
        }
        if (sha256 != null) {
            session.setSha256(sha256);
        }

        resolveParent(ownerUserId, session.getTargetParentId(), session.getSpaceType());
        UUID asVersionOfFileId = resolveCompletionVersionTarget(ownerUserId, session, request);
        if (asVersionOfFileId == null
                && sameNameExists(ownerUserId, session.getSpaceType(), session.getTargetParentId(), session.getFileName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }

        if (!objectReady) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "文件内容尚未上传完成");
        }

        return dispatchSecurityScan(ownerUserId, session, asVersionOfFileId);
    }

    /**
     * 直传内容是否已在对象存储就绪；非直传会话返回 true，交给分片路径自行校验。
     *
     * <p>预签名 PUT 不强制 Content-Length；“申报 100 字节、实传 20GB”的对象必须在
     * 入队扫描前用 HEAD 实际字节数拦截并删除隔离对象。</p>
     */
    private boolean directObjectReady(UUID ownerUserId, String uploadId) {
        return fileUploadSessionRepository.findByUploadIdAndOwnerUserId(uploadId, ownerUserId)
                .filter(this::isDirectUpload)
                .map(session -> {
                    ObjectStorageKey key = new ObjectStorageKey(
                            session.getTargetBucket(),
                            session.getTargetObjectKey()
                    );
                    long actualSize = objectStorageClient.objectSize(key);
                    if (actualSize < 0L) {
                        return false;
                    }
                    if (actualSize != session.getTotalSizeBytes()) {
                        removeObjectQuietly(key, "清理直传大小不一致的隔离对象失败");
                        throw new BusinessException(
                                ErrorCode.FILE_UPLOAD_FAILED,
                                "上传内容大小与申报不一致"
                        );
                    }
                    return true;
                })
                .orElse(true);
    }

    private void removeObjectQuietly(ObjectStorageKey key, String message) {
        try {
            objectStorageClient.removeObject(key);
        } catch (RuntimeException exception) {
            log.warn("{}: bucket={}, errorType={}", message, key.bucket(), exception.getClass().getSimpleName());
        }
    }

    /**
     * 在当前事务内创建媒体导入与 post-process 任务并写入 outbox，
     * 避免请求线程在事务提交后直发 RabbitMQ（防止 MQ 故障阻塞请求、防进程崩溃丢任务）。
     */
    private UUID publishFileUploadedAfterCommit(FileNode savedFile, FileObject savedObject, UUID ownerUserId) {
        return fileContentChangePublisher.publish(savedFile, savedObject, ownerUserId);
    }


    private void ensureCompletable(FileUploadSession session) {
        if (Instant.now().isAfter(session.getExpiresAt())) {
            session.setStatus(UploadStatus.EXPIRED.getValue());
            // 过期标记必须在抛出业务异常后仍然落库：调用方用 noRollbackFor 放行本异常，
            // 否则状态会随事务回滚回 INITIATED/UPLOADING。
            fileUploadSessionRepository.save(session);
            throw new UploadSessionExpiredException();
        }
        if (!UploadStatus.CREATED.getValue().equals(session.getStatus()) && !UploadStatus.UPLOADING.getValue().equals(session.getStatus())) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传会话状态不允许完成");
        }
    }

    /**
     * 上传会话过期：调用方以 {@code noRollbackFor} 放行，使 EXPIRED 状态与异常同时生效。
     */
    public static final class UploadSessionExpiredException extends BusinessException {
        public UploadSessionExpiredException() {
            super(ErrorCode.FILE_UPLOAD_FAILED, "上传会话已过期");
        }
    }

    /**
     * 分片合并没有产出对象，且 multipart 已不存在：会话无法重试完成。
     */
    public static final class UploadContentLostException extends BusinessException {
        public UploadContentLostException() {
            super(ErrorCode.FILE_UPLOAD_FAILED, "上传内容已失效，请重新上传");
        }
    }

    /**
     * 活跃上传会话并发上限：未完成会话会占用隔离桶 multipart 与配额预留，
     * 超限时要求先完成或等待过期回收，防止认证用户刷会话资源。
     */
    private void requireActiveSessionBudget(UUID ownerUserId) {
        long active = fileUploadSessionRepository.countByOwnerUserIdAndStatusInAndExpiresAtAfter(
                ownerUserId,
                List.of(
                        UploadStatus.CREATED.getValue(),
                        UploadStatus.UPLOADING.getValue(),
                        UploadStatus.FINALIZING.getValue()
                ),
                Instant.now()
        );
        if (active >= uploadLimits.getMaxActiveUploadSessions()) {
            throw new BusinessException(ErrorCode.RATE_LIMITED,
                    "活跃上传会话过多（上限 " + uploadLimits.getMaxActiveUploadSessions() + "），请先完成或等待过期会话释放");
        }
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

    private boolean bandwidthLimitEnabled() {
        return runtimeConfigValue("upload.rate.enabled", "upload.bandwidth.enabled")
                .map(value -> "true".equalsIgnoreCase(value.trim()) || "1".equals(value.trim()))
                .orElseGet(uploadSettings::bandwidthLimitEnabled);
    }

    private Optional<String> runtimeConfigValue(String canonicalKey, String legacyKey) {
        Optional<String> cached = runtimeConfigCache.get(canonicalKey);
        if (cached.isPresent()) {
            return cached;
        }
        Optional<String> configured = configValueProvider.findByKey(canonicalKey)
                .or(() -> runtimeConfigCache.get(legacyKey))
                .or(() -> configValueProvider.findByKey(legacyKey));
        configured.ifPresent(value -> runtimeConfigCache.put(canonicalKey, value));
        return configured;
    }

    /**
     * 检查同名活动文件并抛出冲突异常。
     *
     * <p>只检查活动节点：软删除节点与新节点可以并存（唯一索引仅约束 {@code is_deleted = false}），
     * 回收站里的同名项由恢复时的同名检查拦截，不再阻塞重新上传。</p>
     */
    private void checkActiveNameConflict(UUID ownerUserId, SpaceType spaceType, UUID parentId, String fileName) {
        fileNodeRepository.findActiveNameConflict(ownerUserId, spaceType, parentId, fileName)
                .ifPresent(node -> {
                    throw new BusinessException(
                            ErrorCode.CONFLICT,
                            "同级目录下已存在同名文件",
                            conflictDetails("existingFileId", node)
                    );
                });
    }

    private Map<String, Object> conflictDetails(String fileIdKey, FileNode node) {
        Map<String, Object> details = new LinkedHashMap<>();
        details.put(fileIdKey, node.getId().toString());
        details.put("fileName", node.getName());
        details.put("sizeBytes", node.getSizeBytes());
        if (node.getMimeType() != null && !node.getMimeType().isBlank()) {
            details.put("mimeType", node.getMimeType());
        }
        if (node.getDeletedAt() != null) {
            details.put("deletedAt", node.getDeletedAt().toString());
        }
        return Map.copyOf(details);
    }

    private String normalizeFileName(String rawName) {
        String name = rawName == null ? "" : rawName.trim();
        if (name.isEmpty()
                || ".".equals(name)
                || "..".equals(name)
                || name.contains("/")
                || name.contains("\\")
                || name.contains("\u0000")) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件名不合法");
        }
        return name;
    }

    private String normalizeMimeType(String rawMimeType, String fileName) {
        String mimeType = rawMimeType == null ? null : rawMimeType.trim();
        if (mimeType != null && !mimeType.isEmpty()
                && !"application/octet-stream".equals(mimeType)) {
            return mimeType;
        }
        // 前端未传或传了通用类型时，基于文件扩展名兜底
        return guessMimeTypeByFileName(fileName);
    }

    /**
     * 基于文件扩展名推断 MIME 类型，优先使用 Spring MediaTypeFactory。
     */
    static String guessMimeTypeByFileName(String fileName) {
        return MediaTypeFactory
                .getMediaType(fileName)
                .map(MimeType::toString)
                .orElse("application/octet-stream");
    }

    private String normalizeSha256(String rawSha256) {
        if (rawSha256 == null || rawSha256.isBlank()) {
            return null;
        }
        String sha256 = rawSha256.trim().toLowerCase(Locale.ROOT);
        if (!sha256.matches("[0-9a-f]{64}")) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "SHA-256 格式不合法");
        }
        return sha256;
    }

    private String normalizeETag(String rawETag) {
        String eTag = rawETag == null ? "" : rawETag.trim().replace("\"", "");
        if (eTag.isEmpty() || eTag.length() > 160) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "ETag 格式不合法");
        }
        return eTag;
    }

    private int resolvePartSizeBytes(long totalSizeBytes, Integer requestedPartSizeBytes) {
        if (requestedPartSizeBytes != null) {
            if (requestedPartSizeBytes < uploadLimits.getMinPartSizeBytes() || requestedPartSizeBytes > uploadLimits.getMaxPartSizeBytes()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "分片大小必须在 10MB 到 100MB 之间");
            }
            return requestedPartSizeBytes;
        }
        if (totalSizeBytes <= uploadLimits.getDefaultPartSizeBytes()) {
            return Math.toIntExact(totalSizeBytes);
        }
        // 动态分片：目标约 64 个分片，减少大文件的分片数量
        // 2GB 文件：32MB × 64 片（而非 10MB × 200 片）
        int partSizeBytes = Math.max(
                uploadLimits.getMinPartSizeBytes(),
                Math.toIntExact((totalSizeBytes + uploadLimits.getTargetParts() - 1) / uploadLimits.getTargetParts())
        );
        // 确保不超过 S3 的 1000 分片限制
        while (resolveTotalPartsValue(totalSizeBytes, partSizeBytes) > uploadLimits.getMaxTotalParts()
                && partSizeBytes < uploadLimits.getMaxPartSizeBytes()) {
            partSizeBytes = Math.min(partSizeBytes * 2, uploadLimits.getMaxPartSizeBytes());
        }
        return partSizeBytes;
    }

    private int resolveTotalParts(long totalSizeBytes, int partSizeBytes) {
        long totalParts = resolveTotalPartsValue(totalSizeBytes, partSizeBytes);
        if (totalParts > uploadLimits.getMaxTotalParts()) {
            throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "文件分片数量超过限制");
        }
        return Math.toIntExact(totalParts);
    }

    private long resolveTotalPartsValue(long totalSizeBytes, int partSizeBytes) {
        return (totalSizeBytes + partSizeBytes - 1) / partSizeBytes;
    }

    private List<FileUploadPart> buildParts(FileUploadSession session) {
        return IntStream.rangeClosed(1, session.getTotalParts())
                .mapToObj(partNumber -> {
                    FileUploadPart part = new FileUploadPart();
                    part.setUploadSessionId(session.getId());
                    part.setOwnerUserId(session.getOwnerUserId());
                    part.setPartNumber(partNumber);
                    part.setSizeBytes(resolvePartSize(session, partNumber));
                    part.setStatus(UploadStatus.PENDING.getValue());
                    return part;
                })
                .toList();
    }

    private void applyCompletedPartRequest(
            FileUploadSession session,
            List<CompleteFileUploadPartRequest> requestedParts
    ) {
        if (requestedParts == null || requestedParts.isEmpty()) {
            return;
        }
        Set<Integer> partNumbers = new HashSet<>();
        for (CompleteFileUploadPartRequest requestedPart : requestedParts) {
            if (requestedPart.partNumber() > session.getTotalParts()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "分片序号超出上传会话范围");
            }
            if (!partNumbers.add(requestedPart.partNumber())) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "分片序号重复");
            }
        }
        Map<Integer, FileUploadPart> partsByNumber = fileUploadPartRepository
                .findByUploadSessionIdOrderByPartNumber(session.getId())
                .stream()
                .collect(Collectors.toMap(FileUploadPart::getPartNumber, p -> p));
        List<FileUploadPart> toSave = new ArrayList<>();
        for (CompleteFileUploadPartRequest requestedPart : requestedParts) {
            FileUploadPart part = partsByNumber.get(requestedPart.partNumber());
            if (part == null) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传分片不存在");
            }
            part.setETag(normalizeETag(requestedPart.eTag()));
            part.setStatus(UploadStatus.COMPLETED.getValue());
            toSave.add(part);
        }
        fileUploadPartRepository.saveAll(toSave);
    }

    private void ensureAllPartsCompleted(FileUploadSession session, List<FileUploadPart> parts) {
        if (parts.size() != session.getTotalParts()) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传分片数量不完整");
        }
        boolean allCompleted = parts.stream().allMatch(this::isCompletedPart);
        if (!allCompleted) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "存在未完成的上传分片");
        }
    }

    private boolean isCompletedPart(FileUploadPart part) {
        return "COMPLETED".equals(part.getStatus()) && part.getETag() != null && !part.getETag().isBlank();
    }

    private List<ObjectStorageCompletedPart> toCompletedParts(List<FileUploadPart> parts) {
        return parts.stream()
                .sorted(Comparator.comparingInt(FileUploadPart::getPartNumber))
                .map(part -> new ObjectStorageCompletedPart(part.getPartNumber(), part.getETag()))
                .toList();
    }

    private long resolvePartSize(FileUploadSession session, int partNumber) {
        if (partNumber < session.getTotalParts()) {
            return session.getPartSizeBytes();
        }
        long uploadedBeforeLastPart = (long) session.getPartSizeBytes() * (session.getTotalParts() - 1);
        return session.getTotalSizeBytes() - uploadedBeforeLastPart;
    }

    /**
     * 创建安全入库记录并受理安全扫描任务，上传请求在此立即返回。
     * 文件节点由 Worker 在扫描通过后创建，期间会话保持 SCANNING。
     */
    private FileUploadCompleteResultDto dispatchSecurityScan(
            UUID ownerUserId,
            FileUploadSession session,
            UUID asVersionOfFileId
    ) {
        UUID ingressId = ingressLifecycleService.openWithinTransaction(new IngressCommand(
                ownerUserId,
                "UPLOAD",
                null,
                session.getId(),
                session.getTargetBucket(),
                session.getTargetObjectKey(),
                objectStorageBuckets.userFiles(),
                "users/" + ownerUserId + "/files/" + UUID.randomUUID() + "/" + session.getFileName(),
                session.getTargetParentId(),
                session.getFileName(),
                session.getTotalSizeBytes(),
                session.getMimeType()
        ));
        extendScanWindow(session);
        UUID scanTaskId = ingressScanTaskService.enqueueScanTask(
                ownerUserId, ingressId, asVersionOfFileId, session.getSha256());
        session.setIngressItemId(ingressId);
        session.setCompletionTaskId(scanTaskId);
        session.setUploadedParts(session.getTotalParts());
        session.setStatus(UploadStatus.SCANNING.getValue());
        fileUploadSessionRepository.save(session);
        return new FileUploadCompleteResultDto(
                session.getUploadId(),
                UploadStatus.SCANNING.getValue(),
                scanTaskId,
                null
        );
    }

    /**
     * 延长会话有效期与配额预留覆盖扫描与重试窗口，防止扫描期间被过期回收。
     */
    private void extendScanWindow(FileUploadSession session) {
        Instant extendedExpiresAt = Instant.now().plus(SCAN_WINDOW);
        session.setExpiresAt(extendedExpiresAt);
        if (session.getQuotaReservationId() != null) {
            storageQuotaService.extendReservation("UPLOAD", session.getId(), extendedExpiresAt);
        }
    }

    private FileUploadCompleteResultDto completedResult(FileUploadSession session) {
        return new FileUploadCompleteResultDto(
                session.getUploadId(),
                UploadStatus.COMPLETED.getValue(),
                session.getCompletionTaskId(),
                session.getResultFileNodeId()
        );
    }

    private FileUploadCompleteResultDto scanningResult(FileUploadSession session) {
        return new FileUploadCompleteResultDto(
                session.getUploadId(),
                UploadStatus.SCANNING.getValue(),
                session.getCompletionTaskId(),
                null
        );
    }

    private FileUploadSessionDto toSessionDto(FileUploadSession session, List<FileUploadPart> parts, boolean includeUrls) {
        List<FileUploadPartDto> partDtos = toPartDtos(
                session, parts, includeUrls, includeUrls ? INITIAL_PRESIGNED_PARTS : 0);
        String uploadUrl = null;
        Instant uploadUrlExpiresAt = null;
        if (includeUrls && isDirectUpload(session)) {
            uploadUrl = objectStorageClient.createUploadUrl(
                    new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey()),
                    uploadSettings.presignedUrlTtl()
            ).toString();
            uploadUrlExpiresAt = Instant.now().plus(uploadSettings.presignedUrlTtl());
        } else if (!partDtos.isEmpty()) {
            uploadUrl = partDtos.getFirst().uploadUrl();
            uploadUrlExpiresAt = partDtos.getFirst().uploadUrlExpiresAt();
        }
        return new FileUploadSessionDto(
                session.getId(),
                session.getTargetParentId(),
                session.getUploadId(),
                session.getFileName(),
                session.getTotalSizeBytes(),
                session.getPartSizeBytes(),
                session.getTotalParts(),
                session.getMimeType(),
                session.getStatus(),
                uploadUrl,
                uploadUrlExpiresAt,
                partDtos,
                session.getExpiresAt()
        );
    }

    private FileUploadPartsDto toPartsDto(FileUploadSession session, List<FileUploadPart> parts, boolean includeUrls) {
        List<FileUploadPartDto> partDtos = toPartDtos(session, parts, includeUrls, 0);
        List<Integer> completedPartNumbers = parts.stream()
                .filter(this::isCompletedPart)
                .map(FileUploadPart::getPartNumber)
                .sorted()
                .toList();
        return new FileUploadPartsDto(
                session.getId(),
                session.getUploadId(),
                session.getTotalParts(),
                completedPartNumbers,
                partDtos
        );
    }

    private boolean isDirectUpload(FileUploadSession session) {
        return session.getUploadId() != null && session.getUploadId().startsWith("DIRECT-");
    }

    private List<FileUploadPartDto> toPartDtos(
            FileUploadSession session, List<FileUploadPart> parts, boolean includeUrls, int presignLimit) {
        if (isDirectUpload(session)) {
            return List.of();
        }

        ObjectStorageKey key = new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey());
        Instant expiresAt = includeUrls ? Instant.now().plus(uploadSettings.presignedUrlTtl()) : null;
        return parts.stream()
                .sorted(Comparator.comparingInt(FileUploadPart::getPartNumber))
                .map(part -> {
                    boolean presign = includeUrls
                            && part.getPartNumber() <= presignLimit
                            && !isCompletedPart(part);
                    return new FileUploadPartDto(
                            part.getPartNumber(),
                            part.getSizeBytes(),
                            part.getStatus(),
                            part.getETag(),
                            presign
                                    ? objectStorageClient.createMultipartUploadPartUrl(
                                            key,
                                            session.getUploadId(),
                                            part.getPartNumber(),
                                            uploadSettings.presignedUrlTtl()
                                    ).toString()
                                    : null,
                            presign ? expiresAt : null
                    );
                })
                .toList();
    }

    private FileNodeDto toFileNodeDto(FileNode node, UUID mediaAutoImportTaskId) {
        return new FileNodeDto(
                node.getId(),
                node.getParentId(),
                node.getNodeType(),
                node.getName(),
                node.getNormalizedPath(),
                node.getMimeType(),
                node.getSizeBytes(),
                node.isShared(),
                node.getSharedAt(),
                node.getUpdatedAt(),
                node.getSpaceType() != null ? node.getSpaceType().getValue() : "PERSONAL",
                node.getUploadedBy(),
                null,
                null,
                mediaAutoImportTaskId,
                false
        );
    }
}
