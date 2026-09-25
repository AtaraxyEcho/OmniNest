package com.omninest.common.config;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * 启动时校验 JWT secret 的基本强度，并在生产 Profile 拒绝公开兼容默认值。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class JwtSecretValidator implements ApplicationRunner {

    private static final String DEFAULT_SECRET = "change-me-omninest-local-jwt-secret-at-least-32-bytes";

    private final SecurityProperties securityProperties;
    private final Environment environment;

    @Override
    public void run(ApplicationArguments args) {
        validate();
    }

    void validate() {
        validate(environment != null && environment.acceptsProfiles(Profiles.of("prod")));
    }

    void validate(boolean production) {
        String secret = securityProperties.getJwtSecret();
        if (secret == null || secret.isBlank() || secret.length() < 32) {
            throw new IllegalStateException("JWT secret 不能为空且长度不能少于 32 个字符");
        }
        if (secret.equals(DEFAULT_SECRET)) {
            if (production) {
                throw new IllegalStateException(
                        "生产环境禁止使用兼容默认 JWT secret，请通过 OMNINEST_SECURITY_JWT_SECRET 注入独立密钥");
            }
            log.warn("JWT secret 正在使用兼容默认值，公开部署前必须通过环境变量替换");
        }
    }
}
