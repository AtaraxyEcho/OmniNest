package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.HkdfSha256;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.UUID;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * 为无请求头能力的媒体元素签发用途受限的短期令牌。
 *
 * <p>令牌使用 HMAC-SHA256 自包含签名，不保存进程内状态：多实例部署、重启或滚动
 * 升级后仍可校验。签名密钥由 JWT secret 经 HKDF 派生独立子密钥。</p>
 *
 * @author OmniNest
 */
@Service
public class MediaPlaybackTokenService {
    private static final Duration TOKEN_TTL = Duration.ofMinutes(30);
    private static final String HMAC_ALGORITHM = "HmacSHA256";
    private static final String TOKEN_VERSION = "v1";
    private static final String KEY_INFO = "omninest-media-playback-v1";
    private static final int KEY_LENGTH_BYTES = 32;
    private static final int TOKEN_BYTES = 16;
    private static final SecureRandom SECURE_RANDOM = new SecureRandom();
    private static final Base64.Encoder BASE64_ENCODER = Base64.getUrlEncoder().withoutPadding();
    private static final Base64.Decoder BASE64_DECODER = Base64.getUrlDecoder();

    private final SecretKeySpec signingKey;

    public MediaPlaybackTokenService(@Value("${omninest.security.jwt-secret}") String secret) {
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException("媒体播放令牌签名密钥不能为空");
        }
        byte[] derivedKey = HkdfSha256.deriveKey(
                secret.getBytes(StandardCharsets.UTF_8),
                HkdfSha256.defaultSalt(),
                KEY_INFO,
                KEY_LENGTH_BYTES
        );
        this.signingKey = new SecretKeySpec(derivedKey, HMAC_ALGORITHM);
    }

    /** 签发指定用户和影片的短期媒体令牌。 */
    public IssuedMediaToken issue(UUID requesterUserId, UUID videoItemId) {
        return issue(requesterUserId, "VIDEO_ITEM", videoItemId);
    }

    /** 签发指定用户和系列的短期派生资源令牌。 */
    public IssuedMediaToken issueSeries(UUID requesterUserId, UUID seriesId) {
        return issue(requesterUserId, "TV_SERIES", seriesId);
    }

    private IssuedMediaToken issue(UUID requesterUserId, String resourceType, UUID resourceId) {
        Instant expiresAt = Instant.now().plus(TOKEN_TTL);
        byte[] nonce = new byte[TOKEN_BYTES];
        SECURE_RANDOM.nextBytes(nonce);
        String payload = String.join("|",
                TOKEN_VERSION,
                requesterUserId.toString(),
                resourceType,
                resourceId.toString(),
                Long.toString(expiresAt.getEpochSecond()),
                BASE64_ENCODER.encodeToString(nonce));
        String payloadPart = BASE64_ENCODER.encodeToString(payload.getBytes(StandardCharsets.UTF_8));
        String token = payloadPart + "." + BASE64_ENCODER.encodeToString(sign(payloadPart));
        return new IssuedMediaToken(token, expiresAt);
    }

    /** 校验令牌是否属于目标影片。 */
    public MediaGrant requireGrant(String token, UUID videoItemId) {
        MediaGrant grant = validateGrant(token, "VIDEO_ITEM", videoItemId);
        if (grant == null) {
            throw invalidToken();
        }
        return grant;
    }

    /** 校验令牌是否属于目标系列。 */
    public MediaGrant requireSeriesGrant(String token, UUID seriesId) {
        MediaGrant grant = validateGrant(token, "TV_SERIES", seriesId);
        if (grant == null) {
            throw invalidToken();
        }
        return grant;
    }

    private MediaGrant validateGrant(String token, String resourceType, UUID resourceId) {
        if (token == null || token.isBlank()) {
            return null;
        }
        int separator = token.indexOf('.');
        if (separator <= 0 || separator == token.length() - 1) {
            return null;
        }
        String payloadPart = token.substring(0, separator);
        byte[] providedSignature;
        try {
            providedSignature = BASE64_DECODER.decode(token.substring(separator + 1));
        } catch (IllegalArgumentException exception) {
            return null;
        }
        if (!MessageDigest.isEqual(sign(payloadPart), providedSignature)) {
            return null;
        }
        String payload;
        try {
            payload = new String(BASE64_DECODER.decode(payloadPart), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException exception) {
            return null;
        }
        String[] parts = payload.split("\\|", 6);
        if (parts.length != 6 || !TOKEN_VERSION.equals(parts[0])) {
            return null;
        }
        UUID requesterUserId;
        UUID tokenResourceId;
        long expiresAtEpochSecond;
        try {
            requesterUserId = UUID.fromString(parts[1]);
            tokenResourceId = UUID.fromString(parts[3]);
            expiresAtEpochSecond = Long.parseLong(parts[4]);
        } catch (IllegalArgumentException exception) {
            return null;
        }
        if (!resourceType.equals(parts[2]) || !resourceId.equals(tokenResourceId)) {
            return null;
        }
        Instant expiresAt = Instant.ofEpochSecond(expiresAtEpochSecond);
        if (expiresAt.isBefore(Instant.now())) {
            return null;
        }
        return new MediaGrant(requesterUserId, resourceType, tokenResourceId, expiresAt);
    }

    private byte[] sign(String payload) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(signingKey);
            return mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
        } catch (Exception exception) {
            throw new IllegalStateException("媒体播放令牌签名失败", exception);
        }
    }

    private BusinessException invalidToken() {
        return new BusinessException(ErrorCode.FORBIDDEN, "媒体播放令牌无效或已过期");
    }

    public record IssuedMediaToken(String token, Instant expiresAt) {
    }

    public record MediaGrant(UUID requesterUserId, String resourceType, UUID resourceId, Instant expiresAt) {
    }
}
