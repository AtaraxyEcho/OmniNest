package com.omninest.common.config;

import java.util.LinkedHashMap;
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
            "CHANGE_ME_ARIA2_RPC_SECRET",
            "CHANGE_ME_RCLONE_RC_PASS",
            "CHANGE_ME_JWT_SECRET_AT_LEAST_32_BYTES",
            "CHANGE_ME_AI_SIDECAR_SECRET"
    );

    private static final Map<String, String> REQUIRED_SECRETS = new LinkedHashMap<>();

    static {
        REQUIRED_SECRETS.put("spring.datasource.password", "OMNINEST_DB_PASSWORD");
        REQUIRED_SECRETS.put("spring.rabbitmq.password", "OMNINEST_RABBITMQ_PASSWORD");
        REQUIRED_SECRETS.put("spring.data.redis.password", "OMNINEST_REDIS_PASSWORD");
        REQUIRED_SECRETS.put("omninest.minio.access-key", "OMNINEST_MINIO_ACCESS_KEY");
        REQUIRED_SECRETS.put("omninest.minio.secret-key", "OMNINEST_MINIO_SECRET_KEY");
        REQUIRED_SECRETS.put("omninest.rclone.password", "OMNINEST_RCLONE_RC_PASS");
        REQUIRED_SECRETS.put("omninest.aria2.rpc-secret", "OMNINEST_ARIA2_RPC_SECRET");
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
        }
        requireNotPublishedDefault("omninest.security.jwt-secret", "OMNINEST_SECURITY_JWT_SECRET");
        requireNotPublishedDefault("photo.ai.secret", "OMNINEST_AI_SIDECAR_SECRET");
        if (environment.getProperty("omninest.setup.enabled", Boolean.class, Boolean.FALSE)) {
            requireConfigured("omninest.setup.token", "OMNINEST_SETUP_TOKEN");
            requireNotPublishedDefault("omninest.setup.token", "OMNINEST_SETUP_TOKEN");
        }
    }

    private void requireConfigured(String propertyKey, String envName) {
        String value = environment.getProperty(propertyKey);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(
                    "生产环境必须配置 %s（%s），禁止依赖空默认值启动".formatted(envName, propertyKey));
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
