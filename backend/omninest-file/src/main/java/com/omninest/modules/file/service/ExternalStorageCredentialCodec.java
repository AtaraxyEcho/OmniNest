package com.omninest.modules.file.service;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * 外部存储凭据的安全展示与增量更新工具。
 *
 * @author OmniNest
 */
public final class ExternalStorageCredentialCodec {
    private static final Set<String> SENSITIVE_FIELDS = Set.of(
            "secret_access_key",
            "pass",
            "password",
            "token",
            "access_token",
            "refresh_token",
            "client_secret",
            "cookie"
    );

    private ExternalStorageCredentialCodec() {
    }

    /**
     * 提取允许返回客户端的连接元数据。
     *
     * @param provider 存储提供者
     * @param credentialsJson 完整凭据 JSON
     * @return 不包含密码、密钥和令牌的元数据
     */
    public static Map<String, String> extractEditableMetadata(
            String provider,
            String credentialsJson
    ) {
        JSONObject credentials = parseSafely(credentialsJson);
        if (credentials == null) {
            return Map.of();
        }
        List<String> editableFields = switch (provider.trim().toUpperCase(Locale.ROOT)) {
            case "S3", "MINIO" -> List.of("provider", "access_key_id", "endpoint", "region");
            case "WEBDAV" -> List.of("vendor", "url", "user");
            case "ONEDRIVE", "GDRIVE", "GOOGLE_DRIVE", "ALIYUN_DRIVE", "DROPBOX" ->
                    List.of("client_id");
            case "QUARK", "BAIDU" -> List.of();
            default -> List.of();
        };
        Map<String, String> metadata = new LinkedHashMap<>();
        for (String field : editableFields) {
            Object value = credentials.get(field);
            if (value != null) {
                metadata.put(field, value.toString());
            }
        }
        return Map.copyOf(metadata);
    }

    /**
     * 将客户端提交的变更合并到已有凭据中。
     * 空的敏感字段表示保留原值，非敏感字段允许显式清空。
     *
     * @param existingCredentialsJson 已保存的完整凭据
     * @param submittedCredentialsJson 客户端提交的凭据变更
     * @return 合并后的完整凭据 JSON
     */
    public static String mergeForUpdate(
            String existingCredentialsJson,
            String submittedCredentialsJson
    ) {
        JSONObject existing = parseRequired(existingCredentialsJson);
        JSONObject submitted = parseRequired(submittedCredentialsJson);
        Map<String, Object> original = new LinkedHashMap<>(existing);
        for (Map.Entry<String, Object> entry : submitted.entrySet()) {
            String field = entry.getKey();
            Object value = entry.getValue();
            if (SENSITIVE_FIELDS.contains(field.toLowerCase(Locale.ROOT))
                    && (value == null || value.toString().isBlank())) {
                continue;
            }
            existing.put(field, value);
        }
        if (original.equals(existing)) {
            return existingCredentialsJson;
        }
        return JSON.toJSONString(existing);
    }

    private static JSONObject parseSafely(String credentialsJson) {
        if (credentialsJson == null || credentialsJson.isBlank()) {
            return null;
        }
        try {
            return JSON.parseObject(credentialsJson);
        } catch (RuntimeException exception) {
            return null;
        }
    }

    private static JSONObject parseRequired(String credentialsJson) {
        JSONObject credentials = parseSafely(credentialsJson);
        if (credentials == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "外部存储凭据格式无效");
        }
        return credentials;
    }
}
