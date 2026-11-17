package com.omninest.common.storage;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;
import org.springframework.boot.health.contributor.Status;

/**
 * 对象存储健康探针测试。
 *
 * @author OmniNest
 */
class MinioHealthIndicatorTest {

    private final ObjectStorageClient objectStorageClient = mock(ObjectStorageClient.class);
    private final ObjectStorageBuckets buckets = mock(ObjectStorageBuckets.class);
    private final MinioHealthIndicator indicator = new MinioHealthIndicator(objectStorageClient, buckets);

    @Test
    void reportsUpWhenStorageAnswersProbe() {
        when(buckets.userFiles()).thenReturn("user-files");
        when(objectStorageClient.objectExists(any(ObjectStorageKey.class))).thenReturn(false);

        assertThat(indicator.health().getStatus()).isEqualTo(Status.UP);
    }

    @Test
    void reportsDownWhenStorageThrows() {
        when(buckets.userFiles()).thenReturn("user-files");
        when(objectStorageClient.objectExists(any(ObjectStorageKey.class)))
                .thenThrow(new IllegalStateException("minio unreachable"));

        assertThat(indicator.health().getStatus()).isEqualTo(Status.DOWN);
    }
}
