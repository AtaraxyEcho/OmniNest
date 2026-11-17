package com.omninest.modules.configcenter.service;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.security.CredentialCipher;
import com.omninest.modules.configcenter.domain.ConfigEntry;
import com.omninest.modules.configcenter.repository.ConfigEntryRepository;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 配置值查询服务，向其他模块提供不暴露配置实体和仓储的只读端口。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class ConfigValueQueryService implements ConfigValueProvider {

    private final ConfigEntryRepository configEntryRepository;
    private final CredentialCipher credentialCipher;

    /**
     * 按配置键查询原始配置值。
     *
     * @param key 配置键
     * @return 配置值，不存在时返回空
     */
    @Override
    @Transactional(readOnly = true)
    public Optional<String> findByKey(String key) {
        return configEntryRepository.findByConfigKey(key)
                .map(this::resolveValue);
    }

    private String resolveValue(ConfigEntry entry) {
        String value = entry.getConfigValue();
        if (!entry.isSensitive() || value == null || value.isBlank()) {
            return value;
        }
        return credentialCipher.decrypt(value);
    }
}
