package com.omninest.common.config;

import io.minio.BucketExistsArgs;
import io.minio.MinioClient;
import io.minio.SetBucketPolicyArgs;
import java.io.IOException;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.boot.ApplicationArguments;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

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
        MinioBucketInitializer initializer =
                new MinioBucketInitializer(minioClient, properties, environment(false));

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

    @Test
    void productionRefusesToStartWhenBucketStateCannotBeVerified() throws Exception {
        MinioClient minioClient = Mockito.mock(MinioClient.class);
        MinioProperties properties = new MinioProperties();
        Mockito.when(minioClient.bucketExists(Mockito.any(BucketExistsArgs.class)))
                .thenThrow(new IOException("minio unreachable"));
        MinioBucketInitializer initializer =
                new MinioBucketInitializer(minioClient, properties, environment(true));

        // 托管桶必须私有：策略未验证就起跑，健康探针看不出异常而对象可能对外可读。
        Assertions.assertThatThrownBy(() -> initializer.run(Mockito.mock(ApplicationArguments.class)))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("拒绝以未验证状态启动");
    }

    @Test
    void nonProductionToleratesMinioFailureSoLocalStartupSurvives() throws Exception {
        MinioClient minioClient = Mockito.mock(MinioClient.class);
        MinioProperties properties = new MinioProperties();
        Mockito.when(minioClient.bucketExists(Mockito.any(BucketExistsArgs.class)))
                .thenThrow(new IOException("minio unreachable"));
        MinioBucketInitializer initializer =
                new MinioBucketInitializer(minioClient, properties, environment(false));

        initializer.run(Mockito.mock(ApplicationArguments.class));

        Mockito.verify(minioClient, Mockito.times(3))
                .bucketExists(Mockito.any(BucketExistsArgs.class));
    }

    private static Environment environment(boolean production) {
        Environment environment = Mockito.mock(Environment.class);
        Mockito.when(environment.acceptsProfiles(Mockito.any(Profiles.class))).thenReturn(production);
        return environment;
    }
}
