package com.omninest.modules.file.service;

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
 * 本地内容短期访问令牌服务。
 *
 * <p>令牌采用 HMAC-SHA256 自包含签名，不保存服务端状态：多 API 实例、重启与水平
 * 扩展后都能继续校验，避免进程内缓存导致跨节点 403。有效期与 MinIO 预签名一致取
 * 2 小时，覆盖长视频播放中的后续 Range 请求。</p>
 *
 * @author OmniNest
 */
@Service
public class LocalContentAccessTokenService {
    private static final Duration TOKEN_TTL = Duration.ofHours(2);
    private static final String HMAC_ALGORITHM = "HmacSHA256";
    private static final String TOKEN_VERSION = "v1";
    private static final int NONCE_BYTES = 16;
    private static final Base64.Encoder BASE64_ENCODER = Base64.getUrlEncoder().withoutPadding();
    private static final Base64.Decoder BASE64_DECODER = Base64.getUrlDecoder();

    private final SecretKeySpec signingKey;
    private final SecureRandom secureRandom = new SecureRandom();

    public LocalContentAccessTokenService(@Value("${omninest.security.jwt-secret}") String secret) {
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException("本地内容令牌签名密钥不能为空");
        }
        // 本地内容令牌必须使用独立子密钥：直接复用 JWT secret 会让两类 HMAC
        // 处于同一密钥域，任一用途的实现缺陷都可能波及身份令牌。
        this.signingKey = new SecretKeySpec(
                HkdfSha256.deriveKey(
                        secret.getBytes(StandardCharsets.UTF_8),
                        HkdfSha256.defaultSalt(),
                        "omninest-local-content-token-v1",
                        32
                ),
                HMAC_ALGORITHM
        );
    }

    /**
     * 为单个文件签发短期访问令牌。
     *
     * @param ownerUserId 文件所有者 ID
     * @param fileId 文件节点 ID
     * @return 访问授权
     */
    public IssuedAccess issue(UUID ownerUserId, UUID fileId) {
        byte[] random = new byte[NONCE_BYTES];
        secureRandom.nextBytes(random);
        Instant expiresAt = Instant.now().plus(TOKEN_TTL);
        String payload = String.join("|",
                TOKEN_VERSION,
                ownerUserId.toString(),
                fileId.toString(),
                Long.toString(expiresAt.getEpochSecond()),
                BASE64_ENCODER.encodeToString(random));
        String payloadPart = BASE64_ENCODER.encodeToString(payload.getBytes(StandardCharsets.UTF_8));
        String token = payloadPart + "." + BASE64_ENCODER.encodeToString(sign(payloadPart));
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
        int separator = token.indexOf('.');
        if (separator <= 0 || separator == token.length() - 1) {
            throw invalidToken();
        }
        String payloadPart = token.substring(0, separator);
        byte[] providedSignature;
        String payload;
        try {
            providedSignature = BASE64_DECODER.decode(token.substring(separator + 1));
            payload = new String(BASE64_DECODER.decode(payloadPart), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException exception) {
            throw invalidToken();
        }
        if (!MessageDigest.isEqual(providedSignature, sign(payloadPart))) {
            throw invalidToken();
        }
        String[] fields = payload.split("\\|", -1);
        if (fields.length != 5 || !TOKEN_VERSION.equals(fields[0])) {
            throw invalidToken();
        }
        try {
            UUID ownerUserId = UUID.fromString(fields[1]);
            UUID fileId = UUID.fromString(fields[2]);
            Instant expiresAt = Instant.ofEpochSecond(Long.parseLong(fields[3]));
            if (fields[4].isBlank() || !expiresAt.isAfter(Instant.now())) {
                throw invalidToken();
            }
            return new AccessGrant(ownerUserId, fileId, expiresAt);
        } catch (IllegalArgumentException exception) {
            throw invalidToken();
        }
    }

    private byte[] sign(String payloadPart) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(signingKey);
            return mac.doFinal(payloadPart.getBytes(StandardCharsets.US_ASCII));
        } catch (Exception exception) {
            throw new IllegalStateException("本地内容令牌签名失败", exception);
        }
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
