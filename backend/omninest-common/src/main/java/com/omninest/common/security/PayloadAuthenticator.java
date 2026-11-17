package com.omninest.common.security;

/**
 * 提供文本负载签名和签名校验能力。
 *
 * @author OmniNest
 */
public interface PayloadAuthenticator {

    /**
     * 为文本负载生成签名。
     *
     * @param payload 文本负载
     * @return 签名文本
     */
    String sign(String payload);

    /**
     * 校验文本负载和签名是否匹配。
     *
     * @param payload 文本负载
     * @param signature 待校验签名
     * @return 匹配时返回 true
     */
    boolean verify(String payload, String signature);
}
