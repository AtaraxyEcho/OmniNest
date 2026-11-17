package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.json.JsonSupport;
import com.omninest.common.security.CredentialCipher;
import com.omninest.modules.file.domain.StorageConnectorOAuthApp;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Locale;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import tools.jackson.core.type.TypeReference;

/**
 * 外部存储 OAuth token 端点客户端。
 *
 * <p>拆成独立组件是为了让回调与刷新链路可以在单元测试中替换为桩，
 * 不把真实网络请求带进授权落库、同步事件与错误映射的验证。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ExternalStorageOAuthTokenClient {

    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    private final CredentialCipher credentialCipher;

    /**
     * 用授权码换取 token。
     *
     * @param provider 连接器编码
     * @param app 实例级 OAuth 应用
     * @param authorizationCode 授权码
     * @return 提供方 token 响应
     */
    public Map<String, Object> exchangeCode(
            String provider, StorageConnectorOAuthApp app, String authorizationCode) {
        return postToken(provider, Map.of(
                "grant_type", "authorization_code",
                "code", authorizationCode,
                "redirect_uri", app.getRedirectUri(),
                "client_id", app.getClientId(),
                "client_secret", credentialCipher.decrypt(app.getClientSecretEncrypted())
        ));
    }

    /**
     * 用 refresh token 换取新 token。
     *
     * @param provider 连接器编码
     * @param app 实例级 OAuth 应用
     * @param refreshToken 刷新令牌
     * @return 提供方 token 响应
     */
    public Map<String, Object> refreshTokens(
            String provider, StorageConnectorOAuthApp app, String refreshToken) {
        return postToken(provider, Map.of(
                "grant_type", "refresh_token",
                "refresh_token", refreshToken,
                "client_id", app.getClientId(),
                "client_secret", credentialCipher.decrypt(app.getClientSecretEncrypted())
        ));
    }

    private Map<String, Object> postToken(String provider, Map<String, String> form) {
        String endpoint = tokenEndpoint(provider);
        String body = form.entrySet().stream()
                .map(e -> URLEncoder.encode(e.getKey(), StandardCharsets.UTF_8)
                        + "=" + URLEncoder.encode(e.getValue(), StandardCharsets.UTF_8))
                .reduce((a, b) -> a + "&" + b)
                .orElse("");
        try {
            HttpRequest request = HttpRequest.newBuilder(URI.create(endpoint))
                    .timeout(Duration.ofSeconds(20))
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8))
                    .build();
            HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() >= 400) {
                log.warn("OAuth token 交换失败: provider={}, status={}", provider, response.statusCode());
                throw new BusinessException(ErrorCode.PARAM_ERROR, "OAuth 授权失败，请重试或检查应用配置");
            }
            return JsonSupport.fromJson(response.body(), new TypeReference<Map<String, Object>>() {});
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "OAuth 请求被中断");
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "无法访问 OAuth 服务");
        }
    }

    private String tokenEndpoint(String provider) {
        String code = provider.trim().toUpperCase(Locale.ROOT);
        return switch (code) {
            case "ONEDRIVE" -> "https://login.microsoftonline.com/common/oauth2/v2.0/token";
            case "GDRIVE", "GOOGLE_DRIVE" -> "https://oauth2.googleapis.com/token";
            case "DROPBOX" -> "https://api.dropboxapi.com/oauth2/token";
            default -> throw new BusinessException(ErrorCode.PARAM_ERROR, "该连接器暂不支持 OAuth");
        };
    }
}
