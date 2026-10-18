package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.StandardEnvironment;
import org.springframework.mock.env.MockEnvironment;

class ProductionSecretsValidatorTest {

    @Test
    @DisplayName("dev Profile 不校验生产凭据")
    void skipsValidationOutsideProd() {
        MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles("dev");
        assertThatCode(() -> new ProductionSecretsValidator(environment).validate())
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("prod 启动失败：关键凭据为空")
    void failsWhenRequiredSecretsAreBlank() {
        MockEnvironment environment = prodEnvironment();
        environment.setProperty("spring.datasource.password", "");
        assertThatThrownBy(() -> new ProductionSecretsValidator(environment).validate())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("OMNINEST_DB_PASSWORD");
    }

    @Test
    @DisplayName("prod 启动失败：Redis 口令为空")
    void failsWhenRedisPasswordIsBlank() {
        MockEnvironment environment = completeProdEnvironment();
        environment.setProperty("spring.data.redis.password", " ");
        assertThatThrownBy(() -> new ProductionSecretsValidator(environment).validate())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("OMNINEST_REDIS_PASSWORD");
    }

    @Test
    @DisplayName("prod 启动失败：JWT/AI/Setup 仍为文档示例值")
    void failsWhenSecretsUsePublishedDefaults() {
        MockEnvironment environment = completeProdEnvironment();
        environment.setProperty(
                "omninest.security.jwt-secret",
                "change-me-omninest-local-jwt-secret-at-least-32-bytes");
        assertThatThrownBy(() -> new ProductionSecretsValidator(environment).validate())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("OMNINEST_SECURITY_JWT_SECRET");
    }

    @Test
    @DisplayName("prod 启动失败：安装开启但 Setup Token 仍为示例值")
    void failsWhenSetupTokenIsPublishedDefault() {
        MockEnvironment environment = completeProdEnvironment();
        environment.setProperty("omninest.setup.enabled", "true");
        environment.setProperty("omninest.setup.token", "change-me-omninest-setup-token-at-least-32-bytes");
        assertThatThrownBy(() -> new ProductionSecretsValidator(environment).validate())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("OMNINEST_SETUP_TOKEN");
    }

    @Test
    @DisplayName("prod 启动失败：凭据仍为 CHANGE_ME 占位")
    void failsWhenSecretsUseChangeMePlaceholders() {
        MockEnvironment environment = completeProdEnvironment();
        environment.setProperty("spring.datasource.password", "CHANGE_ME_DB_PASSWORD");
        assertThatThrownBy(() -> new ProductionSecretsValidator(environment).validate())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("OMNINEST_DB_PASSWORD");
    }

    @Test
    @DisplayName("prod 启动失败：外部存储凭据加密密钥为空")
    void failsWhenCredentialEncryptionKeyIsBlank() {
        MockEnvironment environment = completeProdEnvironment();
        environment.setProperty("omninest.security.credential-encryption-key", " ");
        assertThatThrownBy(() -> new ProductionSecretsValidator(environment).validate())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY");
    }

    @Test
    @DisplayName("prod 启动成功：关键凭据均已显式配置")
    void succeedsWhenSecretsAreConfigured() {
        assertThatCode(() -> new ProductionSecretsValidator(completeProdEnvironment()).validate())
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("prod Profile 探测：acceptsProfiles 生效")
    void detectsProdProfile() {
        StandardEnvironment environment = new StandardEnvironment();
        environment.setActiveProfiles("prod");
        environment.getPropertySources().addFirst(new MapPropertySource(
                "prod-secrets",
                Map.of(
                        "spring.datasource.password", "db-secret-0123456789abcdef",
                        "spring.rabbitmq.password", "mq-secret-0123456789abcdef",
                        "spring.data.redis.password", "redis-secret-0123456789ab",
                        "omninest.minio.access-key", "minio-access",
                        "omninest.minio.secret-key", "minio-secret-0123456789abcd",
                        "omninest.rclone.password", "rclone-secret-0123456789ab",
                        "omninest.security.credential-encryption-key",
                                "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=",
                        "omninest.security.jwt-secret", "jwt-secret-at-least-32-bytes-long!!"
                )
        ));
        assertThatCode(() -> new ProductionSecretsValidator(environment).validate())
                .doesNotThrowAnyException();
    }

    private static MockEnvironment prodEnvironment() {
        MockEnvironment environment = new MockEnvironment();
        environment.setActiveProfiles("prod");
        return environment;
    }

    private static MockEnvironment completeProdEnvironment() {
        MockEnvironment environment = prodEnvironment();
        environment.setProperty("spring.datasource.password", "db-secret-0123456789abcdef");
        environment.setProperty("spring.rabbitmq.password", "mq-secret-0123456789abcdef");
        environment.setProperty("spring.data.redis.password", "redis-secret-0123456789ab");
        environment.setProperty("omninest.minio.access-key", "minio-access");
        environment.setProperty("omninest.minio.secret-key", "minio-secret-0123456789abcd");
        environment.setProperty("omninest.rclone.password", "rclone-secret-0123456789ab");
        environment.setProperty("omninest.security.credential-encryption-key",
                "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=");
        environment.setProperty("omninest.security.jwt-secret", "jwt-secret-at-least-32-bytes-long!!");
        environment.setProperty("photo.ai.secret", "ai-sidecar-secret-0123456789");
        environment.setProperty("omninest.setup.enabled", "false");
        return environment;
    }

    @Test
    @DisplayName("prod 启动失败：口令为服务默认名等弱词")
    void failsWhenSecretIsWellKnownWeakValue() {
        MockEnvironment environment = completeProdEnvironment();
        environment.setProperty("spring.datasource.password", "omninest");
        assertThatThrownBy(() -> new ProductionSecretsValidator(environment).validate())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("弱口令");
    }

    @Test
    @DisplayName("prod 启动失败：口令长度不足 16")
    void failsWhenSecretShorterThanMinimumLength() {
        MockEnvironment environment = completeProdEnvironment();
        environment.setProperty("spring.data.redis.password", "short-pass");
        assertThatThrownBy(() -> new ProductionSecretsValidator(environment).validate())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("长度不足");
    }

    @Test
    @DisplayName("MinIO access-key 豁免长度要求但不豁免弱词黑名单")
    void accessKeyExemptFromLengthButNotBlacklist() {
        MockEnvironment environment = completeProdEnvironment();
        environment.setProperty("omninest.minio.access-key", "mn-ak");
        assertThatCode(() -> new ProductionSecretsValidator(environment).validate())
                .doesNotThrowAnyException();

        environment.setProperty("omninest.minio.access-key", "minioadmin");
        assertThatThrownBy(() -> new ProductionSecretsValidator(environment).validate())
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("弱口令");
    }
}
