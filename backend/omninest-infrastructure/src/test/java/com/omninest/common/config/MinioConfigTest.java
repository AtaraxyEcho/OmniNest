package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import org.junit.jupiter.api.Test;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.PresignedGetObjectRequest;

/**
 * MinIO 客户端端点配置测试。
 *
 * @author OmniNest
 */
class MinioConfigTest {

    @Test
    void clientPresignerUsesPublicEndpoint() {
        MinioProperties properties = properties();
        properties.setPublicEndpoint("http://192.168.1.206:9000");

        MinioConfig config = new MinioConfig();
        try (S3Presigner presigner = config.s3Presigner(properties)) {
            PresignedGetObjectRequest request = presigner.presignGetObject(builder -> builder
                    .signatureDuration(Duration.ofMinutes(5))
                    .getObjectRequest(object -> object.bucket("user-files").key("cover.jpg")));

            assertThat(request.url().getHost()).isEqualTo("192.168.1.206");
        }
    }

    @Test
    void clientPresignerFallsBackToInternalEndpoint() {
        MinioProperties properties = properties();

        MinioConfig config = new MinioConfig();
        try (S3Presigner presigner = config.s3Presigner(properties)) {
            PresignedGetObjectRequest request = presigner.presignGetObject(builder -> builder
                    .signatureDuration(Duration.ofMinutes(5))
                    .getObjectRequest(object -> object.bucket("user-files").key("cover.jpg")));

            assertThat(request.url().getHost()).isEqualTo("localhost");
        }
    }

    private MinioProperties properties() {
        MinioProperties properties = new MinioProperties();
        properties.setEndpoint("http://localhost:9000");
        properties.setAccessKey("test-access-key");
        properties.setSecretKey("test-secret-key");
        return properties;
    }
}
