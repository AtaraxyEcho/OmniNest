package com.omninest.modules.file.service;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CredentialCipher;
import com.omninest.modules.file.domain.StorageConnectorOAuthApp;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.domain.ExternalStorageStatus;
import com.omninest.modules.file.dto.ConnectorOAuthAppDto;
import com.omninest.modules.file.dto.OAuthStartResponse;
import com.omninest.modules.file.dto.SaveConnectorOAuthAppRequest;
import com.omninest.modules.file.repository.StorageConnectorOAuthAppRepository;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 连接器 OAuth 授权与应用配置服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ExternalStorageOAuthService {

    private static final Duration STATE_TTL = Duration.ofMinutes(10);
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    private final com.github.benmanes.caffeine.cache.Cache<String, String> oauthStates =
            com.github.benmanes.caffeine.cache.Caffeine.newBuilder()
                    .expireAfterWrite(STATE_TTL)
                    .maximumSize(10_000)
                    .build();

    private final StorageConnectorOAuthAppRepository oauthAppRepository;
    private final StorageExternalAccountRepository accountRepository;
    private final ExternalStorageCredentialService credentialService;
    private final CredentialCipher credentialCipher;

    /**
     * token 校验或刷新结果。
     *
     * @param credentials 规范化后的完整凭据
     * @param refreshed 是否实际执行了 token 刷新
     */
    public record TokenRefreshResult(JSONObject credentials, boolean refreshed) {
    }

    /**
     * 实例级 OAuth 应用凭据。
     *
     * @param clientId 应用客户端 ID
     * @param clientSecret 应用客户端密钥
     */
    public record ConnectorAppCredentials(String clientId, String clientSecret) {
    }

    @Transactional(readOnly = true)
    public List<ConnectorOAuthAppDto> listApps() {
        return oauthAppRepository.findAll().stream()
                .map(this::toDto)
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public ConnectorOAuthAppDto saveApp(SaveConnectorOAuthAppRequest request) {
        String code = ExternalStorageProviders.requireAllowed(request.connectorCode());
        if (request.clientId() == null || request.clientId().isBlank()
                || request.redirectUri() == null || request.redirectUri().isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "Client ID 与回调地址不能为空");
        }
        StorageConnectorOAuthApp app = oauthAppRepository
                .findFirstByConnectorCodeAndEnabledTrue(code)
                .orElseGet(StorageConnectorOAuthApp::new);
        boolean secretMissing = request.clientSecret() == null || request.clientSecret().isBlank();
        if (secretMissing && app.getClientSecretEncrypted() == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "Client Secret 不能为空");
        }
        app.setConnectorCode(code);
        app.setClientId(request.clientId().trim());
        if (!secretMissing) {
            app.setClientSecretEncrypted(credentialCipher.encrypt(request.clientSecret().trim()));
        }
        app.setRedirectUri(request.redirectUri().trim());
        app.setEnabled(request.enabled());
        return toDto(oauthAppRepository.save(app));
    }

    /**
     * 开始 OAuth 授权。
     */
    @Transactional(readOnly = true)
    public OAuthStartResponse start(UUID ownerUserId, String connectorCode, UUID accountId) {
        String code = connectorCode.trim().toUpperCase(Locale.ROOT);
        StorageConnectorOAuthApp app = requireApp(code);
        StorageExternalAccount account = accountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储账户不存在"));
        if (!code.equals(account.getProvider().toUpperCase(Locale.ROOT))) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "连接器与账户类型不一致");
        }
        String state = UUID.randomUUID().toString().replace("-", "");
        String payload = JSON.toJSONString(Map.of(
                "state", state,
                "userId", ownerUserId.toString(),
                "accountId", accountId.toString(),
                "code", code
        ));
        oauthStates.put(state, payload);
        return new OAuthStartResponse(buildAuthorizationUrl(code, app), state);
    }

    /**
     * 处理 OAuth 回调并绑定 token。
     */
    @Transactional(rollbackFor = Exception.class)
    public void handleCallback(String state, String code) {
        if (state == null || state.isBlank() || code == null || code.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "OAuth 回调参数不完整");
        }
        String raw = oauthStates.getIfPresent(state);
        if (raw == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "OAuth state 无效或已过期");
        }
        oauthStates.invalidate(state);
        JSONObject payload = JSON.parseObject(raw);
        UUID userId = UUID.fromString(payload.getString("userId"));
        UUID accountId = UUID.fromString(payload.getString("accountId"));
        String connectorCode = payload.getString("code");
        StorageConnectorOAuthApp app = requireApp(connectorCode);
        StorageExternalAccount account = accountRepository.findByIdAndOwnerUserId(accountId, userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储账户不存在"));

        JSONObject tokens = exchangeCode(connectorCode, app, code.trim());
        JSONObject canonical = canonicalizeTokens(tokens);
        account.setEncryptedCredentials(credentialService.encrypt(canonical.toJSONString()));
        account.setStatus(ExternalStorageStatus.ACTIVE.getValue());
        account.setLastErrorCode(null);
        account.setLastCheckedAt(Instant.now());
        accountRepository.save(account);
        log.info("OAuth 授权成功: accountId={}, connector={}", accountId, connectorCode);
    }

    /**
     * 校验并返回可用的 access token；需要刷新时使用实例级 OAuth 应用换取新 token 并回写。
     *
     * @param account 外部存储账户
     * @return 规范化凭据与是否实际执行了刷新
     */
    public TokenRefreshResult ensureAccessToken(StorageExternalAccount account) {
        JSONObject credentials = JSON.parseObject(
                credentialService.decryptToJson(account.getEncryptedCredentials())
        );
        if (credentials == null || credentials.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "该连接尚未完成 OAuth 授权，请先在连接列表中发起授权");
        }
        String access = credentials.getString("access_token");
        Object expiry = credentials.get("expiry");
        if (access != null && !access.isBlank() && !isExpired(expiry)) {
            return new TokenRefreshResult(credentials, false);
        }
        String refresh = credentials.getString("refresh_token");
        if (refresh == null || refresh.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "缺少 refresh_token，请重新授权");
        }
        StorageConnectorOAuthApp app = requireApp(account.getProvider());
        JSONObject refreshed = refreshTokens(account.getProvider(), app, refresh);
        JSONObject canonical = canonicalizeTokens(refreshed);
        if (!canonical.containsKey("refresh_token")) {
            canonical.put("refresh_token", refresh);
        }
        account.setEncryptedCredentials(credentialService.encrypt(canonical.toJSONString()));
        accountRepository.save(account);
        return new TokenRefreshResult(canonical, true);
    }

    /**
     * 读取连接器实例级 OAuth 应用凭据；未配置或未启用时返回空。
     *
     * @param connectorCode 连接器编码
     * @return OAuth 应用凭据
     */
    public Optional<ConnectorAppCredentials> findAppCredentials(String connectorCode) {
        return oauthAppRepository.findFirstByConnectorCodeAndEnabledTrue(
                        connectorCode.trim().toUpperCase(Locale.ROOT))
                .map(app -> new ConnectorAppCredentials(
                        app.getClientId(),
                        credentialCipher.decrypt(app.getClientSecretEncrypted())
                ));
    }

    /**
     * 将提供方 token 响应规范化为 OmniNest 统一凭据结构。
     * 只保留 access_token、refresh_token、token_type、expiry 四个字段，
     * expires_in 秒数在此时转换为 rclone 认可的 ISO-8601 expiry。
     *
     * @param tokens 提供方 token 端点原始响应
     * @return 规范化凭据
     */
    private JSONObject canonicalizeTokens(JSONObject tokens) {
        String access = tokens.getString("access_token");
        if (access == null || access.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "OAuth 授权失败：提供方未返回 access_token");
        }
        JSONObject canonical = new JSONObject(new LinkedHashMap<>());
        canonical.put("access_token", access);
        String refresh = tokens.getString("refresh_token");
        if (refresh != null && !refresh.isBlank()) {
            canonical.put("refresh_token", refresh);
        }
        String tokenType = tokens.getString("token_type");
        canonical.put("token_type", tokenType == null || tokenType.isBlank() ? "Bearer" : tokenType);
        String expiry = tokens.getString("expiry");
        if (expiry == null || expiry.isBlank()) {
            Long expiresIn = tokens.getLong("expires_in");
            if (expiresIn != null && expiresIn > 0) {
                expiry = Instant.now().plusSeconds(expiresIn).toString();
            }
        }
        if (expiry != null && !expiry.isBlank()) {
            canonical.put("expiry", expiry);
        }
        return canonical;
    }

    private boolean isExpired(Object expiry) {
        if (expiry == null) {
            return false;
        }
        try {
            Instant instant = Instant.parse(expiry.toString());
            return instant.isBefore(Instant.now().plusSeconds(60));
        } catch (RuntimeException exception) {
            return false;
        }
    }

    private StorageConnectorOAuthApp requireApp(String connectorCode) {
        return oauthAppRepository.findFirstByConnectorCodeAndEnabledTrue(
                        connectorCode.trim().toUpperCase(Locale.ROOT))
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.CONFIG_VALUE_INVALID,
                        "未配置该连接器的 OAuth 应用，请管理员在管理后台的外部存储页面配置"
                ));
    }

    private String buildAuthorizationUrl(String code, StorageConnectorOAuthApp app) {
        String encodedRedirect = URLEncoder.encode(app.getRedirectUri(), StandardCharsets.UTF_8);
        return switch (code) {
            case "ONEDRIVE" -> "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
                    + "?client_id=" + URLEncoder.encode(app.getClientId(), StandardCharsets.UTF_8)
                    + "&response_type=code"
                    + "&redirect_uri=" + encodedRedirect
                    + "&scope=" + URLEncoder.encode("Files.ReadWrite.All offline_access", StandardCharsets.UTF_8);
            case "GDRIVE", "GOOGLE_DRIVE" -> "https://accounts.google.com/o/oauth2/v2/auth"
                    + "?client_id=" + URLEncoder.encode(app.getClientId(), StandardCharsets.UTF_8)
                    + "&response_type=code"
                    + "&redirect_uri=" + encodedRedirect
                    + "&scope=" + URLEncoder.encode(
                            "https://www.googleapis.com/auth/drive", StandardCharsets.UTF_8)
                    + "&access_type=offline"
                    + "&prompt=consent";
            case "DROPBOX" -> "https://www.dropbox.com/oauth2/authorize"
                    + "?client_id=" + URLEncoder.encode(app.getClientId(), StandardCharsets.UTF_8)
                    + "&response_type=code"
                    + "&redirect_uri=" + encodedRedirect
                    + "&token_access_type=offline";
            default -> throw new BusinessException(ErrorCode.PARAM_ERROR, "该连接器暂不支持 OAuth");
        };
    }

    private JSONObject exchangeCode(String code, StorageConnectorOAuthApp app, String authorizationCode) {
        return postToken(code, app, Map.of(
                "grant_type", "authorization_code",
                "code", authorizationCode,
                "redirect_uri", app.getRedirectUri(),
                "client_id", app.getClientId(),
                "client_secret", credentialCipher.decrypt(app.getClientSecretEncrypted())
        ));
    }

    private JSONObject refreshTokens(String provider, StorageConnectorOAuthApp app, String refreshToken) {
        return postToken(provider, app, Map.of(
                "grant_type", "refresh_token",
                "refresh_token", refreshToken,
                "client_id", app.getClientId(),
                "client_secret", credentialCipher.decrypt(app.getClientSecretEncrypted())
        ));
    }

    private JSONObject postToken(String provider, StorageConnectorOAuthApp app, Map<String, String> form) {
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
            return JSON.parseObject(response.body());
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "OAuth 请求被中断");
        } catch (java.io.IOException exception) {
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

    private ConnectorOAuthAppDto toDto(StorageConnectorOAuthApp app) {
        return new ConnectorOAuthAppDto(
                app.getId(),
                app.getConnectorCode(),
                app.getClientId(),
                app.getRedirectUri(),
                app.isEnabled(),
                app.getUpdatedAt()
        );
    }
}
