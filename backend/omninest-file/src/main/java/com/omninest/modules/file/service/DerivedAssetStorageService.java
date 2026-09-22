package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.config.FileTransferLimitsProperties;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.Collection;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 派生资源对象与文件节点的存储服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class DerivedAssetStorageService {
    private static final Duration DOWNLOAD_TIMEOUT = Duration.ofSeconds(30);
    private static final int MAX_REDIRECTS = 5;
    /** 远程抓取和流式复制派生字节的字节上限；本地落库上限由部署配置决定。 */
    private static final long MAX_FETCHED_DERIVED_ASSET_BYTES = 128L * 1024 * 1024;
    /** 转码产物、批量打包等完整内容产物的兜底上限，仅用于拦截异常产物写满磁盘。 */
    private static final long MAX_MEDIA_DERIVED_ASSET_BYTES = 64L * 1024 * 1024 * 1024;
    /**
     * 允许按完整内容产物上限存储的资产类型。文件模块不感知业务枚举，此处按字符串契约匹配；
     * 新增资产类型默认沿用小资产上限，确属完整内容产物时在此显式加入。
     */
    private static final Set<String> LARGE_ASSET_TYPES = Set.of("TRANSCODE", "DOWNLOAD");
    private static final Path PROCESSING_ROOT = Path.of(
            System.getProperty("java.io.tmpdir"), "omninest-derived");
    private static final String SOURCE_TYPE_DERIVED = "DERIVED";

    /** 复用 HttpClient 实例，避免每次请求创建新连接池 */
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(DOWNLOAD_TIMEOUT)
            .build();

    private final ObjectStorageBuckets objectStorageBuckets;
    private final ObjectStorageClient objectStorageClient;
    private final FileObjectRepository fileObjectRepository;
    private final FileNodeRepository fileNodeRepository;
    private final SafeUrlValidator safeUrlValidator;
    private final TransactionTemplate transactionTemplate;
    private final FileTransferLimitsProperties transferLimits;

    /** 在独立新事务中执行存储动作；并发流水线写入同一对象键时重试一次。 */
    private UUID storeInNewTransactionWithRetry(StoreAction action) {
        TransactionTemplate template = new TransactionTemplate(
                transactionTemplate.getTransactionManager());
        template.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        return executeWithConflictRetry(template, action);
    }

    /** 执行存储动作，命中对象键唯一键冲突时以新事务重试一次，复用先到者写入的元数据。 */
    private UUID executeWithConflictRetry(TransactionTemplate template, StoreAction action) {
        DataIntegrityViolationException lastFailure = null;
        for (int attempt = 1; attempt <= 2; attempt++) {
            try {
                return template.execute(status -> action.run());
            } catch (DataIntegrityViolationException ex) {
                if (attempt == 2) {
                    throw ex;
                }
                lastFailure = ex;
                log.warn("派生资源元数据并发写入冲突，重试: attempt={}", attempt);
            }
        }
        throw lastFailure;
    }

    /** 存储动作。 */
    @FunctionalInterface
    private interface StoreAction {
        UUID run();
    }

    /**
     * 删除当前用户拥有的派生资源及其对象元数据。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 找到并删除派生资源时返回 true
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    /**
     * 查询已存在的派生资产文件节点 ID。
     *
     * <p>与 {@link #isAvailable} 使用同一可用性判定（路径存在、来源为派生、
     * 对象仍在对象存储中），供调用方在不重新生成资产的情况下回填引用。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param resourceType 资源类型
     * @param resourceId 资源 ID
     * @param assetType 资产类型
     * @param fileName 资产文件名
     * @return 派生资产 FileNode ID；不可用或不存在时返回空
     */
    public Optional<UUID> findStoredFileNodeId(
            UUID ownerUserId,
            String resourceType,
            UUID resourceId,
            String assetType,
            String fileName
    ) {
        String path = normalizedPath(resourceType, resourceId, assetType, fileName);
        return fileNodeRepository.findActivePath(ownerUserId, path)
                .filter(node -> SOURCE_TYPE_DERIVED.equals(node.getSourceType())
                        && node.getCurrentObjectId() != null)
                .filter(node -> fileObjectRepository.findById(node.getCurrentObjectId())
                        .map(object -> objectStorageClient.objectExists(new ObjectStorageKey(
                                object.getBucketName(),
                                object.getObjectKey()
                        )))
                        .orElse(false))
                .map(FileNode::getId);
    }

    public boolean deleteOwned(UUID ownerUserId, UUID fileNodeId) {
        return deleteOwnedInCurrentTransaction(ownerUserId, fileNodeId);
    }

    /**
     * 删除派生资源引用的物理对象。
     *
     * <p>调用方必须在删除自身元数据前调用此方法。对象存储异常会直接抛出，
     * 由上层事务决定是否回滚，不能在元数据已经删除后再静默记录失败。</p>
     *
     * @param reference 物理对象引用
     */
    public void deleteObject(LegacyObjectReference reference) {
        validateLegacyReference(reference);
        objectStorageClient.removeObject(new ObjectStorageKey(
                reference.bucketName(),
                reference.objectKey()
        ));
    }

    /**
     * 打开迁移前遗留派生对象的只读流。
     *
     * <p>该入口仅用于尚未迁移为 FileNode 的派生资产。调用方拥有关闭返回流的责任，
     * 业务模块不得直接依赖对象存储客户端。</p>
     *
     * @param reference 遗留对象引用
     * @return 对象内容流
     */
    public InputStream openLegacyObject(LegacyObjectReference reference) {
        validateLegacyReference(reference);
        return objectStorageClient.getObject(new ObjectStorageKey(
                reference.bucketName(),
                reference.objectKey()
        ));
    }

    /**
     * 批量删除当前用户拥有的派生资源及其对象元数据。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileNodeIds 文件节点 ID 集合
     * @return 成功匹配并删除的派生资源数量
     */
    @Transactional(rollbackFor = Exception.class)
    public int deleteOwnedBatch(UUID ownerUserId, Collection<UUID> fileNodeIds) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return 0;
        }
        int deletedCount = 0;
        for (UUID fileNodeId : fileNodeIds) {
            if (fileNodeId != null && deleteOwnedInCurrentTransaction(ownerUserId, fileNodeId)) {
                deletedCount++;
            }
        }
        return deletedCount;
    }

    /**
     * 检查派生资源元数据和对象存储内容是否均可用。
     *
     * @param ownerUserId 所有者用户 ID
     * @param resourceType 业务资源类型
     * @param resourceId 业务资源 ID
     * @param assetType 派生资源类型
     * @param fileName 派生资源文件名
     * @return 元数据和物理对象均存在时返回 true
     */
    @Transactional(readOnly = true)
    public boolean isAvailable(
            UUID ownerUserId,
            String resourceType,
            UUID resourceId,
            String assetType,
            String fileName
    ) {
        String path = normalizedPath(resourceType, resourceId, assetType, fileName);
        return fileNodeRepository.findActivePath(ownerUserId, path)
                .filter(node -> SOURCE_TYPE_DERIVED.equals(node.getSourceType()))
                .map(FileNode::getCurrentObjectId)
                .flatMap(fileObjectRepository::findById)
                .map(object -> objectStorageClient.objectExists(new ObjectStorageKey(
                        object.getBucketName(),
                        object.getObjectKey()
                )))
                .orElse(false);
    }

    private boolean deleteOwnedInCurrentTransaction(UUID ownerUserId, UUID fileNodeId) {
        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileNodeId, ownerUserId)
                .filter(candidate -> SOURCE_TYPE_DERIVED.equals(candidate.getSourceType()))
                .orElse(null);
        if (node == null) {
            return false;
        }
        if (node.getCurrentObjectId() != null) {
            fileObjectRepository.findById(node.getCurrentObjectId()).ifPresent(object -> {
                deleteObject(new LegacyObjectReference(object.getBucketName(), object.getObjectKey()));
                fileObjectRepository.delete(object);
            });
        }
        fileNodeRepository.delete(node);
        return true;
    }

    private void validateLegacyReference(LegacyObjectReference reference) {
        if (reference == null
                || reference.bucketName() == null
                || reference.bucketName().isBlank()
                || reference.objectKey() == null
                || reference.objectKey().isBlank()) {
            throw new IllegalArgumentException("派生资源对象引用不能为空");
        }
    }

    /**
     * 将输入流保存为衍生资产文件（默认存入个人空间）。
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public UUID store(UUID ownerUserId, String resourceType, UUID resourceId,
                     String assetType, String fileName, String mimeType, InputStream data) {
        return store(ownerUserId, resourceType, resourceId, assetType, fileName, mimeType, data, SpaceType.PERSONAL);
    }

    /**
     * 将本地文件保存为派生资产文件（默认存入个人空间）。
     *
     * @param ownerUserId 所有者用户 ID
     * @param resourceType 资源类型
     * @param resourceId 资源 ID
     * @param assetType 资产类型
     * @param fileName 文件名
     * @param mimeType MIME 类型
     * @param sourceFile 本地源文件
     * @return FileNode ID
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public UUID store(UUID ownerUserId, String resourceType, UUID resourceId,
                      String assetType, String fileName, String mimeType, Path sourceFile) {
        return store(
                ownerUserId,
                resourceType,
                resourceId,
                assetType,
                fileName,
                mimeType,
                sourceFile,
                SpaceType.PERSONAL
        );
    }

    /**
     * 将输入流保存为衍生资产文件。
     *
     * @param ownerUserId 所有者用户 ID
     * @param resourceType 资源类型（如 READER_ITEM）
     * @param resourceId 资源 ID
     * @param assetType 资产类型（如 POSTER）
     * @param fileName 文件名
     * @param mimeType MIME 类型
     * @param data 输入流
     * @param spaceType 空间类型（PERSONAL / SHARED）
     * @return FileNode ID
     */
    public UUID store(UUID ownerUserId, String resourceType, UUID resourceId,
                     String assetType, String fileName, String mimeType, InputStream data, SpaceType spaceType) {
        Path tempFile = null;
        try {
            Files.createDirectories(PROCESSING_ROOT);
            tempFile = Files.createTempFile(PROCESSING_ROOT, "reader-cover-", ".img");
            try (OutputStream out = Files.newOutputStream(tempFile)) {
                copyBounded(data, out, MAX_FETCHED_DERIVED_ASSET_BYTES);
            }
            Path stagedFile = tempFile;
            return storeInNewTransactionWithRetry(() -> {
                try {
                    return storeFile(
                            ownerUserId,
                            resourceType,
                            resourceId,
                            assetType,
                            fileName,
                            fileName,
                            mimeType,
                            stagedFile,
                            spaceType
                    );
                } catch (IOException ex) {
                    throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "派生资源保存失败");
                }
            });
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "派生资源保存失败");
        } finally {
            if (tempFile != null) {
                try {
                    Files.deleteIfExists(tempFile);
                } catch (IOException ignored) {
                    log.debug("忽略: {}", ignored.getMessage());
                }
            }
        }
    }

    /**
     * 将本地文件保存为派生资产文件。
     *
     * @param ownerUserId 所有者用户 ID
     * @param resourceType 资源类型
     * @param resourceId 资源 ID
     * @param assetType 资产类型
     * @param fileName 文件名
     * @param mimeType MIME 类型
     * @param sourceFile 本地源文件
     * @param spaceType 空间类型
     * @return FileNode ID
     */
    public UUID store(UUID ownerUserId, String resourceType, UUID resourceId,
                      String assetType, String fileName, String mimeType,
                      Path sourceFile, SpaceType spaceType) {
        return storeInNewTransactionWithRetry(() -> {
            try {
                return storeFile(
                        ownerUserId,
                        resourceType,
                        resourceId,
                        assetType,
                        fileName,
                        fileName,
                        mimeType,
                        sourceFile,
                        spaceType
                );
            } catch (IOException ex) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "派生资源保存失败");
            }
        });
    }

    /**
     * 使用独立的逻辑文件名和对象存储文件名保存本地派生资产。
     *
     * @param ownerUserId 所有者用户 ID
     * @param resourceType 资源类型
     * @param resourceId 资源 ID
     * @param assetType 资产类型
     * @param fileName 文件节点使用的逻辑文件名
     * @param storageFileName 对象键使用的存储文件名
     * @param mimeType MIME 类型
     * @param sourceFile 本地源文件
     * @return FileNode ID
     */
    public UUID store(UUID ownerUserId, String resourceType, UUID resourceId,
                      String assetType, String fileName, String storageFileName,
                      String mimeType, Path sourceFile) {
        return storeInNewTransactionWithRetry(() -> {
            try {
                return storeFile(
                        ownerUserId,
                        resourceType,
                        resourceId,
                        assetType,
                        fileName,
                        storageFileName,
                        mimeType,
                        sourceFile,
                        SpaceType.PERSONAL
                );
            } catch (IOException ex) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "派生资源保存失败");
            }
        });
    }

    private UUID storeFile(
            UUID ownerUserId,
            String resourceType,
            UUID resourceId,
            String assetType,
            String fileName,
            String storageFileName,
            String mimeType,
            Path sourceFile,
            SpaceType spaceType
    ) throws IOException {
        Path normalizedSource = sourceFile.toAbsolutePath().normalize();
        if (!Files.isRegularFile(normalizedSource)) {
            throw new IOException("派生资源源文件不存在");
        }
        long sizeBytes = Files.size(normalizedSource);
        long maxBytes = assetType != null && LARGE_ASSET_TYPES.contains(assetType)
                ? MAX_MEDIA_DERIVED_ASSET_BYTES
                : transferLimits.getMaxDerivedAssetBytes();
        if (sizeBytes <= 0 || sizeBytes > maxBytes) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "派生资源大小超出限制");
        }
        String objectKey = "derived/"
                + ownerUserId + "/"
                + segment(resourceType) + "/"
                + resourceId + "/"
                + segment(assetType) + "/"
                + safeFileName(storageFileName);
        String bucketName = objectStorageBuckets.derivedAssets();
        ObjectStorageKey finalKey = new ObjectStorageKey(bucketName, objectKey);
        ObjectStorageKey stagingKey = new ObjectStorageKey(
                bucketName,
                "derived-staging/" + ownerUserId + "/" + UUID.randomUUID() + "/" + safeFileName(storageFileName)
        );
        String normalizedPath = normalizedPath(resourceType, resourceId, assetType, fileName);
        requireTargetWritable(ownerUserId, normalizedPath);
        try {
            objectStorageClient.putObject(stagingKey, normalizedSource, mimeType);
            requireTargetWritable(ownerUserId, normalizedPath);
            objectStorageClient.copyObject(stagingKey, finalKey);
        } finally {
            removeStagingObject(stagingKey);
        }

        FileObject object = fileObjectRepository
                .findByBucketNameAndObjectKey(bucketName, objectKey)
                .orElseGet(FileObject::new);
        object.setBucketName(bucketName);
        object.setObjectKey(objectKey);
        object.setMimeType(mimeType);
        object.setSizeBytes(sizeBytes);
        object.setSha256(sha256(normalizedSource));
        FileObject savedObject = fileObjectRepository.save(object);

        FileNode node = fileNodeRepository
                .findActivePath(ownerUserId, normalizedPath)
                .orElseGet(FileNode::new);
        node.setOwnerUserId(ownerUserId);
        node.setParentId(null);
        node.setNodeType("FILE");
        node.setName(safeFileName(fileName));
        node.setNormalizedPath(normalizedPath);
        node.setMimeType(mimeType);
        node.setSizeBytes(sizeBytes);
        node.setCurrentObjectId(savedObject.getId());
        node.setSourceType(SOURCE_TYPE_DERIVED);
        node.setDeleted(false);
        node.setSpaceType(spaceType);
        return fileNodeRepository.save(node).getId();
    }

    private void requireTargetWritable(UUID ownerUserId, String normalizedPath) {
        fileNodeRepository.findActivePath(ownerUserId, normalizedPath).ifPresent(node -> {
            if (node.getPurgeState() != null && node.getPurgeState() != FilePurgeState.NONE) {
                throw new BusinessException(ErrorCode.FILE_LIFECYCLE_CONFLICT, "派生资源正在永久删除");
            }
        });
    }

    private void removeStagingObject(ObjectStorageKey stagingKey) {
        try {
            objectStorageClient.removeObject(stagingKey);
        } catch (RuntimeException exception) {
            log.warn("派生资源暂存对象清理失败: errorType={}",
                    exception.getClass().getSimpleName(), exception);
        }
    }

    public UUID storeRemote(DerivedAssetRequest request) {
        validate(request);
        Path tempFile = null;
        try {
            DownloadedAsset downloaded = download(request.sourceUrl());
            tempFile = downloaded.path();
            String mimeType = firstNonBlank(downloaded.mimeType(), request.mimeType(), "application/octet-stream");
            Path downloadedFile = tempFile;
            return executeWithConflictRetry(transactionTemplate, () -> {
                try {
                    return storeFile(
                            request.ownerUserId(),
                            request.resourceType(),
                            request.resourceId(),
                            request.assetType(),
                            request.fileName(),
                            request.fileName(),
                            mimeType,
                            downloadedFile,
                            request.spaceType() != null ? request.spaceType() : SpaceType.PERSONAL
                    );
                } catch (IOException exception) {
                    throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "资源文件保存失败");
                }
            });
        } finally {
            if (tempFile != null) {
                try {
                    Files.deleteIfExists(tempFile);
                } catch (IOException ignored) {
                    log.debug("忽略: {}", ignored.getMessage());
                }
            }
        }
    }

    private DownloadedAsset download(String sourceUrl) {
        try {
            URI currentUri = URI.create(sourceUrl);
            for (int redirectCount = 0; redirectCount <= MAX_REDIRECTS; redirectCount++) {
                safeUrlValidator.requireSafeHttpUrl(currentUri.toString());
                HttpRequest request = HttpRequest.newBuilder(currentUri)
                        .timeout(DOWNLOAD_TIMEOUT)
                        .header("Accept", "image/avif,image/webp,image/*,*/*;q=0.8")
                        .GET()
                        .build();
                HttpResponse<InputStream> response = httpClient
                        .send(request, HttpResponse.BodyHandlers.ofInputStream());
                if (isRedirect(response.statusCode())) {
                    try (InputStream ignored = response.body()) {
                        String location = response.headers().firstValue("Location")
                                .orElseThrow(() -> new BusinessException(
                                        ErrorCode.FILE_UPLOAD_FAILED,
                                        "资源重定向地址缺失"
                                ));
                        currentUri = currentUri.resolve(location);
                    }
                    continue;
                }
                if (response.statusCode() < 200 || response.statusCode() >= 300) {
                    try (InputStream ignored = response.body()) {
                        throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "资源文件下载失败");
                    }
                }
                return persistResponse(response);
            }
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "资源重定向次数过多");
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "资源文件下载被中断");
        } catch (IllegalArgumentException | IOException ex) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "资源文件下载失败");
        }
    }

    private DownloadedAsset persistResponse(HttpResponse<InputStream> response) throws IOException {
        Files.createDirectories(PROCESSING_ROOT);
        long contentLength = response.headers().firstValueAsLong("Content-Length").orElse(-1L);
        if (contentLength > MAX_FETCHED_DERIVED_ASSET_BYTES) {
            throw new IOException("派生资源响应大小超出限制");
        }
        Path tempFile = Files.createTempFile(PROCESSING_ROOT, "remote-", ".asset");
        try {
            try (InputStream body = response.body()) {
                try (OutputStream output = Files.newOutputStream(tempFile)) {
                    copyBounded(body, output, MAX_FETCHED_DERIVED_ASSET_BYTES);
                }
            }
            String mimeType = response.headers().firstValue("Content-Type")
                    .map(value -> value.split(";")[0].trim())
                    .orElse(null);
            return new DownloadedAsset(tempFile, mimeType);
        } catch (IOException ex) {
            Files.deleteIfExists(tempFile);
            throw ex;
        }
    }

    private void copyBounded(InputStream input, OutputStream output, long maxBytes) throws IOException {
        byte[] buffer = new byte[8192];
        long copied = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            copied += read;
            if (copied > maxBytes) {
                throw new IOException("派生资源大小超出限制");
            }
            output.write(buffer, 0, read);
        }
        if (copied == 0) {
            throw new IOException("派生资源为空");
        }
    }

    private boolean isRedirect(int statusCode) {
        return statusCode == 301
                || statusCode == 302
                || statusCode == 303
                || statusCode == 307
                || statusCode == 308;
    }

    private void validate(DerivedAssetRequest request) {
        if (request == null
                || request.ownerUserId() == null
                || request.resourceId() == null
                || isBlank(request.sourceUrl())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "资源文件参数不完整");
        }
    }

    private String normalizedPath(String resourceType, UUID resourceId, String assetType, String fileName) {
        return "/.metadata/"
                + segment(resourceType)
                + "/"
                + resourceId
                + "/"
                + segment(assetType)
                + "/"
                + safeFileName(fileName);
    }

    private String safeFileName(String fileName) {
        String value = firstNonBlank(fileName, "asset.bin");
        return value.replaceAll("[\\\\/\\u0000]", "_").trim();
    }

    private String segment(String value) {
        String text = firstNonBlank(value, "UNKNOWN");
        return text.trim().toUpperCase(Locale.ROOT).replaceAll("[^A-Z0-9_-]", "_");
    }

    private String sha256(Path file) throws IOException {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream input = Files.newInputStream(file);
                 DigestInputStream digestInput = new DigestInputStream(input, digest)) {
                digestInput.transferTo(OutputStream.nullOutputStream());
            }
            return HexFormat.of().formatHex(digest.digest());
        } catch (NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 algorithm is unavailable", ex);
        }
    }

    private String firstNonBlank(String... values) {
        for (String value : values) {
            if (!isBlank(value)) {
                return value.trim();
            }
        }
        return "";
    }

    private boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    /**
     * 列出用户在指定资源类型下仍存活的派生节点引用。
     *
     * @param ownerUserId 所有者用户 ID
     * @param resourceType 资源类型
     * @return 节点引用列表
     */
    @Transactional(readOnly = true)
    public List<DerivedNodeRef> listDerivedNodeRefs(UUID ownerUserId, String resourceType) {
        String prefix = "/.metadata/" + segment(resourceType) + "/";
        return fileNodeRepository
                .findByOwnerUserIdAndSourceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        ownerUserId, SOURCE_TYPE_DERIVED, prefix)
                .stream()
                .map(node -> new DerivedNodeRef(node.getId(), node.getNormalizedPath()))
                .toList();
    }

    /**
     * 列出在指定资源类型下持有存活派生节点的用户。
     *
     * @param resourceType 资源类型
     * @return 用户 ID 列表
     */
    @Transactional(readOnly = true)
    public List<UUID> listOwnerIdsByDerivedPathPrefix(String resourceType) {
        String prefix = "/.metadata/" + segment(resourceType) + "/";
        return fileNodeRepository.findOwnerIdsBySourceTypeAndNormalizedPathPrefix(
                SOURCE_TYPE_DERIVED, prefix);
    }

    /**
     * 派生节点引用。
     *
     * @param fileNodeId 文件节点 ID
     * @param normalizedPath 节点完整逻辑路径
     */
    public record DerivedNodeRef(UUID fileNodeId, String normalizedPath) {
    }

    private record DownloadedAsset(Path path, String mimeType) {
    }
}
