package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.dto.FileContentResource;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileProcessInput;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * MinIO 文件内容提供者。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MinioFileContentProvider implements FileContentProvider {
    /**
     * 封面/缩略类派生资产的预签名有效期。取 2 小时以覆盖长会话场景；
     * 前端另有失败重签闭环兜底，不依赖无限延长。
     */
    private static final Duration DOWNLOAD_URL_TTL = Duration.ofHours(2);
    private static final String PROVIDER_TYPE = "MINIO";

    /**
     * 浏览器会直接执行的类型：经预签名 URL 内联返回即构成存储型 XSS 面，
     * 下载地址必须强制为附件且覆盖为不可执行类型。
     */
    private static final Set<String> INLINE_EXECUTABLE_TYPES = Set.of(
            "text/html",
            "application/xhtml+xml",
            "image/svg+xml",
            "application/xml",
            "text/xml",
            "application/javascript",
            "text/javascript"
    );

    private final FileObjectRepository fileObjectRepository;
    private final ObjectStorageClient objectStorageClient;

    @Override
    public String providerType() {
        return PROVIDER_TYPE;
    }

    @Override
    public boolean supports(FileNode node) {
        return node.getCurrentObjectId() != null;
    }

    @Override
    public FileContentStream open(FileNode node) {
        FileObject object = requireObject(node);
        return new FileContentStream(
                objectStorageClient.getObject(new ObjectStorageKey(object.getBucketName(), object.getObjectKey())),
                node.getName(),
                object.getSizeBytes(),
                object.getMimeType()
        );
    }

    @Override
    public FileDownloadUrlDto createDownloadUrl(FileNode node) {
        FileObject object = requireObject(node);
        String url = createSafeDownloadUrl(node.getName(), object).toString();
        return new FileDownloadUrlDto(node.getId(), node.getName(), url, Instant.now().plus(DOWNLOAD_URL_TTL));
    }

    @Override
    public FileDownloadUrlDto createDownloadUrl(FileNode node, FileObject object) {
        String url = createSafeDownloadUrl(node.getName(), object).toString();
        return new FileDownloadUrlDto(node.getId(), node.getName(), url, Instant.now().plus(DOWNLOAD_URL_TTL));
    }

    /**
     * 危险类型强制附件下载；普通类型维持内联语义以保留在线预览能力。
     */
    private URI createSafeDownloadUrl(String fileName, FileObject object) {
        ObjectStorageKey key = new ObjectStorageKey(object.getBucketName(), object.getObjectKey());
        String mimeType = object.getMimeType() == null ? "" : object.getMimeType().toLowerCase(Locale.ROOT);
        if (!INLINE_EXECUTABLE_TYPES.contains(mimeType)) {
            return objectStorageClient.createDownloadUrl(key, DOWNLOAD_URL_TTL);
        }
        String encodedName = URLEncoder.encode(fileName, StandardCharsets.UTF_8).replace("+", "%20");
        return objectStorageClient.createDownloadUrl(
                key,
                DOWNLOAD_URL_TTL,
                "application/octet-stream",
                "attachment; filename*=UTF-8''" + encodedName
        );
    }

    @Override
    public FileProcessInput createProcessInput(FileNode node) {
        return new FileProcessInput(node.getId(), PROVIDER_TYPE, createDownloadUrl(node).downloadUrl());
    }

    @Override
    public FileProcessInput createContainerProcessInput(FileNode node) {
        FileObject object = requireObject(node);
        URI url = objectStorageClient.createContainerDownloadUrl(
                new ObjectStorageKey(object.getBucketName(), object.getObjectKey()),
                DOWNLOAD_URL_TTL
        );
        return new FileProcessInput(node.getId(), PROVIDER_TYPE, url.toString());
    }

    @Override
    public Optional<FileContentResource> findRangeResource(FileNode node) {
        return Optional.empty();
    }

    private FileObject requireObject(FileNode node) {
        if (node.getCurrentObjectId() == null) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件对象不存在");
        }
        return fileObjectRepository.findById(node.getCurrentObjectId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件对象不存在"));
    }
}
