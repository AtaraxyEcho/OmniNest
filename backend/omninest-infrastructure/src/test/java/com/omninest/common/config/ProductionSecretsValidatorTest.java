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
                        "spring.datasource.password", "db-secret",
                        "spring.rabbitmq.password", "mq-secret",
                        "spring.data.redis.password", "redis-secret",
                        "omninest.minio.access-key", "minio-access",
                        "omninest.minio.secret-key", "minio-secret",
                        "omninest.rclone.password", "rclone-secret",
                        "omninest.aria2.rpc-secret", "aria2-secret",
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
        environment.setProperty("spring.datasource.password", "db-secret");
        environment.setProperty("spring.rabbitmq.password", "mq-secret");
        environment.setProperty("spring.data.redis.password", "redis-secret");
        environment.setProperty("omninest.minio.access-key", "minio-access");
        environment.setProperty("omninest.minio.secret-key", "minio-secret");
        environment.setProperty("omninest.rclone.password", "rclone-secret");
        environment.setProperty("omninest.aria2.rpc-secret", "aria2-secret");
        environment.setProperty("omninest.security.jwt-secret", "jwt-secret-at-least-32-bytes-long!!");
        environment.setProperty("photo.ai.secret", "ai-sidecar-secret");
        environment.setProperty("omninest.setup.enabled", "false");
        return environment;
    }
}
