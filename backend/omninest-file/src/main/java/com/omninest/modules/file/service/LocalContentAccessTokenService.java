package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.HkdfSha256;
import com.omninest.modules.file.domain.SpaceType;
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
 * <p>令牌同时绑定"谁、在哪个空间、以什么身份"取到这个地址：只签名文件与所有者
 * 时，分享被撤销、成员被降权或文件移入回收站后，已发地址在剩余有效期内仍能读。
 * 因此载荷携带 requesterUserId 与 spaceType，读取时逐次复核，而不是把 2 小时
 * 当作不可撤销的授权窗口。</p>
 *
 * @author OmniNest
 */
@Service
public class LocalContentAccessTokenService {
    private static final Duration TOKEN_TTL = Duration.ofHours(2);
    private static final String HMAC_ALGORITHM = "HmacSHA256";
    /** v2 起携带请求者与空间上下文；v1 令牌（仅文件+所有者）不再接受。 */
    private static final String TOKEN_VERSION = "v2";
    private static final int NONCE_BYTES = 16;
    private static final int FIELD_COUNT = 7;
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
     * @param requesterUserId 本次取到地址的请求者 ID
     * @param spaceType 文件所在空间
     * @return 访问授权
     */
    public IssuedAccess issue(
            UUID ownerUserId,
            UUID fileId,
            UUID requesterUserId,
            SpaceType spaceType
    ) {
        if (ownerUserId == null || fileId == null || requesterUserId == null || spaceType == null) {
            throw new IllegalArgumentException("本地内容令牌缺少必要的授权上下文");
        }
        byte[] random = new byte[NONCE_BYTES];
        secureRandom.nextBytes(random);
        Instant expiresAt = Instant.now().plus(TOKEN_TTL);
        String payload = String.join("|",
                TOKEN_VERSION,
                ownerUserId.toString(),
                fileId.toString(),
                requesterUserId.toString(),
                spaceType.name(),
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
        if (fields.length != FIELD_COUNT || !TOKEN_VERSION.equals(fields[0])) {
            throw invalidToken();
        }
        try {
            UUID ownerUserId = UUID.fromString(fields[1]);
            UUID fileId = UUID.fromString(fields[2]);
            UUID requesterUserId = UUID.fromString(fields[3]);
            SpaceType spaceType = SpaceType.valueOf(fields[4]);
            Instant expiresAt = Instant.ofEpochSecond(Long.parseLong(fields[5]));
            if (fields[6].isBlank() || !expiresAt.isAfter(Instant.now())) {
                throw invalidToken();
            }
            return new AccessGrant(ownerUserId, fileId, requesterUserId, spaceType, expiresAt);
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
     * @param requesterUserId 取到地址的请求者 ID
     * @param spaceType 签发时的文件空间
     * @param expiresAt 过期时间
     */
    public record AccessGrant(
            UUID ownerUserId,
            UUID fileId,
            UUID requesterUserId,
            SpaceType spaceType,
            Instant expiresAt
    ) {
    }
}
