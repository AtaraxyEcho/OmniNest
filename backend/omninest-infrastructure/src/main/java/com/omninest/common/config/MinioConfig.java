package com.omninest.common.config;

import io.minio.MinioClient;
import java.net.URI;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

/**
 * MinIO 客户端配置。
 *
 * @author OmniNest
 */
@Configuration
@EnableConfigurationProperties({MinioProperties.class, UploadProperties.class})
public class MinioConfig {

    /**
     * 创建后端直连 MinIO 的客户端。
     *
     * @param properties MinIO 配置
     * @return MinIO 客户端
     */
    @Bean
    public MinioClient minioClient(MinioProperties properties) {
        return MinioClient.builder()
                .endpoint(properties.getEndpoint())
                .credentials(properties.getAccessKey(), properties.getSecretKey())
                .build();
    }

    /**
     * 创建后端直连 MinIO 的 S3 客户端。
     *
     * @param properties MinIO 配置
     * @return S3 客户端
     */
    @Bean
    public S3Client s3Client(MinioProperties properties) {
        return S3Client.builder()
                .endpointOverride(URI.create(properties.getEndpoint()))
                .credentialsProvider(credentialsProvider(properties))
                .region(Region.US_EAST_1)
                .serviceConfiguration(s3Configuration())
                .overrideConfiguration(o -> o
                        .apiCallTimeout(Duration.ofSeconds(properties.getApiCallTimeoutSeconds()))
                        .apiCallAttemptTimeout(Duration.ofSeconds(properties.getApiCallAttemptTimeoutSeconds())))
                .build();
    }

    /**
     * 创建面向终端客户端的预签名器。
     *
     * @param properties MinIO 配置
     * @return 客户端预签名器
     */
    @Bean
    public S3Presigner s3Presigner(MinioProperties properties) {
        return S3Presigner.builder()
                .endpointOverride(URI.create(clientEndpoint(properties)))
                .credentialsProvider(credentialsProvider(properties))
                .region(Region.US_EAST_1)
                .serviceConfiguration(s3Configuration())
                .build();
    }

    /**
     * Docker 内部网络专用的 S3Presigner，使用 dockerEndpoint 生成预签名 URL。
     * 用于 ffmpeg 容器通过 Docker 网络访问 MinIO。
     *
     * @param properties MinIO 配置
     * @return Docker 内部预签名器
     */
    @Bean
    @Qualifier("dockerS3Presigner")
    public S3Presigner dockerS3Presigner(MinioProperties properties) {
        String dockerEndpoint = properties.getDockerEndpoint();
        if (dockerEndpoint == null || dockerEndpoint.isBlank()) {
            dockerEndpoint = properties.getEndpoint();
        }
        return S3Presigner.builder()
                .endpointOverride(URI.create(dockerEndpoint))
                .credentialsProvider(credentialsProvider(properties))
                .region(Region.US_EAST_1)
                .serviceConfiguration(s3Configuration())
                .build();
    }

    private String clientEndpoint(MinioProperties properties) {
        String publicEndpoint = properties.getPublicEndpoint();
        if (publicEndpoint == null || publicEndpoint.isBlank()) {
            return properties.getEndpoint();
        }
        return publicEndpoint;
    }

    private StaticCredentialsProvider credentialsProvider(MinioProperties properties) {
        return StaticCredentialsProvider.create(
                AwsBasicCredentials.create(properties.getAccessKey(), properties.getSecretKey())
        );
    }

    private S3Configuration s3Configuration() {
        return S3Configuration.builder()
                .pathStyleAccessEnabled(true)
                .build();
    }
}
