package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

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

    private final ExternalStorageOAuthService service = new ExternalStorageOAuthService(
            oauthAppRepository, accountRepository, credentialService, credentialCipher
    );

    @BeforeEach
    void setUpCredentialDecrypt() {
        when(credentialService.decryptToJson(anyString()))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(accountRepository.save(org.mockito.ArgumentMatchers.any(StorageExternalAccount.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
    }

    @Test
    void ensureAccessToken_returnsUnrefreshedWhenTokenValid() {
        StorageExternalAccount account = buildAccount(
                "{\"access_token\":\"at\",\"refresh_token\":\"rt\","
                        + "\"expiry\":\"2099-01-01T00:00:00Z\"}");

        ExternalStorageOAuthService.TokenRefreshResult result = service.ensureAccessToken(account);

        assertThat(result.refreshed()).isFalse();
        assertThat(result.credentials().getString("access_token")).isEqualTo("at");
    }

    @Test
    void ensureAccessToken_rejectsUnAuthorizedAccount() {
        StorageExternalAccount account = buildAccount("{}");

        assertThatThrownBy(() -> service.ensureAccessToken(account))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("尚未完成 OAuth 授权");
    }

    @Test
    void ensureAccessToken_rejectsExpiredTokenWithoutRefreshToken() {
        StorageExternalAccount account = buildAccount(
                "{\"access_token\":\"at\",\"expiry\":\"2000-01-01T00:00:00Z\"}");

        assertThatThrownBy(() -> service.ensureAccessToken(account))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("缺少 refresh_token");
    }

    @Test
    void ensureAccessToken_requiresConfiguredAppWhenRefreshing() {
        StorageExternalAccount account = buildAccount(
                "{\"access_token\":\"at\",\"refresh_token\":\"rt\","
                        + "\"expiry\":\"2000-01-01T00:00:00Z\"}");
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

    private StorageExternalAccount buildAccount(String credentialsJson) {
        StorageExternalAccount account = new StorageExternalAccount();
        account.setId(ACCOUNT_ID);
        account.setOwnerUserId(OWNER_ID);
        account.setProvider("GDRIVE");
        account.setDisplayName("测试授权");
        account.setEncryptedCredentials(credentialsJson);
        account.setStatus(ExternalStorageStatus.ACTIVE.getValue());
        account.setCreatedAt(Instant.now());
        account.setUpdatedAt(Instant.now());
        return account;
    }
}
