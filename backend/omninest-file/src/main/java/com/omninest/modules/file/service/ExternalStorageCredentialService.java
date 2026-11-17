package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CredentialCipher;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 外部存储凭据加解密。存量明文 JSON 在读取时兼容，写入时统一 AES-GCM。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class ExternalStorageCredentialService {

    private final CredentialCipher credentialCipher;

    /**
     * 加密明文凭据 JSON。
     *
     * @param plaintextJson 明文 JSON
     * @return AES-GCM 密文
     */
    public String encrypt(String plaintextJson) {
        if (plaintextJson == null || plaintextJson.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "外部存储凭据不能为空");
        }
        return credentialCipher.encrypt(plaintextJson);
    }

    /**
     * 解密为明文 JSON。兼容历史明文入库数据。
     *
     * @param stored 数据库中的凭据载荷
     * @return 明文 JSON
     */
    public String decryptToJson(String stored) {
        if (stored == null || stored.isBlank()) {
            return "{}";
        }
        String trimmed = stored.trim();
        if (trimmed.startsWith("{")) {
            return trimmed;
        }
        try {
            return credentialCipher.decrypt(stored);
        } catch (BusinessException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "外部存储凭据无法解密，请重新配置连接");
        }
    }

    /**
     * 判断存量载荷是否为未加密明文 JSON。
     *
     * @param stored 数据库中的凭据载荷
     * @return 是否为明文 JSON
     */
    public boolean isLegacyPlaintext(String stored) {
        return stored != null && stored.trim().startsWith("{");
    }
}
