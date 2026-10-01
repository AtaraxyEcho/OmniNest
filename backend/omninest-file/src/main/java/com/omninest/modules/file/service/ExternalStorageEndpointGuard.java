package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.modules.file.config.ExternalStorageEndpointPolicyProperties;
import java.net.URI;
import java.util.Locale;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * 外部存储端点出网安全守卫。
 *
 * <p>WEBDAV url 与 S3/MINIO endpoint 由用户提交、由 rclone 容器实际发起请求且响应会回显，
 * 属于全项目最敏感的 SSRF 入口；该守卫在创建、更新与每次使用时校验协议、端口与目标地址。
 *
 * @author OmniNest
 */
@Component
public class ExternalStorageEndpointGuard {

    private static final String PRIVATE_HINT = "外部存储地址被安全策略拒绝：默认仅允许公网地址，"
            + "连接内网 NAS 需管理员开启 omninest.external-storage.endpoint.allow-private-network";

    private final SafeUrlValidator safeUrlValidator;
    private final ExternalStorageEndpointPolicyProperties policyProperties;

    public ExternalStorageEndpointGuard(
            SafeUrlValidator safeUrlValidator,
            ExternalStorageEndpointPolicyProperties policyProperties
    ) {
        this.safeUrlValidator = safeUrlValidator;
        this.policyProperties = policyProperties;
    }

    /**
     * 校验凭据中的端点地址；OAuth 类连接器与未填写端点的凭据直接放行。
     *
     * @param provider 存储提供者编码
     * @param credentials 解密后的凭据键值
     */
    public void validate(String provider, Map<String, ?> credentials) {
        if (credentials == null || credentials.isEmpty()) {
            return;
        }
        String normalizedProvider = provider == null ? "" : provider.trim().toUpperCase(Locale.ROOT);
        String endpoint;
        switch (normalizedProvider) {
            case "WEBDAV" -> endpoint = asText(credentials.get("url"));
            case "S3", "MINIO" -> endpoint = asText(credentials.get("endpoint"));
            default -> {
                return;
            }
        }
        if (endpoint == null || endpoint.isBlank()) {
            return;
        }
        URI uri;
        try {
            uri = URI.create(endpoint.trim());
        } catch (IllegalArgumentException exception) {
            throw rejection("外部存储地址格式无效");
        }
        String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
        if (!"http".equals(scheme) && !"https".equals(scheme)) {
            throw rejection("外部存储地址仅支持 HTTP/HTTPS 协议");
        }
        if (uri.getUserInfo() != null && !uri.getUserInfo().isBlank()) {
            throw rejection("外部存储地址不允许携带用户信息");
        }
        if (uri.getPort() != -1 && !policyProperties.getAllowedPorts().contains(uri.getPort())) {
            throw rejection("外部存储地址端口不在允许清单（默认 80/443），"
                    + "可经 omninest.external-storage.endpoint.allowed-ports 扩展");
        }
        try {
            safeUrlValidator.requireSafeHost(uri, policyProperties.isAllowPrivateNetwork());
        } catch (BusinessException exception) {
            throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, PRIVATE_HINT);
        }
    }

    private BusinessException rejection(String message) {
        return new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, message);
    }

    private String asText(Object value) {
        return value == null ? null : value.toString();
    }
}
