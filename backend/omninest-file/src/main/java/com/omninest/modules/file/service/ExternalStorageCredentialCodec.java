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
            "client_secret"
    );

    /**
     * 各提供者允许入库的凭据键白名单（比较时大小写不敏感）。
     * 未列出的键在创建与更新时一并丢弃，阻断任意键透传 rclone config/create。
     */
    private static final Map<String, Set<String>> ALLOWED_FIELDS = Map.of(
            "S3", Set.of("provider", "access_key_id", "secret_access_key", "endpoint", "region"),
            "MINIO", Set.of("provider", "access_key_id", "secret_access_key", "endpoint", "region"),
            "WEBDAV", Set.of("vendor", "url", "user", "pass", "password", "token", "bearer_token"),
            "ONEDRIVE", oauthFields(),
            "GDRIVE", oauthFields(),
            "GOOGLE_DRIVE", oauthFields(),
            "ALIYUN_DRIVE", oauthFields(),
            "DROPBOX", oauthFields()
    );

    private static Set<String> oauthFields() {
        return Set.of("client_id", "client_secret", "access_token", "token_type", "refresh_token", "expiry");
    }

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
     * 空的敏感字段表示保留原值，非敏感字段允许显式清空；白名单之外的键直接丢弃。
     *
     * @param provider 存储提供者
     * @param existingCredentialsJson 已保存的完整凭据
     * @param submittedCredentialsJson 客户端提交的凭据变更
     * @return 合并后的完整凭据 JSON
     */
    public static String mergeForUpdate(
            String provider,
            String existingCredentialsJson,
            String submittedCredentialsJson
    ) {
        JSONObject existing = parseRequired(existingCredentialsJson);
        JSONObject submitted = parseRequired(submittedCredentialsJson);
        Set<String> allowed = allowedFields(provider);
        Map<String, Object> original = new LinkedHashMap<>(existing);
        for (Map.Entry<String, Object> entry : submitted.entrySet()) {
            String field = entry.getKey();
            Object value = entry.getValue();
            if (!isAllowedField(allowed, field)) {
                continue;
            }
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

    /**
     * 过滤创建请求中的凭据 JSON，仅保留该提供者白名单内的键。
     *
     * @param provider 存储提供者
     * @param credentialsJson 客户端提交的凭据 JSON
     * @return 过滤后的凭据 JSON；无可识别键时返回空对象 JSON
     */
    public static String sanitize(String provider, String credentialsJson) {
        JSONObject credentials = parseRequired(credentialsJson);
        Set<String> allowed = allowedFields(provider);
        JSONObject filtered = new JSONObject();
        for (Map.Entry<String, Object> entry : credentials.entrySet()) {
            if (isAllowedField(allowed, entry.getKey())) {
                filtered.put(entry.getKey(), entry.getValue());
            }
        }
        return filtered.isEmpty() ? "{}" : JSON.toJSONString(filtered);
    }

    private static boolean isAllowedField(Set<String> allowed, String field) {
        return field != null && allowed.contains(field.toLowerCase(Locale.ROOT));
    }

    private static Set<String> allowedFields(String provider) {
        String normalized = provider == null ? "" : provider.trim().toUpperCase(Locale.ROOT);
        return ALLOWED_FIELDS.getOrDefault(normalized, Set.of());
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
