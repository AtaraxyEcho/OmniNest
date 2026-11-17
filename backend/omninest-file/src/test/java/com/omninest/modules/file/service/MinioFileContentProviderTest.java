package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.dto.FileContentRange;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.net.URI;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * MinIO 内容提供者下载地址安全测试。
 * 重点覆盖危险类型强制附件下载。
 *
 * @author OmniNest
 */
@DisplayName("MinioFileContentProvider 下载地址安全测试")
class MinioFileContentProviderTest {

    private static final UUID NODE_ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final UUID OBJECT_ID = UUID.fromString("00000000-0000-0000-0000-000000000002");

    private final FileObjectRepository fileObjectRepository = mock(FileObjectRepository.class);
    private final ObjectStorageClient objectStorageClient = mock(ObjectStorageClient.class);
    private final MinioFileContentProvider provider =
            new MinioFileContentProvider(fileObjectRepository, objectStorageClient);

    @BeforeEach
    void setUp() {
        when(objectStorageClient.createDownloadUrl(any(ObjectStorageKey.class), any(Duration.class)))
                .thenReturn(URI.create("https://minio/plain"));
        when(objectStorageClient.createDownloadUrl(
                        any(ObjectStorageKey.class), any(Duration.class), anyString(), anyString()))
                .thenReturn(URI.create("https://minio/attachment"));
    }

    @Test
    @DisplayName("普通类型维持内联语义，不追加响应覆盖参数")
    void keepsInlineSemanticsForSafeTypes() {
        FileNode node = node("photo.jpg", "image/jpeg");

        FileDownloadUrlDto result = provider.createDownloadUrl(node);

        assertThat(result.downloadUrl()).isEqualTo("https://minio/plain");
        verify(objectStorageClient, never()).createDownloadUrl(
                any(ObjectStorageKey.class), any(Duration.class), anyString(), anyString());
    }

    @Test
    @DisplayName("HTML/SVG 等危险类型强制附件下载并覆盖为 octet-stream")
    void forcesAttachmentForInlineExecutableTypes() {
        FileNode html = node("page.html", "text/html");
        FileNode svg = node("icon.svg", "image/svg+xml");

        assertThat(provider.createDownloadUrl(html).downloadUrl()).isEqualTo("https://minio/attachment");
        assertThat(provider.createDownloadUrl(svg).downloadUrl()).isEqualTo("https://minio/attachment");

        ArgumentCaptor<String> disposition = ArgumentCaptor.forClass(String.class);
        verify(objectStorageClient, org.mockito.Mockito.times(2)).createDownloadUrl(
                any(ObjectStorageKey.class), any(Duration.class), eq("application/octet-stream"),
                disposition.capture());
        assertThat(disposition.getAllValues())
                .allSatisfy(value -> assertThat(value).startsWith("attachment; filename*=UTF-8''"));
    }

    @Test
    @DisplayName("区间读把偏移与长度交给存储客户端，并回报对象完整长度")
    void readsRangeAndReportsTotalObjectSize() throws IOException {
        FileNode node = node("clip.mp4", "video/mp4");
        when(objectStorageClient.getObject(any(ObjectStorageKey.class), eq(1_048_576L), eq(4L)))
                .thenReturn(new ByteArrayInputStream(new byte[]{1, 2, 3, 4}));

        FileContentRange range = provider.openRange(node, 1_048_576L, 4L).orElseThrow();

        assertThat(range.totalBytes()).isEqualTo(9_000_000L);
        assertThat(range.inputStream().readAllBytes()).containsExactly(1, 2, 3, 4);
        ArgumentCaptor<ObjectStorageKey> key = ArgumentCaptor.forClass(ObjectStorageKey.class);
        verify(objectStorageClient).getObject(key.capture(), eq(1_048_576L), eq(4L));
        assertThat(key.getValue().bucket()).isEqualTo("user-files");
        assertThat(key.getValue().objectKey()).isEqualTo("users/1/files/clip.mp4");
    }

    private FileNode node(String name, String mimeType) {
        FileObject object = new FileObject();
        object.setId(OBJECT_ID);
        object.setBucketName("user-files");
        object.setObjectKey("users/1/files/" + name);
        object.setMimeType(mimeType);
        object.setSizeBytes(9_000_000L);
        FileNode fileNode = new FileNode();
        fileNode.setId(NODE_ID);
        fileNode.setName(name);
        fileNode.setCurrentObjectId(OBJECT_ID);
        when(fileObjectRepository.findById(OBJECT_ID)).thenReturn(Optional.of(object));
        return fileNode;
    }
}
