package com.omninest.common.storage;

import java.io.InputStream;
import java.net.URI;
import java.net.URL;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.AbortMultipartUploadRequest;
import software.amazon.awssdk.services.s3.model.CompletedMultipartUpload;
import software.amazon.awssdk.services.s3.model.CompletedPart;
import software.amazon.awssdk.services.s3.model.CompleteMultipartUploadRequest;
import software.amazon.awssdk.services.s3.model.CopyObjectRequest;
import software.amazon.awssdk.services.s3.model.CreateMultipartUploadRequest;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.MetadataDirective;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.model.UploadPartRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.PresignedPutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.PresignedUploadPartRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.UploadPartPresignRequest;

/**
 * 基于 S3 兼容协议实现对象存储访问。
 *
 * @author OmniNest
 */
@Component
public class MinioObjectStorageClient implements ObjectStorageClient {
    private final S3Client s3Client;
    private final S3Presigner s3Presigner;
    private final S3Presigner dockerS3Presigner;

    /**
     * 创建对象存储客户端。
     *
     * @param s3Client 服务端视角 S3 客户端
     * @param s3Presigner 服务端视角签名器
     * @param dockerS3Presigner 容器网络视角签名器（转码/探测容器访问用）
     */
    public MinioObjectStorageClient(
            S3Client s3Client,
            @Qualifier("s3Presigner") S3Presigner s3Presigner,
            @Qualifier("dockerS3Presigner") S3Presigner dockerS3Presigner
    ) {
        this.s3Client = s3Client;
        this.s3Presigner = s3Presigner;
        this.dockerS3Presigner = dockerS3Presigner;
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public URI createUploadUrl(ObjectStorageKey key, Duration ttl) {
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey())
                .build();
        PresignedPutObjectRequest presignedRequest = s3Presigner.presignPutObject(PutObjectPresignRequest.builder()
                .signatureDuration(ttl)
                .putObjectRequest(putObjectRequest)
                .build());
        return toUri(presignedRequest.url());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public URI createContainerDownloadUrl(ObjectStorageKey key, Duration ttl) {
        return toUri(dockerS3Presigner.presignGetObject(builder -> builder
                        .signatureDuration(ttl)
                        .getObjectRequest(request -> request
                                .bucket(key.bucket())
                                .key(key.objectKey())))
                .url());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public URI createDownloadUrl(ObjectStorageKey key, Duration ttl) {
        return toUri(s3Presigner.presignGetObject(builder -> builder
                        .signatureDuration(ttl)
                        .getObjectRequest(request -> request
                                .bucket(key.bucket())
                                .key(key.objectKey())))
                .url());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public URI createDownloadUrl(
            ObjectStorageKey key,
            Duration ttl,
            String responseContentType,
            String responseContentDisposition
    ) {
        GetObjectRequest.Builder request = GetObjectRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey());
        if (responseContentType != null && !responseContentType.isBlank()) {
            request.responseContentType(responseContentType);
        }
        if (responseContentDisposition != null && !responseContentDisposition.isBlank()) {
            request.responseContentDisposition(responseContentDisposition);
        }
        GetObjectRequest getObjectRequest = request.build();
        return toUri(s3Presigner.presignGetObject(builder -> builder
                        .signatureDuration(ttl)
                        .getObjectRequest(getObjectRequest))
                .url());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public String initiateMultipartUpload(ObjectStorageKey key, String contentType) {
        CreateMultipartUploadRequest.Builder builder = CreateMultipartUploadRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey());
        if (contentType != null && !contentType.isBlank()) {
            builder.contentType(contentType);
        }
        return s3Client.createMultipartUpload(builder.build()).uploadId();
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public URI createMultipartUploadPartUrl(ObjectStorageKey key, String uploadId, int partNumber, Duration ttl) {
        UploadPartRequest uploadPartRequest = UploadPartRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey())
                .uploadId(uploadId)
                .partNumber(partNumber)
                .build();
        PresignedUploadPartRequest presignedRequest = s3Presigner.presignUploadPart(UploadPartPresignRequest.builder()
                .signatureDuration(ttl)
                .uploadPartRequest(uploadPartRequest)
                .build());
        return toUri(presignedRequest.url());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void completeMultipartUpload(
            ObjectStorageKey key,
            String uploadId,
            List<ObjectStorageCompletedPart> parts
    ) {
        List<CompletedPart> completedParts = parts.stream()
                .map(part -> CompletedPart.builder()
                        .partNumber(part.partNumber())
                        .eTag(normalizeETag(part.eTag()))
                        .build())
                .toList();
        CompletedMultipartUpload multipartUpload = CompletedMultipartUpload.builder()
                .parts(completedParts)
                .build();
        CompleteMultipartUploadRequest request = CompleteMultipartUploadRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey())
                .uploadId(uploadId)
                .multipartUpload(multipartUpload)
                .build();

        // 带指数退避的重试逻辑，仅对瞬态错误重试
        int maxAttempts = 3;
        long delayMs = 1000;
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                s3Client.completeMultipartUpload(request);
                return;
            } catch (S3Exception e) {
                if (attempt == maxAttempts || !isRetryableS3Error(e)) {
                    throw e;
                }
                try {
                    Thread.sleep(delayMs);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw e;
                }
                delayMs *= 2;
            }
        }
    }

    private boolean isRetryableS3Error(S3Exception e) {
        int status = e.statusCode();
        return status >= 500 || status == 429;
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void abortMultipartUpload(ObjectStorageKey key, String uploadId) {
        s3Client.abortMultipartUpload(AbortMultipartUploadRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey())
                .uploadId(uploadId)
                .build());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public ObjectStorageCompletedPart uploadPart(
            ObjectStorageKey key, String uploadId, int partNumber,
            InputStream data, long size
    ) {
        UploadPartRequest request = UploadPartRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey())
                .uploadId(uploadId)
                .partNumber(partNumber)
                .contentLength(size)
                .build();
        String eTag = s3Client.uploadPart(request, RequestBody.fromInputStream(data, size)).eTag();
        return new ObjectStorageCompletedPart(partNumber, normalizeETag(eTag));
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void putObject(ObjectStorageKey key, Path source, String contentType) {
        PutObjectRequest.Builder builder = PutObjectRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey());
        if (contentType != null && !contentType.isBlank()) {
            builder.contentType(contentType);
        }
        s3Client.putObject(builder.build(), RequestBody.fromFile(source));
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void putObject(ObjectStorageKey key, InputStream data, long size, String contentType) {
        PutObjectRequest.Builder builder = PutObjectRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey());
        if (contentType != null && !contentType.isBlank()) {
            builder.contentType(contentType);
        }
        s3Client.putObject(builder.build(), RequestBody.fromInputStream(data, size));
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void copyObject(ObjectStorageKey source, ObjectStorageKey target) {
        s3Client.copyObject(CopyObjectRequest.builder()
                .sourceBucket(source.bucket())
                .sourceKey(source.objectKey())
                .destinationBucket(target.bucket())
                .destinationKey(target.objectKey())
                .build());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void copyObject(ObjectStorageKey source, ObjectStorageKey target, String contentType) {
        s3Client.copyObject(CopyObjectRequest.builder()
                .sourceBucket(source.bucket())
                .sourceKey(source.objectKey())
                .destinationBucket(target.bucket())
                .destinationKey(target.objectKey())
                .metadataDirective(MetadataDirective.REPLACE)
                .contentType(contentType)
                .build());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public InputStream getObject(ObjectStorageKey key) {
        return s3Client.getObject(GetObjectRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey())
                .build());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public boolean objectExists(ObjectStorageKey key) {
        try {
            s3Client.headObject(HeadObjectRequest.builder()
                    .bucket(key.bucket())
                    .key(key.objectKey())
                    .build());
            return true;
        } catch (NoSuchKeyException exception) {
            return false;
        } catch (S3Exception exception) {
            if (exception.statusCode() == 404) {
                return false;
            }
            throw exception;
        }
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void removeObject(ObjectStorageKey key) {
        s3Client.deleteObject(DeleteObjectRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey())
                .build());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public void removeObjectVersion(ObjectStorageKey key, String versionId) {
        s3Client.deleteObject(DeleteObjectRequest.builder()
                .bucket(key.bucket())
                .key(key.objectKey())
                .versionId(versionId)
                .build());
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public ObjectStoragePage listObjects(
            String bucket,
            String prefix,
            String continuationToken,
            int maxKeys
    ) {
        if (bucket == null || bucket.isBlank()) {
            throw new IllegalArgumentException("bucket is required");
        }
        if (maxKeys < 1 || maxKeys > 1000) {
            throw new IllegalArgumentException("maxKeys must be between 1 and 1000");
        }
        ListObjectsV2Request.Builder request = ListObjectsV2Request.builder()
                .bucket(bucket)
                .prefix(prefix == null ? "" : prefix)
                .maxKeys(maxKeys);
        if (continuationToken != null && !continuationToken.isBlank()) {
            request.continuationToken(continuationToken);
        }
        ListObjectsV2Response response = s3Client.listObjectsV2(request.build());
        List<ObjectStorageObject> objects = response.contents().stream()
                .map(item -> new ObjectStorageObject(item.key(), item.size(), item.lastModified()))
                .toList();
        String nextToken = Boolean.TRUE.equals(response.isTruncated())
                ? response.nextContinuationToken()
                : null;
        return new ObjectStoragePage(objects, nextToken);
    }

    private String normalizeETag(String eTag) {
        if (eTag == null) {
            return "";
        }
        return eTag.replace("\"", "");
    }

    private URI toUri(URL url) {
        return URI.create(url.toString());
    }
}
