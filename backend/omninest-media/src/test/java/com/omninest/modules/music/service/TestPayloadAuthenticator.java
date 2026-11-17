package com.omninest.modules.music.service;

import com.omninest.common.security.PayloadAuthenticator;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

/**
 * 音乐播放令牌测试使用的确定性负载签名器。
 *
 * @author OmniNest
 */
final class TestPayloadAuthenticator implements PayloadAuthenticator {

    /**
     * 生成确定性的测试签名。
     *
     * @param payload 文本负载
     * @return 测试签名
     */
    @Override
    public String sign(String payload) {
        return Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString(payload.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * 校验测试签名。
     *
     * @param payload 文本负载
     * @param signature 待校验签名
     * @return 匹配时返回 true
     */
    @Override
    public boolean verify(String payload, String signature) {
        return sign(payload).equals(signature);
    }
}
