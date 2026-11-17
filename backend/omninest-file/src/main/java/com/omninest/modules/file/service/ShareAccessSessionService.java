package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.HkdfSha256;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * 已完成分享密码校验的短期、用途受限会话。
 *
 * <p>会话使用 HMAC-SHA256 自包含签名，不保存进程内状态：多实例部署、重启或滚动
 * 升级后仍可校验。载荷绑定分享令牌摘要、资源类型与过期时间，签名密钥由 JWT secret
 * 经 HKDF 派生独立子密钥，避免与身份令牌共用密钥域。</p>
 *
 * @author OmniNest
 */
@Service
public class ShareAccessSessionService {

    private static final Duration MAX_TTL = Duration.ofMinutes(10);
    private static final String HMAC_ALGORITHM = "HmacSHA256";
    private static final String TOKEN_VERSION = "v1";
    private static final String KEY_INFO = "omninest-share-session-v1";
    private static final int KEY_LENGTH_BYTES = 32;
    private static final Base64.Encoder BASE64_ENCODER = Base64.getUrlEncoder().withoutPadding();
    private static final Base64.Decoder BASE64_DECODER = Base64.getUrlDecoder();

    private final SecretKeySpec signingKey;

    public ShareAccessSessionService(@Value("${omninest.security.jwt-secret}") String secret) {
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException("分享会话签名密钥不能为空");
        }
        byte[] derivedKey = HkdfSha256.deriveKey(
                secret.getBytes(StandardCharsets.UTF_8),
                HkdfSha256.defaultSalt(),
                KEY_INFO,
                KEY_LENGTH_BYTES
        );
        this.signingKey = new SecretKeySpec(derivedKey, HMAC_ALGORITHM);
    }

    /**
     * 签发绑定分享令牌和资源类型的短期会话。
     */
    public IssuedSession issue(String tokenHash, String resourceType, Instant linkExpiresAt) {
        Instant now = Instant.now();
        if (linkExpiresAt != null && !linkExpiresAt.isAfter(now)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "分享链接已过期");
        }
        Instant expiresAt = now.plus(MAX_TTL);
        if (linkExpiresAt != null && linkExpiresAt.isBefore(expiresAt)) {
            expiresAt = linkExpiresAt;
        }
        String payload = String.join("|",
                TOKEN_VERSION,
                tokenHash,
                resourceType,
                Long.toString(expiresAt.getEpochSecond()));
        String payloadPart = BASE64_ENCODER.encodeToString(payload.getBytes(StandardCharsets.UTF_8));
        String token = payloadPart + "." + BASE64_ENCODER.encodeToString(sign(payloadPart));
        return new IssuedSession(token, expiresAt);
    }

    /**
     * 校验会话签名、有效期及其与分享令牌、资源类型的绑定关系。
     */
    public void require(String sessionToken, String tokenHash, String resourceType) {
        if (!matches(sessionToken, tokenHash, resourceType)) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "分享会话无效或已过期");
        }
    }

    /**
     * 无状态校验，供需要布尔结果的调用方使用。
     */
    public boolean matches(String sessionToken, String tokenHash, String resourceType) {
        if (sessionToken == null || sessionToken.isBlank()) {
            return false;
        }
        int separator = sessionToken.indexOf('.');
        if (separator <= 0 || separator == sessionToken.length() - 1) {
            return false;
        }
        String payloadPart = sessionToken.substring(0, separator);
        byte[] providedSignature;
        try {
            providedSignature = BASE64_DECODER.decode(sessionToken.substring(separator + 1));
        } catch (IllegalArgumentException exception) {
            return false;
        }
        byte[] expectedSignature = sign(payloadPart);
        if (!MessageDigest.isEqual(expectedSignature, providedSignature)) {
            return false;
        }
        String payload;
        try {
            payload = new String(BASE64_DECODER.decode(payloadPart), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException exception) {
            return false;
        }
        String[] parts = payload.split("\\|", 4);
        if (parts.length != 4 || !TOKEN_VERSION.equals(parts[0])) {
            return false;
        }
        long expiresAt;
        try {
            expiresAt = Long.parseLong(parts[3]);
        } catch (NumberFormatException exception) {
            return false;
        }
        return expiresAt > Instant.now().getEpochSecond()
                && parts[1].equals(tokenHash)
                && parts[2].equals(resourceType);
    }

    private byte[] sign(String payloadPart) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(signingKey);
            return mac.doFinal(payloadPart.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException exception) {
            throw new IllegalStateException("分享会话签名失败", exception);
        }
    }

    public record IssuedSession(String token, Instant expiresAt) {
    }
}
