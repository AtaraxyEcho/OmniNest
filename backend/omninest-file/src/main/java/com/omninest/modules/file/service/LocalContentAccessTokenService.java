package com.omninest.modules.file.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.UUID;
import org.springframework.stereotype.Service;

/**
 * 本地内容短期访问令牌服务。
 *
 * @author OmniNest
 */
@Service
public class LocalContentAccessTokenService {
    /**
     * 本地内容令牌有效期。与 MinIO 预签名一致取 2 小时；令牌为进程内
     * Caffeine 缓存，后端重启后旧令牌失效由前端重签闭环兜底。
     */
    private static final Duration TOKEN_TTL = Duration.ofHours(2);
    private static final int TOKEN_BYTES = 32;
    private static final long MAXIMUM_TOKENS = 20000;

    private final SecureRandom secureRandom = new SecureRandom();
    private final Cache<String, AccessGrant> grants = Caffeine.newBuilder()
            .maximumSize(MAXIMUM_TOKENS)
            .expireAfterWrite(TOKEN_TTL)
            .build();

    /**
     * 为单个文件签发短期访问令牌。
     *
     * @param ownerUserId 文件所有者 ID
     * @param fileId 文件节点 ID
     * @return 访问授权
     */
    public IssuedAccess issue(UUID ownerUserId, UUID fileId) {
        byte[] random = new byte[TOKEN_BYTES];
        secureRandom.nextBytes(random);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(random);
        Instant expiresAt = Instant.now().plus(TOKEN_TTL);
        grants.put(token, new AccessGrant(ownerUserId, fileId, expiresAt));
        return new IssuedAccess(token, expiresAt);
    }

    /**
     * 校验短期令牌并返回其最小授权范围。
     *
     * @param token 访问令牌
     * @return 访问授权
     */
    public AccessGrant requireGrant(String token) {
        if (token == null || token.isBlank()) {
            throw invalidToken();
        }
        AccessGrant grant = grants.getIfPresent(token);
        if (grant == null || grant.expiresAt().isBefore(Instant.now())) {
            if (grant != null) {
                grants.invalidate(token);
            }
            throw invalidToken();
        }
        return grant;
    }

    private BusinessException invalidToken() {
        return new BusinessException(ErrorCode.FORBIDDEN, "本地媒体访问令牌无效或已过期");
    }

    /**
     * 已签发令牌。
     *
     * @param token 令牌值
     * @param expiresAt 过期时间
     */
    public record IssuedAccess(String token, Instant expiresAt) {
    }

    /**
     * 令牌对应的最小访问授权。
     *
     * @param ownerUserId 文件所有者 ID
     * @param fileId 文件节点 ID
     * @param expiresAt 过期时间
     */
    public record AccessGrant(UUID ownerUserId, UUID fileId, Instant expiresAt) {
    }
}
