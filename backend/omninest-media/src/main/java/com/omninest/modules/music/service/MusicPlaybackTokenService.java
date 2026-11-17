package com.omninest.modules.music.service;

import com.omninest.common.security.PayloadAuthenticator;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 音乐播放短期令牌服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MusicPlaybackTokenService {
    private static final String TOKEN_SEPARATOR = ".";
    private static final int TOKEN_PART_COUNT = 3;

    private final PayloadAuthenticator payloadAuthenticator;

    /**
     * 签发绑定播放会话和过期时间的令牌。
     *
     * @param sessionId 会话标识
     * @param expiresAt 过期时间
     * @return 播放令牌
     */
    public String sign(String sessionId, Instant expiresAt) {
        String payload = sessionId + TOKEN_SEPARATOR + expiresAt.getEpochSecond();
        return payload + TOKEN_SEPARATOR + signature(payload);
    }

    /**
     * 校验播放令牌。
     *
     * @param token 令牌
     * @param sessionId 会话标识
     * @param expectedExpiresAt 期望过期时间
     * @param now 当前时间
     * @return 校验通过时返回 true
     */
    public boolean verify(String token, String sessionId, Instant expectedExpiresAt, Instant now) {
        if (token == null || token.isBlank() || sessionId == null || expectedExpiresAt == null) {
            return false;
        }
        String[] parts = token.split("\\.", TOKEN_PART_COUNT);
        if (parts.length != TOKEN_PART_COUNT) {
            return false;
        }
        if (!sessionId.equals(parts[0])) {
            return false;
        }
        String expectedEpoch = String.valueOf(expectedExpiresAt.getEpochSecond());
        if (!expectedEpoch.equals(parts[1])) {
            return false;
        }
        if (now.isAfter(expectedExpiresAt)) {
            return false;
        }
        String payload = parts[0] + TOKEN_SEPARATOR + parts[1];
        return payloadAuthenticator.verify(payload, parts[2]);
    }

    private String signature(String payload) {
        return payloadAuthenticator.sign(payload);
    }
}
