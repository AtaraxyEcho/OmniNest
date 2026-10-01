package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.dto.CreateExternalStorageRequest;
import com.omninest.modules.file.dto.ExternalStorageAccountDto;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * ExternalStorageAccountService 单元测试。
 * 重点覆盖 OAuth 连接器创建前的实例级应用配置预检。
 *
 * @author OmniNest
 */
class ExternalStorageAccountServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final StorageExternalAccountRepository externalAccountRepository =
            mock(StorageExternalAccountRepository.class);
    private final ExternalStorageService externalStorageService = mock(ExternalStorageService.class);
    private final ExternalStorageCredentialService credentialService =
            mock(ExternalStorageCredentialService.class);
    private final ExternalStorageOAuthService oauthService = mock(ExternalStorageOAuthService.class);
    private final ExternalStorageEndpointGuard endpointGuard = mock(ExternalStorageEndpointGuard.class);

    private final ExternalStorageAccountService service = new ExternalStorageAccountService(
            externalAccountRepository, externalStorageService, credentialService, oauthService, endpointGuard);

    @BeforeEach
    void setUpSave() {
        when(externalAccountRepository.save(any(StorageExternalAccount.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(credentialService.encrypt(any())).thenReturn("encrypted");
    }

    @Test
    void createRejectsOAuthConnectorWhenAppMissing() {
        when(oauthService.findAppCredentials("GDRIVE")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.createExternalAccount(OWNER_ID,
                new CreateExternalStorageRequest("GDRIVE", "我的云端硬盘", "{}")))
                .isInstanceOf(BusinessException.class)
                .satisfies(ex -> assertThat(((BusinessException) ex).errorCode())
                        .isEqualTo(ErrorCode.CONFIG_VALUE_INVALID))
                .hasMessageContaining("尚未配置实例级 OAuth 应用");
        verifyNoInteractions(externalAccountRepository);
    }

    @Test
    void createAllowsOAuthConnectorWhenAppConfigured() {
        when(oauthService.findAppCredentials("GDRIVE")).thenReturn(Optional.of(
                new ExternalStorageOAuthService.ConnectorAppCredentials("cid", "csec")));

        ExternalStorageAccountDto result = service.createExternalAccount(OWNER_ID,
                new CreateExternalStorageRequest("gdrive", "我的云端硬盘", "{}"));

        assertThat(result.provider()).isEqualTo("GDRIVE");
        assertThat(result.displayName()).isEqualTo("我的云端硬盘");
        verify(externalAccountRepository).save(any(StorageExternalAccount.class));
    }

    @Test
    void createSkipsAppCheckForPasswordConnector() {
        assertThatCode(() -> service.createExternalAccount(OWNER_ID,
                new CreateExternalStorageRequest("WEBDAV", "坚果云", "{\"url\":\"https://dav.example.com\"}")))
                .doesNotThrowAnyException();
        verifyNoInteractions(oauthService);
    }

    @Test
    void createValidatesEndpointSafetyBeforeSave() {
        doThrow(new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "外部存储地址被安全策略拒绝"))
                .when(endpointGuard).validate(anyString(), any());

        assertThatThrownBy(() -> service.createExternalAccount(OWNER_ID,
                new CreateExternalStorageRequest("WEBDAV", "内网盘", "{\"url\":\"http://192.168.1.10/dav\"}")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("安全策略拒绝");
        verifyNoInteractions(externalAccountRepository);
    }

    @Test
    void createSanitizesCredentialsBeforeEncryption() {
        service.createExternalAccount(OWNER_ID, new CreateExternalStorageRequest("WEBDAV", "内网盘",
                "{\"url\":\"https://dav.example.com\",\"type\":\"s3\",\"config_is_local\":\"true\"}"));

        ArgumentCaptor<String> captor = ArgumentCaptor.forClass(String.class);
        verify(credentialService).encrypt(captor.capture());
        assertThat(captor.getValue()).contains("dav.example.com").doesNotContain("config_is_local");
    }
}
