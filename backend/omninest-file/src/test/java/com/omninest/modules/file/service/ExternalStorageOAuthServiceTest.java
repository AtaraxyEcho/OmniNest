package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.concurrency.DistributedLock;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CredentialCipher;
import com.omninest.modules.file.domain.ExternalStorageStatus;
import com.omninest.modules.file.domain.StorageConnectorOAuthApp;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.repository.StorageConnectorOAuthAppRepository;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * ExternalStorageOAuthService 单元测试。
 * 覆盖不触发外部 HTTP 的 token 校验与刷新前置分支。
 *
 * @author OmniNest
 */
class ExternalStorageOAuthServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ACCOUNT_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final StorageConnectorOAuthAppRepository oauthAppRepository =
            mock(StorageConnectorOAuthAppRepository.class);
    private final StorageExternalAccountRepository accountRepository =
            mock(StorageExternalAccountRepository.class);
    private final ExternalStorageCredentialService credentialService =
            mock(ExternalStorageCredentialService.class);
    private final CredentialCipher credentialCipher = mock(CredentialCipher.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class);
    private final DistributedLock distributedLock = mock(DistributedLock.class);

    private final ExternalStorageOAuthService service = new ExternalStorageOAuthService(
            oauthAppRepository, accountRepository, credentialService, credentialCipher,
            readThroughCache, distributedLock
    );

    @BeforeEach
    void setUpCredentialDecrypt() {
        when(credentialService.decryptToJson(anyString()))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(accountRepository.save(any(StorageExternalAccount.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(distributedLock.newToken()).thenReturn("lock-token");
        when(distributedLock.tryLock(anyString(), anyString(), any()))
                .thenReturn(true);
        when(distributedLock.unlock(anyString(), anyString())).thenReturn(true);
    }

    @Test
    void ensureAccessToken_returnsUnrefreshedWhenTokenValid() {
        StorageExternalAccount account = buildAccount(
                "{\"access_token\":\"at\",\"refresh_token\":\"rt\","
                        + "\"expiry\":\"2099-01-01T00:00:00Z\"}");

        when(accountRepository.findById(ACCOUNT_ID)).thenReturn(Optional.of(account));
        ExternalStorageOAuthService.TokenRefreshResult result = service.ensureAccessToken(account);

        assertThat(result.refreshed()).isFalse();
        assertThat(result.credentials().get("access_token")).isEqualTo("at");
    }

    @Test
    void ensureAccessToken_rejectsUnAuthorizedAccount() {
        StorageExternalAccount account = buildAccount("{}");

        when(accountRepository.findById(ACCOUNT_ID)).thenReturn(Optional.of(account));
        assertThatThrownBy(() -> service.ensureAccessToken(account))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("尚未完成 OAuth 授权");
    }

    @Test
    void ensureAccessToken_rejectsExpiredTokenWithoutRefreshToken() {
        StorageExternalAccount account = buildAccount(
                "{\"access_token\":\"at\",\"expiry\":\"2000-01-01T00:00:00Z\"}");

        when(accountRepository.findById(ACCOUNT_ID)).thenReturn(Optional.of(account));
        assertThatThrownBy(() -> service.ensureAccessToken(account))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("缺少 refresh_token");
    }

    @Test
    void ensureAccessToken_requiresConfiguredAppWhenRefreshing() {
        StorageExternalAccount account = buildAccount(
                "{\"access_token\":\"at\",\"refresh_token\":\"rt\","
                        + "\"expiry\":\"2000-01-01T00:00:00Z\"}");
        when(accountRepository.findById(ACCOUNT_ID)).thenReturn(Optional.of(account));
        when(oauthAppRepository.findFirstByConnectorCodeAndEnabledTrue("GDRIVE"))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.ensureAccessToken(account))
                .isInstanceOf(BusinessException.class)
                .satisfies(ex -> assertThat(((BusinessException) ex).errorCode())
                        .isEqualTo(ErrorCode.CONFIG_VALUE_INVALID))
                .hasMessageContaining("未配置该连接器的 OAuth 应用");
    }

    @Test
    void findAppCredentials_decryptsClientSecret() {
        StorageConnectorOAuthApp app = new StorageConnectorOAuthApp();
        app.setConnectorCode("gdrive");
        app.setClientId("cid");
        app.setClientSecretEncrypted("encrypted");
        app.setRedirectUri("https://example.com/callback");
        when(oauthAppRepository.findFirstByConnectorCodeAndEnabledTrue("GDRIVE"))
                .thenReturn(Optional.of(app));
        when(credentialCipher.decrypt("encrypted")).thenReturn("csec");

        Optional<ExternalStorageOAuthService.ConnectorAppCredentials> result =
                service.findAppCredentials(" gdrive ");

        assertThat(result).isPresent();
        assertThat(result.get().clientId()).isEqualTo("cid");
        assertThat(result.get().clientSecret()).isEqualTo("csec");
    }

    @Test
    void findAppCredentials_returnsEmptyWhenNotConfigured() {
        when(oauthAppRepository.findFirstByConnectorCodeAndEnabledTrue("DROPBOX"))
                .thenReturn(Optional.empty());

        assertThat(service.findAppCredentials("DROPBOX")).isEmpty();
        verify(oauthAppRepository).findFirstByConnectorCodeAndEnabledTrue("DROPBOX");
    }

    @Test
    void buildAuthorizationUrlCarriesStateForEveryProvider() {
        StorageConnectorOAuthApp app = new StorageConnectorOAuthApp();
        app.setConnectorCode("GDRIVE");
        app.setClientId("client-id");
        app.setClientSecretEncrypted("secret");
        app.setRedirectUri("http://localhost:8080/api/v1/external-connectors/GDRIVE/oauth/callback");
        app.setEnabled(true);
        when(oauthAppRepository.findFirstByConnectorCodeAndEnabledTrue(anyString()))
                .thenReturn(Optional.of(app));
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT_ID, OWNER_ID))
                .thenReturn(Optional.of(buildAccount("{}")));

        var response = service.start(OWNER_ID, "GDRIVE", ACCOUNT_ID);

        assertThat(response.state()).isNotBlank();
        assertThat(response.authorizationUrl())
                .contains("state=" + response.state())
                .contains("redirect_uri=");
    }

    @Test
    @DisplayName("授权链接只申请只读 scope，且带 offline 能力")
    void authorizationUrlsRequestReadOnlyScopes() {
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT_ID, OWNER_ID))
                .thenReturn(
                        Optional.of(buildAccount("ONEDRIVE", "{}")),
                        Optional.of(buildAccount("GDRIVE", "{}")));
        when(oauthAppRepository.findFirstByConnectorCodeAndEnabledTrue("ONEDRIVE"))
                .thenReturn(Optional.of(buildApp("ONEDRIVE")));
        when(oauthAppRepository.findFirstByConnectorCodeAndEnabledTrue("GDRIVE"))
                .thenReturn(Optional.of(buildApp("GDRIVE")));

        String oneDrive = service.start(OWNER_ID, "ONEDRIVE", ACCOUNT_ID).authorizationUrl();
        String googleDrive = service.start(OWNER_ID, "GDRIVE", ACCOUNT_ID).authorizationUrl();

        // 远程源定位是只读浏览与导入，读写 scope 会让一次凭据泄露波及用户云端全部文件。
        assertThat(oneDrive)
                .contains("scope=Files.Read.All+offline_access")
                .doesNotContain("ReadWrite");
        assertThat(googleDrive)
                .contains("scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive.readonly")
                .contains("access_type=offline")
                .doesNotContain("auth%2Fdrive&");
    }

    @Test
    void handleCallbackRejectsUnknownState() {
        assertThatThrownBy(() -> service.handleCallback("GDRIVE", "never-issued", "authorization-code"))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    @Test
    void handleCallbackRejectsProviderThatDoesNotMatchIssuedState() {
        when(readThroughCache.take("omninest:oauth:state:issued-state"))
                .thenReturn("{\"userId\":\"" + OWNER_ID + "\",\"accountId\":\"" + ACCOUNT_ID
                        + "\",\"code\":\"GDRIVE\"}");

        assertThatThrownBy(() -> service.handleCallback("ONEDRIVE", "issued-state", "authorization-code"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不匹配");
    }


    private StorageExternalAccount buildAccount(String credentialsJson) {
        return buildAccount("GDRIVE", credentialsJson);
    }

    private StorageExternalAccount buildAccount(String provider, String credentialsJson) {
        StorageExternalAccount account = new StorageExternalAccount();
        account.setId(ACCOUNT_ID);
        account.setOwnerUserId(OWNER_ID);
        account.setProvider(provider);
        account.setDisplayName("测试授权");
        account.setEncryptedCredentials(credentialsJson);
        account.setStatus(ExternalStorageStatus.ACTIVE.getValue());
        account.setCreatedAt(Instant.now());
        account.setUpdatedAt(Instant.now());
        return account;
    }

    private StorageConnectorOAuthApp buildApp(String connectorCode) {
        StorageConnectorOAuthApp app = new StorageConnectorOAuthApp();
        app.setConnectorCode(connectorCode);
        app.setClientId("client-id");
        app.setClientSecretEncrypted("secret");
        app.setRedirectUri("http://localhost/api/v1/external-connectors/"
                + connectorCode + "/oauth/callback");
        app.setEnabled(true);
        return app;
    }
}
