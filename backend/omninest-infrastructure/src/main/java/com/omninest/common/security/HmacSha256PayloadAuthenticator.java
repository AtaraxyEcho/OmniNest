package com.omninest.common.security;

import com.omninest.common.config.SecurityProperties;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.Base64;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 使用安全配置密钥提供 HMAC-SHA256 文本负载签名。
 *
 * <p>签名密钥经 HKDF-SHA256 从 JWT secret 派生（盐与用途标签固定），
 * 与 JWT 本体的签名域隔离：任一用途的密料推导都不影响另一用途，
 * 播放令牌等短时凭证也无法被拿去伪造 JWT 结构。派生确定性保证跨重启一致。
 * 切换到派生密钥会使升级前签发的在途短时令牌一次性失效（TTL ≤ 30 分钟）。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class HmacSha256PayloadAuthenticator implements PayloadAuthenticator {
    private static final String HMAC_ALGORITHM = "HmacSHA256";
    private static final String KEY_INFO = "omninest-payload-hmac-v1";
    private static final int DERIVED_KEY_LENGTH = 32;

    private final SecurityProperties securityProperties;

    @Override
    public String sign(String payload) {
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(new SecretKeySpec(derivedKey(), HMAC_ALGORITHM));
            byte[] digest = mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(digest);
        } catch (GeneralSecurityException exception) {
            throw new IllegalStateException("负载签名失败", exception);
        }
    }

    @Override
    public boolean verify(String payload, String signature) {
        if (payload == null || signature == null) {
            return false;
        }
        byte[] expected = sign(payload).getBytes(StandardCharsets.UTF_8);
        byte[] actual = signature.getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(expected, actual);
    }

    private byte[] derivedKey() {
        return HkdfSha256.deriveKey(
                securityProperties.getJwtSecret().getBytes(StandardCharsets.UTF_8),
                HkdfSha256.defaultSalt(),
                KEY_INFO,
                DERIVED_KEY_LENGTH
        );
    }

}
