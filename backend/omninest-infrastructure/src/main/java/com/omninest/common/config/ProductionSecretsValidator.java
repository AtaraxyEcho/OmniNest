package com.omninest.common.config;

import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * 生产 Profile 启动时拒绝空白或仍为公开示例值的关键凭据。
 *
 * <p>本校验只拦截“缺省未配置”和“文档示例默认值”，不承担口令强度策略。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ProductionSecretsValidator implements ApplicationRunner {

    private static final Set<String> PUBLISHED_DEFAULT_SECRETS = Set.of(
            "change-me-omninest-local-jwt-secret-at-least-32-bytes",
            "change-me-ai-sidecar-random-secret",
            "change-me-omninest-setup-token-at-least-32-bytes",
            "CHANGE_ME_DB_PASSWORD",
            "CHANGE_ME_REDIS_PASSWORD",
            "CHANGE_ME_RABBITMQ_PASSWORD",
            "CHANGE_ME_MINIO_USER",
            "CHANGE_ME_MINIO_PASSWORD",
            "CHANGE_ME_RCLONE_RC_PASS",
            "CHANGE_ME_JWT_SECRET_AT_LEAST_32_BYTES",
            "CHANGE_ME_AI_SIDECAR_SECRET",
            // dev 模板公开的 32 零字节 Base64 KEK：是合法 AES-256 密钥，必须点名拒绝
            "QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE=",
            // application-dev.yml 公开的凭据加密 KEK，与零字节密钥同属可用但不应上生产的默认值
            "b21uaW5lc3QtZGV2LWNyZWRlbnRpYWwta2V5LTAwMDE="
    );

    private static final Map<String, String> REQUIRED_SECRETS = new LinkedHashMap<>();

    /**
     * 众所周知的服务默认口令与通用弱词，命中即拒绝启动。
     */
    private static final Set<String> WEAK_SECRET_VALUES = Set.of(
            "omninest", "minioadmin", "minio", "secret", "password", "changeme",
            "rabbitmq", "postgres", "redis", "admin", "omninest123", "123456"
    );

    /**
     * 口令类凭据的最小长度；访问密钥类用户名不受此约束。
     */
    private static final int MIN_SECRET_LENGTH = 16;

    static {
        REQUIRED_SECRETS.put("spring.datasource.password", "OMNINEST_DB_PASSWORD");
        REQUIRED_SECRETS.put("spring.rabbitmq.password", "OMNINEST_RABBITMQ_PASSWORD");
        REQUIRED_SECRETS.put("spring.data.redis.password", "OMNINEST_REDIS_PASSWORD");
        REQUIRED_SECRETS.put("omninest.minio.access-key", "OMNINEST_MINIO_ACCESS_KEY");
        REQUIRED_SECRETS.put("omninest.minio.secret-key", "OMNINEST_MINIO_SECRET_KEY");
        REQUIRED_SECRETS.put("omninest.rclone.password", "OMNINEST_RCLONE_RC_PASS");
        REQUIRED_SECRETS.put("omninest.security.credential-encryption-key", "OMNINEST_SECURITY_CREDENTIAL_ENCRYPTION_KEY");
    }

    private final Environment environment;

    @Override
    public void run(ApplicationArguments args) {
        validate();
    }

    void validate() {
        if (environment == null || !environment.acceptsProfiles(Profiles.of("prod"))) {
            return;
        }
        for (Map.Entry<String, String> entry : REQUIRED_SECRETS.entrySet()) {
            requireConfigured(entry.getKey(), entry.getValue());
            requireNotPublishedDefault(entry.getKey(), entry.getValue());
            requireNotWeakSecret(entry.getKey(), entry.getValue());
        }
        requireNotPublishedDefault("omninest.security.jwt-secret", "OMNINEST_SECURITY_JWT_SECRET");
        requireNotWeakSecret("omninest.security.jwt-secret", "OMNINEST_SECURITY_JWT_SECRET");
        requireNotPublishedDefault("photo.ai.secret", "OMNINEST_AI_SIDECAR_SECRET");
        requireNotWeakSecret("photo.ai.secret", "OMNINEST_AI_SIDECAR_SECRET");
        if (environment.getProperty("omninest.setup.enabled", Boolean.class, Boolean.FALSE)) {
            requireConfigured("omninest.setup.token", "OMNINEST_SETUP_TOKEN");
            requireNotPublishedDefault("omninest.setup.token", "OMNINEST_SETUP_TOKEN");
            requireNotWeakSecret("omninest.setup.token", "OMNINEST_SETUP_TOKEN");
        }
    }

    private void requireConfigured(String propertyKey, String envName) {
        String value = environment.getProperty(propertyKey);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(
                    "生产环境必须配置 %s（%s），禁止依赖空默认值启动".formatted(envName, propertyKey));
        }
    }

    /**
     * 拦截"非文档示例值但仍然众所周知"的弱口令（服务默认名、通用词）。
     * 访问密钥类用户名（MinIO access-key）只做黑名单不做长度要求。
     */
    private void requireNotWeakSecret(String propertyKey, String envName) {
        String value = environment.getProperty(propertyKey);
        if (value == null) {
            return;
        }
        String normalized = value.trim().toLowerCase(Locale.ROOT);
        if (WEAK_SECRET_VALUES.contains(normalized)) {
            throw new IllegalStateException(
                    "生产环境禁止使用弱口令：%s（%s）的值是服务默认名或通用词，请用 openssl rand -base64 32 生成独立凭据"
                            .formatted(envName, propertyKey));
        }
        if ("omninest.minio.access-key".equals(propertyKey)) {
            return;
        }
        if (value.trim().length() < MIN_SECRET_LENGTH) {
            throw new IllegalStateException(
                    "生产环境凭据长度不足：%s（%s）至少 %d 个字符，请用 openssl rand -base64 32 生成"
                            .formatted(envName, propertyKey, MIN_SECRET_LENGTH));
        }
    }

    private void requireNotPublishedDefault(String propertyKey, String envName) {
        String value = environment.getProperty(propertyKey);
        if (value == null) {
            return;
        }
        if (PUBLISHED_DEFAULT_SECRETS.contains(value) || value.startsWith("CHANGE_ME_")) {
            throw new IllegalStateException(
                    "生产环境禁止使用文档示例默认值：%s（%s）".formatted(envName, propertyKey));
        }
    }
}
