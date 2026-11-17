package com.omninest.common.security;

/**
 * 定义业务模块使用的外部凭据加密能力。
 *
 * @author OmniNest
 */
public interface CredentialCipher {

    /**
     * 加密明文凭据。
     *
     * @param plaintext 明文凭据
     * @return 带版本信息的密文
     */
    String encrypt(String plaintext);

    /**
     * 解密外部凭据。
     *
     * @param payload 带版本信息的密文
     * @return 解密后的明文
     */
    String decrypt(String payload);

    /**
     * 获取当前凭据加密密钥版本。
     *
     * @return 密钥版本
     */
    int currentKeyVersion();
}
