package com.omninest.common.storage;

import java.time.Instant;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.ListPartsRequest;
import software.amazon.awssdk.services.s3.model.ListPartsResponse;
import software.amazon.awssdk.services.s3.model.NoSuchUploadException;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.model.S3Object;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

/**
 * MinIO 对象存储分页清单测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class MinioObjectStorageClientTest {

    @Mock
    private S3Client s3Client;

    @Mock
    private S3Presigner s3Presigner;

    @InjectMocks
    private MinioObjectStorageClient storageClient;

    @Test
    void listObjectsMapsBoundedPageAndContinuationToken() {
        Instant modifiedAt = Instant.parse("2026-07-25T00:00:00Z");
        ListObjectsV2Response response = ListObjectsV2Response.builder()
                .contents(S3Object.builder()
                        .key("derived/poster.jpg")
                        .size(128L)
                        .lastModified(modifiedAt)
                        .build())
                .isTruncated(true)
                .nextContinuationToken("next-page")
                .build();
        Mockito.when(s3Client.listObjectsV2(ArgumentMatchers.any(ListObjectsV2Request.class)))
                .thenReturn(response);

        ObjectStoragePage page = storageClient.listObjects(
                "derived-assets",
                "derived/",
                "current-page",
                200
        );

        Assertions.assertThat(page.objects())
                .containsExactly(new ObjectStorageObject("derived/poster.jpg", 128L, modifiedAt));
        Assertions.assertThat(page.nextContinuationToken()).isEqualTo("next-page");
        Assertions.assertThat(page.hasNext()).isTrue();

        ArgumentCaptor<ListObjectsV2Request> requestCaptor = ArgumentCaptor.forClass(
                ListObjectsV2Request.class
        );
        Mockito.verify(s3Client).listObjectsV2(requestCaptor.capture());
        Assertions.assertThat(requestCaptor.getValue().bucket()).isEqualTo("derived-assets");
        Assertions.assertThat(requestCaptor.getValue().prefix()).isEqualTo("derived/");
        Assertions.assertThat(requestCaptor.getValue().continuationToken()).isEqualTo("current-page");
        Assertions.assertThat(requestCaptor.getValue().maxKeys()).isEqualTo(200);
    }

    @Test
    void multipartUploadExistsReturnsTrueWhenUploadIsListable() {
        ObjectStorageKey key = new ObjectStorageKey("file-quarantine", "uploads/demo.bin");
        Mockito.when(s3Client.listParts(ArgumentMatchers.any(ListPartsRequest.class)))
                .thenReturn(ListPartsResponse.builder().build());

        Assertions.assertThat(storageClient.multipartUploadExists(key, "upload-1")).isTrue();
    }

    @Test
    void multipartUploadExistsTreatsMissingUploadAsAbsent() {
        ObjectStorageKey key = new ObjectStorageKey("file-quarantine", "uploads/demo.bin");
        Mockito.when(s3Client.listParts(ArgumentMatchers.any(ListPartsRequest.class)))
                .thenThrow(NoSuchUploadException.builder().message("missing").statusCode(404).build());

        Assertions.assertThat(storageClient.multipartUploadExists(key, "upload-1")).isFalse();
    }

    @Test
    void multipartUploadExistsPropagatesStorageFailure() {
        ObjectStorageKey key = new ObjectStorageKey("file-quarantine", "uploads/demo.bin");
        Mockito.when(s3Client.listParts(ArgumentMatchers.any(ListPartsRequest.class)))
                .thenThrow(S3Exception.builder().message("boom").statusCode(503).build());

        Assertions.assertThatThrownBy(() -> storageClient.multipartUploadExists(key, "upload-1"))
                .isInstanceOf(S3Exception.class);
    }
}
