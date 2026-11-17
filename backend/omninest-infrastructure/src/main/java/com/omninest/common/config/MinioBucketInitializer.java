package com.omninest.common.config;

import io.minio.BucketExistsArgs;
import io.minio.MakeBucketArgs;
import io.minio.MinioClient;
import io.minio.SetBucketPolicyArgs;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * 应用启动时自动创建业务使用的 MinIO bucket，并强制私有策略。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class MinioBucketInitializer implements ApplicationRunner {

    /**
     * 空 Statement 的策略等价于拒绝匿名访问，下载只能走短期签名 URL。
     */
    private static final String PRIVATE_BUCKET_POLICY =
            "{\"Version\":\"2012-10-17\",\"Statement\":[]}";

    private final MinioClient minioClient;
    private final MinioProperties minioProperties;
    private final Environment environment;

    @Override
    public void run(ApplicationArguments args) {
        MinioProperties.Buckets buckets = minioProperties.getBuckets();
        boolean production = environment != null
                && environment.acceptsProfiles(Profiles.of("prod"));
        List<String> bucketNames = List.of(
                buckets.getUserFiles(),
                buckets.getDerivedAssets(),
                buckets.getQuarantine()
        );
        for (String bucketName : bucketNames) {
            ensureBucket(bucketName, production);
        }
    }

    void ensureBucket(String bucketName, boolean production) {
        try {
            boolean exists = minioClient.bucketExists(
                    BucketExistsArgs.builder().bucket(bucketName).build()
            );
            if (!exists) {
                minioClient.makeBucket(
                        MakeBucketArgs.builder().bucket(bucketName).build()
                );
                log.info("MinIO bucket 已创建: {}", bucketName);
            }
            minioClient.setBucketPolicy(
                    SetBucketPolicyArgs.builder()
                            .bucket(bucketName)
                            .config(PRIVATE_BUCKET_POLICY)
                            .build()
            );
        } catch (Exception e) {
            // 托管桶必须私有：MinIO 不可达或策略下发被拒时，生产 profile 不能带着
            // "桶不存在/策略未验证"的状态起跑，否则健康探针看不出异常而对象可能对外可读。
            if (production) {
                throw new IllegalStateException(
                        "生产环境无法确认 MinIO bucket 及其私有策略，拒绝以未验证状态启动: " + bucketName, e);
            }
            log.error("检查或创建 MinIO bucket 失败: {}", bucketName, e);
        }
    }
}
