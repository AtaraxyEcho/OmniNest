package com.omninest.modules.configcenter.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.security.CredentialCipher;
import com.omninest.modules.configcenter.domain.ConfigEntry;
import com.omninest.modules.configcenter.repository.ConfigEntryRepository;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * 配置值查询服务测试。
 *
 * @author OmniNest
 */
class ConfigValueQueryServiceTest {

    private final ConfigEntryRepository configEntryRepository = mock(ConfigEntryRepository.class);
    private final CredentialCipher credentialCipher = mock(CredentialCipher.class);
    private final ConfigValueQueryService service = new ConfigValueQueryService(
            configEntryRepository,
            credentialCipher
    );

    /**
     * 验证查询端口只返回配置原始值。
     */
    @Test
    void findByKeyReturnsRawValue() {
        ConfigEntry entry = new ConfigEntry();
        entry.setConfigKey("feature.enabled");
        entry.setConfigValue("true");
        when(configEntryRepository.findByConfigKey("feature.enabled"))
                .thenReturn(Optional.of(entry));

        assertThat(service.findByKey("feature.enabled")).contains("true");
    }

    /**
     * 验证敏感配置仅在运行时查询端口解密。
     */
    @Test
    void findByKeyDecryptsSensitiveValue() {
        ConfigEntry entry = new ConfigEntry();
        entry.setConfigKey("weather.qweather.private-key");
        entry.setConfigValue("v1:iv:payload");
        entry.setSensitive(true);
        when(configEntryRepository.findByConfigKey("weather.qweather.private-key"))
                .thenReturn(Optional.of(entry));
        when(credentialCipher.decrypt("v1:iv:payload")).thenReturn("private-key");

        assertThat(service.findByKey("weather.qweather.private-key")).contains("private-key");
    }
}
