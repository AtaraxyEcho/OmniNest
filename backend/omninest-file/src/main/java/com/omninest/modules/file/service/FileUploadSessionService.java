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
    private static final long DIRECT_UPLOAD_MAX_BYTES = 64L * 1024 * 1024;
    private static final int MAX_CONCURRENT_PARTS = 4;
    private static final int MIN_PART_SIZE_BYTES = 10 * 1024 * 1024;
    private static final int DEFAULT_PART_SIZE_BYTES = 10 * 1024 * 1024;
    private static final int MAX_PART_SIZE_BYTES = 100 * 1024 * 1024;
    private static final int MAX_TOTAL_PARTS = 1000;
    private static final int TARGET_PARTS = 64;
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
    private final FileIngressLifecycleService ingressLifecycleService;
    private final FileIngressScanTaskService ingressScanTaskService;
    private final ConfigValueProvider configValueProvider;
    private final RuntimeConfigCache runtimeConfigCache;
    private final FileContentChangePublisher fileContentChangePublisher;

    public FileUploadPolicyDto uploadPolicy() {
        return new FileUploadPolicyDto(
                DIRECT_UPLOAD_MAX_BYTES,
                DEFAULT_PART_SIZE_BYTES,
                MAX_PART_SIZE_BYTES,
                MAX_TOTAL_PARTS,
                MAX_CONCURRENT_PARTS,
                uploadSettings.presignedUrlTtl().getSeconds(),
                uploadSettings.maxPresignedPartsPerSecond(),
                bandwidthLimitEnabled()
        );
    }

    @Transactional(rollbackFor = Exception.class)
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

        String fileName = normalizeFileName(request.fileName());
        FileNode parent = resolveParent(ownerUserId, request.parentId());
        UUID asVersionOfFileId = request.asVersionOfFileId();
        if (asVersionOfFileId != null) {
            fileNodeRepository
                    .findByIdAndOwnerUserIdAndDeletedFalse(asVersionOfFileId, ownerUserId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "目标文件不存在"));
        } else {
            checkActiveNameConflict(ownerUserId, request.parentId(), fileName);
            checkSoftDeletedConflict(ownerUserId, request.parentId(), fileName);
        }

        String mimeType = normalizeMimeType(request.mimeType(), fileName);
        UUID sessionId = UUID.randomUUID();
        Instant expiresAt = Instant.now().plus(uploadSettings.sessionTtl());
        UUID quotaReservationId = spaceType == SpaceType.PERSONAL
                ? storageQuotaService.reserve(
                        ownerUserId,
                        "UPLOAD",
                        sessionId,
                        request.sizeBytes(),
                        expiresAt
                )
                : null;
        if (request.partSizeBytes() == null && request.sizeBytes() <= DIRECT_UPLOAD_MAX_BYTES) {
            return createDirectSession(
                    ownerUserId,
                    request,
                    parent,
                    fileName,
                    mimeType,
                    spaceType,
                    sessionId,
                    expiresAt,
                    quotaReservationId
            );
        }

        int partSizeBytes = resolvePartSizeBytes(request.sizeBytes(), request.partSizeBytes());
        int totalParts = resolveTotalParts(request.sizeBytes(), partSizeBytes);
        String bucket = objectStorageBuckets.quarantine();
        String objectKey = "uploads/" + ownerUserId + "/" + sessionId + "/" + fileName;
        ObjectStorageKey storageKey = new ObjectStorageKey(bucket, objectKey);
        String uploadId = objectStorageClient.initiateMultipartUpload(storageKey, mimeType);

        FileUploadSession session = new FileUploadSession();
        session.setId(sessionId);
        session.setOwnerUserId(ownerUserId);
        session.setTargetParentId(parent == null ? null : parent.getId());
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
        session.setSpaceType(spaceType);
        FileUploadSession saved = fileUploadSessionRepository.save(session);
        List<FileUploadPart> parts = fileUploadPartRepository.saveAll(buildParts(saved));
        return toSessionDto(saved, parts, true);
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

    @Transactional(rollbackFor = Exception.class)
    public FileUploadPartsDto completePart(
            UUID ownerUserId,
            String uploadId,
            int partNumber,
            CompleteFileUploadPartRequest request
    ) {
        FileUploadSession session = findCompletableSession(ownerUserId, uploadId);
        FileUploadPart part = fileUploadPartRepository.findByUploadSessionIdAndPartNumber(session.getId(), partNumber)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传分片不存在"));
        part.setETag(normalizeETag(request == null ? null : request.eTag()));
        part.setStatus(UploadStatus.COMPLETED.getValue());
        fileUploadPartRepository.save(part);

        List<FileUploadPart> parts = fileUploadPartRepository.findByUploadSessionIdOrderByPartNumber(session.getId());
        long completedParts = parts.stream().filter(this::isCompletedPart).count();
        session.setUploadedParts(Math.toIntExact(completedParts));
        if (!UploadStatus.COMPLETED.getValue().equals(session.getStatus())) {
            session.setStatus(UploadStatus.UPLOADING.getValue());
        }
        // 自动延期：当剩余时间不足 1 小时时自动延期
        Instant now = Instant.now();
        if (session.getExpiresAt().minus(Duration.ofHours(1)).isBefore(now)) {
            session.setExpiresAt(now.plus(uploadSettings.sessionTtl()));
        }
        fileUploadSessionRepository.save(session);
        return toPartsDto(session, parts, false);
    }

    @Transactional(rollbackFor = Exception.class)
    public FileUploadCompleteResultDto completeSession(UUID ownerUserId, String uploadId, CompleteFileUploadRequest request) {
        FileUploadSession session = findSessionForUpdate(ownerUserId, uploadId);
        if (UploadStatus.COMPLETED.getValue().equals(session.getStatus())) {
            return completedResult(session);
        }
        if (UploadStatus.SCANNING.getValue().equals(session.getStatus())) {
            return scanningResult(session);
        }
        ensureCompletable(session);
        if (isDirectUpload(session)) {
            return completeDirectSession(ownerUserId, session, request);
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

        resolveParent(ownerUserId, session.getTargetParentId());
        UUID asVersionOfFileIdForCheck = request == null ? null : request.asVersionOfFileId();
        if (asVersionOfFileIdForCheck == null
                && sameNameExists(ownerUserId, session.getTargetParentId(), session.getFileName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }

        ObjectStorageKey key = new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey());
        session.setStatus(UploadStatus.FINALIZING.getValue());
        fileUploadSessionRepository.save(session);
        objectStorageClient.completeMultipartUpload(key, session.getUploadId(), toCompletedParts(parts));

        return dispatchSecurityScan(ownerUserId, session, request == null ? null : request.asVersionOfFileId());
    }

    @Transactional(rollbackFor = Exception.class)
    public void cancelSession(UUID ownerUserId, String uploadId) {
        FileUploadSession session = findSessionForUpdate(ownerUserId, uploadId);
        if (UploadStatus.COMPLETED.getValue().equals(session.getStatus())) {
            return;
        }
        ObjectStorageKey key = new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey());
        if (isDirectUpload(session)) {
            if (objectStorageClient.objectExists(key)) {
                objectStorageClient.removeObject(key);
            }
        } else {
            objectStorageClient.abortMultipartUpload(key, session.getUploadId());
        }
        fileUploadPartRepository.deleteByUploadSessionId(session.getId());
        if (session.getQuotaReservationId() != null) {
            storageQuotaService.releaseReservation("UPLOAD", session.getId());
        }
        fileUploadSessionRepository.delete(session);
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

    @Transactional(readOnly = true)
    public FileUploadPartDto getPartUrl(UUID ownerUserId, String uploadId, int partNumber) {
        FileUploadSession session = findSession(ownerUserId, uploadId);
        if (isDirectUpload(session)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "直传模式不支持分片 URL 查询");
        }
        ensureCompletable(session);

        // 带宽限速：控制 presigned URL 签发频率
        checkBandwidthLimit(ownerUserId);

        FileUploadPart part = fileUploadPartRepository
                .findByUploadSessionIdAndPartNumber(session.getId(), partNumber)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传分片不存在"));
        if (isCompletedPart(part)) {
            return new FileUploadPartDto(part.getPartNumber(), part.getSizeBytes(),
                    part.getStatus(), part.getETag(), null);
        }
        ObjectStorageKey key = new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey());
        String url = objectStorageClient.createMultipartUploadPartUrl(
                key, session.getUploadId(), partNumber, uploadSettings.presignedUrlTtl()
        ).toString();
        return new FileUploadPartDto(part.getPartNumber(), part.getSizeBytes(),
                part.getStatus(), part.getETag(), url);
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
        return toSessionDto(saved, List.of(), false);
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

    private FileUploadSession findCompletableSession(UUID ownerUserId, String uploadId) {
        FileUploadSession session = findSessionForUpdate(ownerUserId, uploadId);
        ensureCompletable(session);
        return session;
    }

    private FileUploadCompleteResultDto completeDirectSession(
            UUID ownerUserId,
            FileUploadSession session,
            CompleteFileUploadRequest request
    ) {
        String sha256 = normalizeSha256(request == null ? null : request.sha256());
        if (sha256 != null && session.getSha256() != null && !session.getSha256().equalsIgnoreCase(sha256)) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "文件摘要不一致");
        }
        if (sha256 != null) {
            session.setSha256(sha256);
        }

        resolveParent(ownerUserId, session.getTargetParentId());
        UUID asVersionOfFileId = request == null ? null : request.asVersionOfFileId();
        if (asVersionOfFileId == null
                && sameNameExists(ownerUserId, session.getTargetParentId(), session.getFileName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }

        ObjectStorageKey key = new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey());
        if (!objectStorageClient.objectExists(key)) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "文件内容尚未上传完成");
        }

        return dispatchSecurityScan(ownerUserId, session, asVersionOfFileId);
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
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传会话已过期");
        }
        if (!UploadStatus.CREATED.getValue().equals(session.getStatus()) && !UploadStatus.UPLOADING.getValue().equals(session.getStatus())) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传会话状态不允许完成");
        }
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

    private void checkActiveNameConflict(UUID ownerUserId, UUID parentId, String fileName) {
        fileNodeRepository.findActiveNameConflict(ownerUserId, parentId, fileName)
                .ifPresent(node -> {
                    throw new BusinessException(
                            ErrorCode.CONFLICT,
                            "同级目录下已存在同名文件",
                            conflictDetails("existingFileId", node)
                    );
                });
    }

    /**
     * 检查回收站是否存在同名文件，如果存在则抛出冲突异常。
     * 前端收到 409 + details 后弹窗提示用户确认清理。
     */
    private void checkSoftDeletedConflict(UUID ownerUserId, UUID parentId, String fileName) {
        Optional<FileNode> conflict;
        if (parentId == null) {
            conflict = fileNodeRepository.findByOwnerUserIdAndParentIdIsNullAndNameAndDeletedTrue(ownerUserId, fileName);
        } else {
            conflict = fileNodeRepository.findByOwnerUserIdAndParentIdAndNameAndDeletedTrue(ownerUserId, parentId, fileName);
        }
        conflict.ifPresent(node -> {
            throw new BusinessException(ErrorCode.CONFLICT, "回收站存在同名文件，请先清理后再上传",
                    conflictDetails("softDeletedFileId", node));
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
            if (requestedPartSizeBytes < MIN_PART_SIZE_BYTES || requestedPartSizeBytes > MAX_PART_SIZE_BYTES) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "分片大小必须在 10MB 到 100MB 之间");
            }
            return requestedPartSizeBytes;
        }
        if (totalSizeBytes <= DEFAULT_PART_SIZE_BYTES) {
            return Math.toIntExact(totalSizeBytes);
        }
        // 动态分片：目标约 64 个分片，减少大文件的分片数量
        // 2GB 文件：32MB × 64 片（而非 10MB × 200 片）
        int partSizeBytes = Math.max(
                MIN_PART_SIZE_BYTES,
                Math.toIntExact((totalSizeBytes + TARGET_PARTS - 1) / TARGET_PARTS)
        );
        // 确保不超过 S3 的 1000 分片限制
        while (resolveTotalPartsValue(totalSizeBytes, partSizeBytes) > MAX_TOTAL_PARTS
                && partSizeBytes < MAX_PART_SIZE_BYTES) {
            partSizeBytes = Math.min(partSizeBytes * 2, MAX_PART_SIZE_BYTES);
        }
        return partSizeBytes;
    }

    private int resolveTotalParts(long totalSizeBytes, int partSizeBytes) {
        long totalParts = resolveTotalPartsValue(totalSizeBytes, partSizeBytes);
        if (totalParts > MAX_TOTAL_PARTS) {
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
        UUID ingressId = ingressLifecycleService.open(new IngressCommand(
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
        List<FileUploadPartDto> partDtos = toPartDtos(session, parts, includeUrls);
        String uploadUrl = null;
        if (includeUrls && isDirectUpload(session)) {
            uploadUrl = objectStorageClient.createUploadUrl(
                    new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey()),
                    uploadSettings.presignedUrlTtl()
            ).toString();
        } else if (!partDtos.isEmpty()) {
            uploadUrl = partDtos.getFirst().uploadUrl();
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
                session.getTargetBucket(),
                session.getTargetObjectKey(),
                uploadUrl,
                partDtos,
                session.getExpiresAt()
        );
    }

    private FileUploadPartsDto toPartsDto(FileUploadSession session, List<FileUploadPart> parts, boolean includeUrls) {
        List<FileUploadPartDto> partDtos = toPartDtos(session, parts, includeUrls);
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

    private List<FileUploadPartDto> toPartDtos(FileUploadSession session, List<FileUploadPart> parts, boolean includeUrls) {
        if (isDirectUpload(session)) {
            return List.of();
        }

        ObjectStorageKey key = new ObjectStorageKey(session.getTargetBucket(), session.getTargetObjectKey());
        return parts.stream()
                .sorted(Comparator.comparingInt(FileUploadPart::getPartNumber))
                .map(part -> new FileUploadPartDto(
                        part.getPartNumber(),
                        part.getSizeBytes(),
                        part.getStatus(),
                        part.getETag(),
                        includeUrls && !isCompletedPart(part)
                                ? objectStorageClient.createMultipartUploadPartUrl(
                                        key,
                                        session.getUploadId(),
                                        part.getPartNumber(),
                                        uploadSettings.presignedUrlTtl()
                                ).toString()
                                : null
                ))
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
                mediaAutoImportTaskId
        );
    }
}
