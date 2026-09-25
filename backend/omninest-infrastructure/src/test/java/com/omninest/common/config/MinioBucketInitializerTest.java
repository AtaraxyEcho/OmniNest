package com.omninest.common.config;

import io.minio.BucketExistsArgs;
import io.minio.MinioClient;
import io.minio.SetBucketPolicyArgs;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.boot.ApplicationArguments;

/**
 * 验证 MinIO 启动建桶范围。
 *
 * @author OmniNest
 */
class MinioBucketInitializerTest {

    @Test
    void initializesOnlyBucketsUsedByProductionCode() throws Exception {
        MinioClient minioClient = Mockito.mock(MinioClient.class);
        MinioProperties properties = new MinioProperties();
        properties.getBuckets().setUserFiles("user-files-test");
        properties.getBuckets().setDerivedAssets("derived-assets-test");
        properties.getBuckets().setQuarantine("file-quarantine-test");
        Mockito.when(minioClient.bucketExists(Mockito.any(BucketExistsArgs.class))).thenReturn(true);
        MinioBucketInitializer initializer = new MinioBucketInitializer(minioClient, properties);

        initializer.run(Mockito.mock(ApplicationArguments.class));

        ArgumentCaptor<BucketExistsArgs> captor = ArgumentCaptor.forClass(BucketExistsArgs.class);
        Mockito.verify(minioClient, Mockito.times(3)).bucketExists(captor.capture());
        Assertions.assertThat(captor.getAllValues())
                .extracting(BucketExistsArgs::bucket)
                .containsExactly("user-files-test", "derived-assets-test", "file-quarantine-test");
        Mockito.verify(minioClient, Mockito.never()).makeBucket(Mockito.any());
        ArgumentCaptor<SetBucketPolicyArgs> policyCaptor =
                ArgumentCaptor.forClass(SetBucketPolicyArgs.class);
        Mockito.verify(minioClient, Mockito.times(3)).setBucketPolicy(policyCaptor.capture());
        Assertions.assertThat(policyCaptor.getAllValues())
                .extracting(SetBucketPolicyArgs::config)
                .containsOnly("{\"Version\":\"2012-10-17\",\"Statement\":[]}");
    }
}
