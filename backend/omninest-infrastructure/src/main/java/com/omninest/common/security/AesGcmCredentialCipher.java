package com.omninest.common.security;

import com.omninest.common.config.SecurityProperties;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 使用 AES-GCM 加密和解密外部集成凭据。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class AesGcmCredentialCipher implements CredentialCipher {
    private static final String ALGORITHM = "AES/GCM/NoPadding";
    private static final String KEY_ALGORITHM = "AES";
    private static final int IV_LENGTH_BYTES = 12;
    private static final int TAG_LENGTH_BITS = 128;
    private static final int KEY_LENGTH_BYTES = 32;
    private static final String PAYLOAD_PREFIX = "v";

    private final SecurityProperties securityProperties;
    private final SecureRandom secureRandom = new SecureRandom();

    /**
     * 加密明文凭据。
     *
     * @param plaintext 明文
     * @return 带密钥版本和随机向量的密文
     * @throws BusinessException 密钥未配置或加密失败时抛出
     */
    @Override
    public String encrypt(String plaintext) {
        if (plaintext == null || plaintext.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "待加密凭据不能为空");
        }
        byte[] iv = new byte[IV_LENGTH_BYTES];
        secureRandom.nextBytes(iv);
        try {
            Cipher cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(
                    Cipher.ENCRYPT_MODE,
                    encryptionKey(securityProperties.getCredentialEncryptionKeyVersion()),
                    new GCMParameterSpec(TAG_LENGTH_BITS, iv)
            );
            byte[] encrypted = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
            return PAYLOAD_PREFIX + securityProperties.getCredentialEncryptionKeyVersion()
                    + ":" + Base64.getEncoder().encodeToString(iv)
                    + ":" + Base64.getEncoder().encodeToString(encrypted);
        } catch (GeneralSecurityException exception) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "外部凭据加密失败");
        }
    }

    /**
     * 解密外部集成凭据。
     *
     * @param payload 带版本信息的密文
     * @return 解密后的明文
     * @throws BusinessException 密文格式、密钥版本或认证标签无效时抛出
     */
    @Override
    public String decrypt(String payload) {
        String[] parts = payload == null ? new String[0] : payload.split(":", 3);
        if (parts.length != 3 || !parts[0].startsWith(PAYLOAD_PREFIX)) {
            throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "外部凭据密文格式无效");
        }
        int keyVersion = parseKeyVersion(parts[0]);
        try {
            byte[] iv = Base64.getDecoder().decode(parts[1]);
            byte[] encrypted = Base64.getDecoder().decode(parts[2]);
            if (iv.length != IV_LENGTH_BYTES) {
                throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "外部凭据随机向量长度无效");
            }
            Cipher cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(
                    Cipher.DECRYPT_MODE,
                    encryptionKey(keyVersion),
                    new GCMParameterSpec(TAG_LENGTH_BITS, iv)
            );
            return new String(cipher.doFinal(encrypted), StandardCharsets.UTF_8);
        } catch (BusinessException exception) {
            throw exception;
        } catch (IllegalArgumentException | GeneralSecurityException exception) {
            throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "外部凭据解密失败");
        }
    }

    /**
     * 解析指定版本密钥：当前版本取主密钥，历史版本取 previousKeys。
     */
    private SecretKeySpec encryptionKey(int keyVersion) {
        int currentVersion = securityProperties.getCredentialEncryptionKeyVersion();
        String configured = keyVersion == currentVersion
                ? securityProperties.getCredentialEncryptionKey()
                : securityProperties.getCredentialEncryptionPreviousKeys().get(keyVersion);
        if (configured == null || configured.isBlank()) {
            throw new BusinessException(
                    ErrorCode.CONFIG_VALUE_INVALID,
                    keyVersion == currentVersion ? "外部凭据加密密钥未配置" : "外部凭据密钥版本不受支持"
            );
        }
        try {
            byte[] decoded = Base64.getDecoder().decode(configured.trim());
            if (decoded.length != KEY_LENGTH_BYTES) {
                throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "外部凭据加密密钥必须为 32 字节");
            }
            return new SecretKeySpec(decoded, KEY_ALGORITHM);
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "外部凭据加密密钥必须使用 Base64 编码");
        }
    }

    /**
     * 获取当前凭据加密密钥版本。
     *
     * @return 密钥版本
     */
    @Override
    public int currentKeyVersion() {
        return securityProperties.getCredentialEncryptionKeyVersion();
    }

    private int parseKeyVersion(String version) {
        try {
            return Integer.parseInt(version.substring(PAYLOAD_PREFIX.length()));
        } catch (NumberFormatException exception) {
            throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "外部凭据密钥版本无效");
        }
    }
}
