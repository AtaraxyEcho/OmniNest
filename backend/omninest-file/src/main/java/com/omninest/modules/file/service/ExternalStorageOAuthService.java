package com.omninest.modules.file.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.concurrency.DistributedLock;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.json.JsonSupport;
import com.omninest.common.security.CredentialCipher;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.file.domain.StorageConnectorOAuthApp;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.domain.ExternalStorageStatus;
import com.omninest.modules.file.dto.ConnectorOAuthAppDto;
import com.omninest.modules.file.dto.OAuthStartResponse;
import com.omninest.modules.file.dto.SaveConnectorOAuthAppRequest;
import com.omninest.modules.file.repository.StorageConnectorOAuthAppRepository;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import com.omninest.modules.quota.port.AdminActorVerifier;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import tools.jackson.core.type.TypeReference;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

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
    private static final String STATE_KEY_PREFIX = "omninest:oauth:state:";

    private final StorageConnectorOAuthAppRepository oauthAppRepository;
    private final StorageExternalAccountRepository accountRepository;
    private final ExternalStorageCredentialService credentialService;
    private final CredentialCipher credentialCipher;
    private final ReadThroughCache readThroughCache;
    private final DistributedLock distributedLock;
    private final AdminActorVerifier adminActorVerifier;
    private final AdminAuditRecorder adminAuditRecorder;
    private final UserSyncEventRecorder syncEventRecorder;
    private final ExternalStorageOAuthTokenClient tokenClient;
    private final TransactionTemplate transactionTemplate;

    /**
     * 同账户刷新在本实例内串行；跨实例由分布式锁协调。
     *
     * <p>按账户缓存的锁对象必须有界：外部存储账号被删除后不会再访问，
     * 裸 ConcurrentMap 会随账号数量长期增长。</p>
     */
    private final Cache<UUID, Object> refreshLocalLocks = Caffeine.newBuilder()
            .maximumSize(256)
            .expireAfterAccess(Duration.ofMinutes(30))
            .build();

    /**
     * token 校验或刷新结果。
     *
     * @param credentials 规范化后的完整凭据
     * @param refreshed 是否实际执行了 token 刷新
     */
    public record TokenRefreshResult(Map<String, Object> credentials, boolean refreshed) {
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
    public ConnectorOAuthAppDto saveApp(UUID actorUserId, SaveConnectorOAuthAppRequest request) {
        // 令牌里的权限声明可能已过期，实例级 OAuth 应用配置必须按库内当前角色复核。
        adminActorVerifier.requireFreshAdminActor(actorUserId);
        String code = ExternalStorageProviders.requireAllowed(request.connectorCode());
        if (request.clientId() == null || request.clientId().isBlank()
                || request.redirectUri() == null || request.redirectUri().isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "Client ID 与回调地址不能为空");
        }
        StorageConnectorOAuthApp app = oauthAppRepository
                .findFirstByConnectorCode(code)
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
        ConnectorOAuthAppDto saved = toDto(oauthAppRepository.save(app));
        // 审计只落连接器与启用状态，Client Secret 及其密文一律不进载荷。
        adminAuditRecorder.recordWithMetadata(
                actorUserId,
                "EXTERNAL_OAUTH_APP_SAVE",
                "storage_connector_oauth_apps",
                saved.id(),
                Map.of("connectorCode", code, "enabled", request.enabled()));
        return saved;
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
        // state 落 Redis：多实例部署或重启后回调仍能定位本次授权，且 TTL 由服务端统一回收。
        OAuthStatePayload payload = new OAuthStatePayload(
                ownerUserId.toString(), accountId.toString(), code);
        readThroughCache.getOrLoad(
                STATE_KEY_PREFIX + state,
                STATE_TTL,
                () -> payload,
                OAuthStatePayload.class
        );
        return new OAuthStartResponse(buildAuthorizationUrl(code, app, state), state);
    }

    /**
     * 处理 OAuth 回调并绑定 token。
     *
     * <p>路径上的连接器编码必须与发起授权时记录的一致，否则同一实例下的
     * 另一连接器可以拿别人的 state 完成自己的回调。state 使用一次性读取，
     * 读取即删除，重复回调直接失败。</p>
     *
     * <p>第三方令牌交换最长可达 30 秒，绝不能包在数据库事务里：否则少数慢回调
     * 就会占满 HikariCP 连接并拖垮整个后端。外部请求完成后才用短事务落库。</p>
     *
     * @param providerCode 回调路径中的连接器编码
     * @param state OAuth state
     * @param code 授权码
     */
    public void handleCallback(String providerCode, String state, String code) {
        if (state == null || state.isBlank() || code == null || code.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "OAuth 回调参数不完整");
        }
        String raw = readThroughCache.take(STATE_KEY_PREFIX + state.trim());
        if (raw == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "OAuth state 无效或已过期");
        }
        OAuthStatePayload statePayload;
        try {
            statePayload = JsonSupport.fromJson(raw, OAuthStatePayload.class);
        } catch (RuntimeException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "OAuth state 无效或已过期");
        }
        String requestedProvider = providerCode == null
                ? ""
                : providerCode.trim().toUpperCase(Locale.ROOT);
        if (!requestedProvider.equals(statePayload.code())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "OAuth 提供商与发起授权时的连接器不匹配");
        }
        UUID userId = UUID.fromString(statePayload.userId());
        UUID accountId = UUID.fromString(statePayload.accountId());
        String connectorCode = statePayload.code();
        StorageConnectorOAuthApp app = requireApp(connectorCode);
        accountRepository.findByIdAndOwnerUserId(accountId, userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储账户不存在"));

        Map<String, Object> tokens = tokenClient.exchangeCode(connectorCode, app, code.trim());
        String encryptedCredentials = credentialService.encrypt(
                JsonSupport.toJson(canonicalizeTokens(tokens)));
        transactionTemplate.executeWithoutResult(status -> {
            StorageExternalAccount account = accountRepository
                    .findByIdAndOwnerUserId(accountId, userId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储账户不存在"));
            account.setEncryptedCredentials(encryptedCredentials);
            account.setStatus(ExternalStorageStatus.ACTIVE.getValue());
            account.setLastErrorCode(null);
            account.setLastCheckedAt(Instant.now());
            accountRepository.save(account);
            // 授权在浏览器完成后才落库，必须推送同步事件让已打开的文件页实时刷新账户状态。
            syncEventRecorder.record(new SyncEventCommand(
                    userId,
                    SyncScope.FILES,
                    "EXTERNAL_STORAGE",
                    accountId.toString(),
                    SyncAction.UPDATED,
                    null,
                    Map.of()
            ));
        });
        log.info("OAuth 授权成功: accountId={}, connector={}", accountId, connectorCode);
    }

    /**
     * 已发起的 OAuth 授权会话。
     *
     * @param userId 发起授权的用户标识
     * @param accountId 外部存储账户标识
     * @param code 连接器编码
     */
    private record OAuthStatePayload(String userId, String accountId, String code) {
    }

    /**
     * 校验并返回可用的 access token；需要刷新时使用实例级 OAuth 应用换取新 token 并回写。
     *
     * @param account 外部存储账户
     * @return 规范化凭据与是否实际执行了刷新
     */
    public TokenRefreshResult ensureAccessToken(StorageExternalAccount account) {
        Object localLock = refreshLocalLocks.get(account.getId(), key -> new Object());
        synchronized (localLock) {
            return ensureAccessTokenLocked(account.getId());
        }
    }

    private TokenRefreshResult ensureAccessTokenLocked(UUID accountId) {
        StorageExternalAccount account = accountRepository.findById(accountId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储账户不存在"));
        Map<String, Object> credentials = parseCredentials(
                credentialService.decryptToJson(account.getEncryptedCredentials())
        );
        if (credentials == null || credentials.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "该连接尚未完成 OAuth 授权，请先在连接列表中发起授权");
        }
        if (hasUsableAccessToken(credentials)) {
            return new TokenRefreshResult(credentials, false);
        }

        String lockKey = "omninest:external-oauth:refresh:" + accountId;
        String lockToken = distributedLock.newToken();
        boolean lockAttempted = true;
        boolean locked = false;
        try {
            locked = distributedLock.tryLock(lockKey, lockToken, Duration.ofSeconds(30));
        } catch (RuntimeException exception) {
            // Redis 不可用时退化为本实例串行，不能把外部存储导入整体打死。
            lockAttempted = false;
            log.warn("外部存储刷新锁不可用，退化为单实例串行: accountId={}, errorType={}",
                    accountId, exception.getClass().getSimpleName());
        }
        if (lockAttempted && !locked) {
            // 其他实例正在刷新：重新读取，若已拿到新令牌直接复用，否则让调用方重试。
            StorageExternalAccount latest = accountRepository.findById(accountId).orElse(account);
            Map<String, Object> latestCredentials = parseCredentials(
                    credentialService.decryptToJson(latest.getEncryptedCredentials()));
            if (latestCredentials != null && hasUsableAccessToken(latestCredentials)) {
                return new TokenRefreshResult(latestCredentials, false);
            }
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "外部存储凭据正在刷新，请稍后重试");
        }
        try {
            // 持锁后重新读取，避免另一个实例刚刷新完成又被本实例覆盖。
            account = accountRepository.findById(accountId).orElse(account);
            credentials = parseCredentials(
                    credentialService.decryptToJson(account.getEncryptedCredentials()));
            if (credentials == null || credentials.isEmpty()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "该连接尚未完成 OAuth 授权，请先在连接列表中发起授权");
            }
            if (hasUsableAccessToken(credentials)) {
                return new TokenRefreshResult(credentials, false);
            }
            String refresh = textOrNull(credentials, "refresh_token");
            if (refresh == null || refresh.isBlank()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "缺少 refresh_token，请重新授权");
            }
            StorageConnectorOAuthApp app = requireApp(account.getProvider());
            Map<String, Object> refreshed = tokenClient.refreshTokens(account.getProvider(), app, refresh);
            Map<String, Object> canonical = canonicalizeTokens(refreshed);
            if (!canonical.containsKey("refresh_token")) {
                canonical.put("refresh_token", refresh);
            }
            account.setEncryptedCredentials(credentialService.encrypt(JsonSupport.toJson(canonical)));
            accountRepository.save(account);
            return new TokenRefreshResult(canonical, true);
        } finally {
            if (locked) {
                try {
                    distributedLock.unlock(lockKey, lockToken);
                } catch (RuntimeException exception) {
                    log.warn("外部存储刷新锁释放失败: accountId={}, errorType={}",
                            accountId, exception.getClass().getSimpleName());
                }
            }
        }
    }

    private boolean hasUsableAccessToken(Map<String, Object> credentials) {
        String access = textOrNull(credentials, "access_token");
        return access != null && !access.isBlank() && !isExpired(credentials.get("expiry"));
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
    private Map<String, Object> canonicalizeTokens(Map<String, Object> tokens) {
        String access = textOrNull(tokens, "access_token");
        if (access == null || access.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "OAuth 授权失败：提供方未返回 access_token");
        }
        Map<String, Object> canonical = new LinkedHashMap<>();
        canonical.put("access_token", access);
        String refresh = textOrNull(tokens, "refresh_token");
        if (refresh != null && !refresh.isBlank()) {
            canonical.put("refresh_token", refresh);
        }
        String tokenType = textOrNull(tokens, "token_type");
        canonical.put("token_type", tokenType == null || tokenType.isBlank() ? "Bearer" : tokenType);
        String expiry = textOrNull(tokens, "expiry");
        if (expiry == null || expiry.isBlank()) {
            Long expiresIn = nullableLong(tokens, "expires_in");
            if (expiresIn != null && expiresIn > 0) {
                expiry = Instant.now().plusSeconds(expiresIn).toString();
            }
        }
        if (expiry != null && !expiry.isBlank()) {
            canonical.put("expiry", expiry);
        }
        return canonical;
    }

    private static Map<String, Object> parseCredentials(String json) {
        return JsonSupport.fromJson(json, new TypeReference<Map<String, Object>>() {});
    }

    private static String textOrNull(Map<String, Object> map, String key) {
        Object value = map.get(key);
        return value == null ? null : value.toString();
    }

    private static Long nullableLong(Map<String, Object> map, String key) {
        Object value = map.get(key);
        if (value instanceof Number number) {
            return number.longValue();
        }
        if (value == null) {
            return null;
        }
        try {
            return Long.parseLong(value.toString().trim());
        } catch (NumberFormatException exception) {
            return null;
        }
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

    /**
     * 构造三方授权地址。
     *
     * <p>{@code state} 必须随地址下发：回调处理器只认 state 命中的授权会话，且它是该
     * 回调端点唯一的跨站请求伪造防线（端点本身匿名可访问）。此前生成并缓存了 state 却
     * 从不拼接，三方回跳时不带该参数，授权流程必然停在「state 无效或已过期」。</p>
     *
     * @param code 连接器编码
     * @param app 该连接器的 OAuth 应用配置
     * @param state 本次授权的一次性状态串
     * @return 授权地址
     */
    private String buildAuthorizationUrl(String code, StorageConnectorOAuthApp app, String state) {
        String encodedRedirect = URLEncoder.encode(app.getRedirectUri(), StandardCharsets.UTF_8);
        String encodedState = URLEncoder.encode(state, StandardCharsets.UTF_8);
        String stateParam = "&state=" + encodedState;
        return switch (code) {
            case "ONEDRIVE" -> "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
                    + "?client_id=" + URLEncoder.encode(app.getClientId(), StandardCharsets.UTF_8)
                    + "&response_type=code"
                    + "&redirect_uri=" + encodedRedirect
                    + "&scope=" + URLEncoder.encode("Files.Read.All offline_access", StandardCharsets.UTF_8)
                    + stateParam;
            case "GDRIVE", "GOOGLE_DRIVE" -> "https://accounts.google.com/o/oauth2/v2/auth"
                    + "?client_id=" + URLEncoder.encode(app.getClientId(), StandardCharsets.UTF_8)
                    + "&response_type=code"
                    + "&redirect_uri=" + encodedRedirect
                    + "&scope=" + URLEncoder.encode(
                            "https://www.googleapis.com/auth/drive.readonly", StandardCharsets.UTF_8)
                    + "&access_type=offline"
                    + "&prompt=consent"
                    + stateParam;
            case "DROPBOX" -> "https://www.dropbox.com/oauth2/authorize"
                    + "?client_id=" + URLEncoder.encode(app.getClientId(), StandardCharsets.UTF_8)
                    + "&response_type=code"
                    + "&redirect_uri=" + encodedRedirect
                    + "&token_access_type=offline"
                    + stateParam;
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
