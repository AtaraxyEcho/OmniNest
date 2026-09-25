package com.omninest.modules.video.service;

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
 * 为无请求头能力的媒体元素签发用途受限的短期令牌。
 *
 * @author OmniNest
 */
@Service
public class MediaPlaybackTokenService {
    private static final Duration TOKEN_TTL = Duration.ofMinutes(30);
    private static final int TOKEN_BYTES = 32;
    private static final int MAXIMUM_TOKENS = 20000;

    private final SecureRandom secureRandom = new SecureRandom();
    private final Cache<String, MediaGrant> grants = Caffeine.newBuilder()
            .maximumSize(MAXIMUM_TOKENS)
            .expireAfterWrite(TOKEN_TTL)
            .build();
    private final Cache<GrantKey, IssuedMediaToken> issuedByResource = Caffeine.newBuilder()
            .maximumSize(MAXIMUM_TOKENS)
            .expireAfterWrite(TOKEN_TTL)
            .build();

    /** 签发指定用户和影片的短期媒体令牌。 */
    public IssuedMediaToken issue(UUID requesterUserId, UUID videoItemId) {
        return issue(requesterUserId, "VIDEO_ITEM", videoItemId);
    }

    /** 签发指定用户和系列的短期派生资源令牌。 */
    public IssuedMediaToken issueSeries(UUID requesterUserId, UUID seriesId) {
        return issue(requesterUserId, "TV_SERIES", seriesId);
    }

    private IssuedMediaToken issue(UUID requesterUserId, String resourceType, UUID resourceId) {
        GrantKey key = new GrantKey(requesterUserId, resourceType, resourceId);
        IssuedMediaToken existing = issuedByResource.getIfPresent(key);
        if (existing != null && isValid(grants.getIfPresent(existing.token()), resourceType, resourceId)) {
            return existing;
        }
        if (existing != null) {
            issuedByResource.invalidate(key);
        }
        byte[] random = new byte[TOKEN_BYTES];
        secureRandom.nextBytes(random);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(random);
        Instant expiresAt = Instant.now().plus(TOKEN_TTL);
        grants.put(token, new MediaGrant(requesterUserId, resourceType, resourceId, expiresAt));
        IssuedMediaToken issued = new IssuedMediaToken(token, expiresAt);
        issuedByResource.put(key, issued);
        return issued;
    }

    /** 校验令牌是否属于目标影片。 */
    public MediaGrant requireGrant(String token, UUID videoItemId) {
        if (token == null || token.isBlank()) {
            throw invalidToken();
        }
        MediaGrant grant = grants.getIfPresent(token);
        if (!isValid(grant, "VIDEO_ITEM", videoItemId)) {
            if (grant != null) {
                grants.invalidate(token);
            }
            throw invalidToken();
        }
        return grant;
    }

    /** 校验令牌是否属于目标系列。 */
    public MediaGrant requireSeriesGrant(String token, UUID seriesId) {
        if (token == null || token.isBlank()) {
            throw invalidToken();
        }
        MediaGrant grant = grants.getIfPresent(token);
        if (!isValid(grant, "TV_SERIES", seriesId)) {
            if (grant != null) {
                grants.invalidate(token);
            }
            throw invalidToken();
        }
        return grant;
    }

    private boolean isValid(MediaGrant grant, String resourceType, UUID resourceId) {
        return grant != null
                && !grant.expiresAt().isBefore(Instant.now())
                && resourceType.equals(grant.resourceType())
                && resourceId.equals(grant.resourceId());
    }

    private BusinessException invalidToken() {
        return new BusinessException(ErrorCode.FORBIDDEN, "媒体播放令牌无效或已过期");
    }

    public record IssuedMediaToken(String token, Instant expiresAt) {
    }

    public record MediaGrant(UUID requesterUserId, String resourceType, UUID resourceId, Instant expiresAt) {
    }

    private record GrantKey(UUID requesterUserId, String resourceType, UUID resourceId) {
    }
}
