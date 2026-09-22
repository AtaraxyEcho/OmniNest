package com.omninest.modules.configcenter.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.DomainEventPublisher;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.security.CredentialCipher;
import com.omninest.common.security.CurrentUser;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.common.security.Roles;
import com.omninest.modules.configcenter.domain.ConfigEntry;
import com.omninest.modules.configcenter.domain.ConfigHistory;
import com.omninest.modules.configcenter.repository.ConfigEntryRepository;
import com.omninest.modules.configcenter.repository.ConfigHistoryRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

/**
 * 配置中心应用服务单元测试。
 *
 * @author OmniNest
 */
class ConfigCenterServiceTest {
    private final ConfigEntryRepository configEntryRepository = mock(ConfigEntryRepository.class);
    private final ConfigHistoryRepository configHistoryRepository = mock(ConfigHistoryRepository.class);
    private final DomainEventPublisher publisher = mock(DomainEventPublisher.class);
    private final CredentialCipher credentialCipher = mock(CredentialCipher.class);
    private final CurrentUserContext currentUserContext = mock(CurrentUserContext.class);
    private final ConfigCenterService service = new ConfigCenterService(
            configEntryRepository,
            configHistoryRepository,
            publisher,
            credentialCipher,
            currentUserContext
    );

    @BeforeEach
    void setUpCurrentUser() {
        when(currentUserContext.requireCurrentUser()).thenReturn(currentUser(
                Set.of(Permissions.SYSTEM_CONFIG_MANAGE),
                Set.of(Roles.SUPER_ADMIN)
        ));
    }

    @Test
    void initDefaultsIncludesStorageSettings() {
        stubCatalogLock();
        when(configEntryRepository.findAll()).thenReturn(List.of());

        service.initializeCatalog();

        ArgumentCaptor<ConfigEntry> entries = ArgumentCaptor.forClass(ConfigEntry.class);
        verify(configEntryRepository, atLeastOnce()).save(entries.capture());
        assertThat(entries.getAllValues())
                .extracting(ConfigEntry::getConfigKey)
                .contains(
                        "share.enabled",
                        "share.max-bytes",
                        "media.transcode.enabled"
                );
    }

    @Test
    void listReadsEntriesFromDatabase() {
        ConfigEntry entry = entry("share.max-bytes", "120", "NUMBER", "storage", "HOT");
        when(configEntryRepository.findAll(Sort.by(Sort.Direction.ASC, "configKey"))).thenReturn(List.of(entry));

        var entries = service.list();

        assertThat(entries).hasSize(1);
        assertThat(entries.get(0).key()).isEqualTo("share.max-bytes");
        assertThat(entries.get(0).value()).isEqualTo("120");
    }

    @Test
    void updatePersistsEntryHistoryAndPublishesRefreshEvent() {
        ConfigEntry entry = entry("share.max-bytes", "120", "NUMBER", "storage", "HOT");
        UUID changedBy = UUID.randomUUID();
        when(configEntryRepository.findByConfigKey("share.max-bytes")).thenReturn(Optional.of(entry));
        when(configEntryRepository.save(any(ConfigEntry.class))).thenAnswer(invocation -> invocation.getArgument(0));

        var updated = service.update("share.max-bytes", "180", "调整共享空间容量", changedBy);

        assertThat(updated.value()).isEqualTo("180");
        assertThat(entry.getConfigValue()).isEqualTo("180");
        verify(configHistoryRepository).save(any(ConfigHistory.class));
        verify(publisher).publishFanout(any(), any());
        verify(publisher).publishFanout(ArgumentMatchers.eq(QueueNames.CONFIG_REFRESH_EXCHANGE), any());
    }

    @Test
    void updateValueUsesPublicRuntimeConfigCommand() {
        ConfigEntry entry = entry("share.enabled", "true", "BOOLEAN", "storage", "HOT");
        UUID changedBy = UUID.randomUUID();
        when(configEntryRepository.findByConfigKey("share.enabled")).thenReturn(Optional.of(entry));
        when(configEntryRepository.save(any(ConfigEntry.class))).thenAnswer(invocation -> invocation.getArgument(0));

        service.updateValue("share.enabled", "false", "关闭共享空间", changedBy);

        assertThat(entry.getConfigValue()).isEqualTo("false");
        verify(configHistoryRepository).save(any(ConfigHistory.class));
        verify(publisher).publishFanout(ArgumentMatchers.eq(QueueNames.CONFIG_REFRESH_EXCHANGE), any());
    }

    @Test
    void updateRejectsUnknownAndHiddenKeys() {
        assertThatThrownBy(() -> service.update("unknown.key", "value", null, UUID.randomUUID()))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不允许运行时编辑");
        assertThatThrownBy(() -> service.update(
                "rate-limit.default-limit",
                "120",
                null,
                UUID.randomUUID()
        ))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不允许运行时编辑");
    }

    @Test
    void updateRejectsInvalidValuesBeforePersistence() {
        assertThatThrownBy(() -> service.update(
                "storage.quota.warning",
                "101",
                null,
                UUID.randomUUID()
        ))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("配置值不合法");
        assertThatThrownBy(() -> service.update(
                "weather.enabled",
                "yes",
                null,
                UUID.randomUUID()
        ))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("配置值不合法");
        assertThatThrownBy(() -> service.update(
                "storage.quota.default",
                "10.5",
                null,
                UUID.randomUUID()
        ))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("配置值不合法");
    }

    @Test
    void updateRejectsUserWithoutManagePermission() {
        when(currentUserContext.requireCurrentUser()).thenReturn(currentUser(Set.of(), Set.of(Roles.ADMIN)));

        assertThatThrownBy(() -> service.update(
                "share.enabled",
                "false",
                null,
                UUID.randomUUID()
        ))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("无权修改");
    }

    @Test
    void updateRejectsNonSuperAdminForRestrictedMediaConfig() {
        when(currentUserContext.requireCurrentUser()).thenReturn(currentUser(
                Set.of(Permissions.SYSTEM_CONFIG_MANAGE),
                Set.of(Roles.ADMIN)
        ));

        assertThatThrownBy(() -> service.update(
                "media.tmdb.enabled",
                "true",
                null,
                UUID.randomUUID()
        ))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("超级管理员");
    }

    @Test
    void initDefaultsDoesNotRewriteDeletedMasterSwitches() {
        ConfigEntry master = entry("music.platform.online.enabled", "false", "BOOLEAN", "music", "HOT");
        ConfigEntry netease = entry("music.platform.netease.enabled", "true", "BOOLEAN", "music", "HOT");
        when(configEntryRepository.findByConfigKey(ArgumentMatchers.anyString())).thenAnswer(invocation -> {
            String key = invocation.getArgument(0);
            return switch (key) {
                case "music.platform.online.enabled" -> Optional.of(master);
                case "music.platform.netease.enabled" -> Optional.of(netease);
                default -> Optional.empty();
            };
        });
        when(configEntryRepository.findAll()).thenReturn(List.of());
        when(configEntryRepository.save(any(ConfigEntry.class))).thenAnswer(invocation -> invocation.getArgument(0));

        stubCatalogLock();
        service.initializeCatalog();

        assertThat(master.getConfigValue()).isEqualTo("false");
        assertThat(netease.getConfigValue()).isEqualTo("true");
    }

    @Test
    void listHistoryReturnsHistoryForKey() {
        ConfigHistory h1 = history(UUID.randomUUID(), "share.max-bytes", "100", "120", "初始值");
        ConfigHistory h2 = history(UUID.randomUUID(), "share.max-bytes", "120", "180", "调整容量");
        when(configHistoryRepository.findByConfigKeyOrderByCreatedAtDesc(
                ArgumentMatchers.eq("share.max-bytes"),
                any()
        ))
                .thenReturn(List.of(h2, h1));

        var result = service.listHistory("share.max-bytes");

        assertThat(result).hasSize(2);
        assertThat(result.get(0).configKey()).isEqualTo("share.max-bytes");
        assertThat(result.get(0).oldValue()).isEqualTo("120");
        assertThat(result.get(0).newValue()).isEqualTo("180");
        assertThat(result.get(1).oldValue()).isEqualTo("100");
        ArgumentCaptor<Pageable> pageable = ArgumentCaptor.forClass(Pageable.class);
        verify(configHistoryRepository).findByConfigKeyOrderByCreatedAtDesc(
                ArgumentMatchers.eq("share.max-bytes"),
                pageable.capture()
        );
        assertThat(pageable.getValue().getPageSize()).isEqualTo(100);
    }

    @Test
    void listHistoryRejectsUnknownKey() {
        when(configHistoryRepository.findByConfigKeyOrderByCreatedAtDesc(
                ArgumentMatchers.eq("nonexistent.key"),
                any()
        ))
                .thenReturn(List.of());

        assertThatThrownBy(() -> service.listHistory("nonexistent.key"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不允许运行时编辑");
    }

    @Test
    void rollbackRestoresOldValueAndCreatesHistory() {
        UUID historyId = UUID.randomUUID();
        UUID changedBy = UUID.randomUUID();
        ConfigHistory historyRecord = history(historyId, "share.max-bytes", "100", "180", "调整容量");
        ConfigEntry entry = entry("share.max-bytes", "180", "NUMBER", "storage", "HOT");

        when(configHistoryRepository.findById(historyId)).thenReturn(Optional.of(historyRecord));
        when(configEntryRepository.findByConfigKey("share.max-bytes")).thenReturn(Optional.of(entry));
        when(configEntryRepository.save(any(ConfigEntry.class))).thenAnswer(invocation -> invocation.getArgument(0));

        var result = service.rollback(historyId, changedBy);

        assertThat(result.value()).isEqualTo("100");
        assertThat(entry.getConfigValue()).isEqualTo("100");
        verify(configHistoryRepository).save(any(ConfigHistory.class));
        verify(publisher).publishFanout(
                ArgumentMatchers.eq(QueueNames.CONFIG_REFRESH_EXCHANGE), any());
    }

    @Test
    void rollbackThrowsWhenHistoryNotFound() {
        UUID historyId = UUID.randomUUID();
        UUID changedBy = UUID.randomUUID();
        when(configHistoryRepository.findById(historyId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.rollback(historyId, changedBy))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("历史记录不存在");
    }

    @Test
    void rollbackThrowsWhenConfigEntryNotFound() {
        UUID historyId = UUID.randomUUID();
        UUID changedBy = UUID.randomUUID();
        ConfigHistory historyRecord = history(historyId, "share.max-bytes", "100", "120", "test");

        when(configHistoryRepository.findById(historyId)).thenReturn(Optional.of(historyRecord));
        when(configEntryRepository.findByConfigKey("share.max-bytes")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.rollback(historyId, changedBy))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("配置项不存在");
    }

    @Test
    void rollbackRejectsNonSuperAdminForRestrictedMediaConfig() {
        UUID historyId = UUID.randomUUID();
        ConfigHistory historyRecord = history(
                historyId,
                "media.tmdb.enabled",
                "false",
                "true",
                "启用 TMDB"
        );
        when(configHistoryRepository.findById(historyId)).thenReturn(Optional.of(historyRecord));
        when(currentUserContext.requireCurrentUser()).thenReturn(currentUser(
                Set.of(Permissions.SYSTEM_CONFIG_MANAGE),
                Set.of(Roles.ADMIN)
        ));

        assertThatThrownBy(() -> service.rollback(historyId, UUID.randomUUID()))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("超级管理员");
    }

    @Test
    void listHistoryMasksSensitiveValues() {
        ConfigEntry sensitiveEntry = entry(
                "media.tmdb.key",
                "sk-secret123",
                "STRING",
                "media",
                "HOT"
        );
        sensitiveEntry.setSensitive(true);
        ConfigHistory h1 = history(
                UUID.randomUUID(),
                "media.tmdb.key",
                "old-key",
                "new-key",
                "更换密钥"
        );
        when(configEntryRepository.findByConfigKey("media.tmdb.key"))
                .thenReturn(Optional.of(sensitiveEntry));
        when(configHistoryRepository.findByConfigKeyOrderByCreatedAtDesc(
                ArgumentMatchers.eq("media.tmdb.key"),
                any()
        ))
                .thenReturn(List.of(h1));

        var result = service.listHistory("media.tmdb.key");

        assertThat(result).hasSize(1);
        assertThat(result.get(0).oldValue()).isEqualTo("******");
        assertThat(result.get(0).newValue()).isEqualTo("******");
        assertThat(result.get(0).configKey()).isEqualTo("media.tmdb.key");
    }

    @Test
    void listHistoryDoesNotMaskNonSensitiveValues() {
        ConfigEntry nonSensitiveEntry = entry("share.max-bytes", "120", "NUMBER", "storage", "HOT");
        ConfigHistory h1 = history(UUID.randomUUID(), "share.max-bytes", "100", "120", "初始值");
        when(configEntryRepository.findByConfigKey("share.max-bytes"))
                .thenReturn(Optional.of(nonSensitiveEntry));
        when(configHistoryRepository.findByConfigKeyOrderByCreatedAtDesc(
                ArgumentMatchers.eq("share.max-bytes"),
                any()
        ))
                .thenReturn(List.of(h1));

        var result = service.listHistory("share.max-bytes");

        assertThat(result).hasSize(1);
        assertThat(result.get(0).oldValue()).isEqualTo("100");
        assertThat(result.get(0).newValue()).isEqualTo("120");
    }

    @Test
    void rollbackMasksSensitiveValueInResponse() {
        UUID historyId = UUID.randomUUID();
        UUID changedBy = UUID.randomUUID();
        ConfigHistory historyRecord = history(
                historyId,
                "media.tmdb.key",
                "old-key",
                "new-key",
                "更换密钥"
        );
        ConfigEntry sensitiveEntry = entry(
                "media.tmdb.key",
                "new-key",
                "STRING",
                "media",
                "HOT"
        );
        sensitiveEntry.setSensitive(true);

        when(configHistoryRepository.findById(historyId)).thenReturn(Optional.of(historyRecord));
        when(configEntryRepository.findByConfigKey("media.tmdb.key"))
                .thenReturn(Optional.of(sensitiveEntry));
        when(configEntryRepository.save(any(ConfigEntry.class))).thenAnswer(invocation -> invocation.getArgument(0));

        var result = service.rollback(historyId, changedBy);

        assertThat(result.value()).isNull();
    }

    @Test
    void updateSetsChangedByOnHistory() {
        ConfigEntry entry = entry("share.max-bytes", "120", "NUMBER", "storage", "HOT");
        UUID changedBy = UUID.randomUUID();
        when(configEntryRepository.findByConfigKey("share.max-bytes")).thenReturn(Optional.of(entry));
        when(configEntryRepository.save(any(ConfigEntry.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(configHistoryRepository.save(any(ConfigHistory.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.update("share.max-bytes", "180", "调整共享空间容量", changedBy);

        verify(configHistoryRepository).save(ArgumentMatchers.argThat(h ->
                h.getChangedBy() != null && h.getChangedBy().equals(changedBy)
        ));
    }

    @Test
    void updateEncryptsSensitiveValueBeforePersistence() {
        ConfigEntry sensitiveEntry = entry(
                "weather.qweather.key",
                "v1:old-iv:old-payload",
                "STRING",
                "weather",
                "HOT"
        );
        sensitiveEntry.setSensitive(true);
        UUID changedBy = UUID.randomUUID();
        when(configEntryRepository.findByConfigKey("weather.qweather.key"))
                .thenReturn(Optional.of(sensitiveEntry));
        when(credentialCipher.encrypt("new-private-key"))
                .thenReturn("v1:new-iv:new-payload");
        when(configEntryRepository.save(any(ConfigEntry.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = service.update(
                "weather.qweather.key",
                "new-private-key",
                "轮换天气服务私钥",
                changedBy
        );

        assertThat(result.value()).isNull();
        assertThat(sensitiveEntry.getConfigValue()).isEqualTo("v1:new-iv:new-payload");
        verify(configHistoryRepository).save(ArgumentMatchers.argThat(history ->
                "v1:new-iv:new-payload".equals(history.getNewValue())
                        && "v1:old-iv:old-payload".equals(history.getOldValue())
        ));
    }

    @Test
    void initDefaultsEncryptsLegacyHistoryWhenCurrentValueIsAlreadyEncrypted() {
        ConfigEntry sensitiveEntry = entry(
                "weather.qweather.key",
                "v1:Y3VycmVudC1pdg==:Y3VycmVudC1wYXlsb2Fk",
                "STRING",
                "weather",
                "HOT"
        );
        sensitiveEntry.setSensitive(true);
        ConfigHistory legacyHistory = history(
                UUID.randomUUID(),
                "weather.qweather.key",
                "legacy-old-key",
                "legacy-new-key",
                "历史密钥轮换"
        );
        when(configEntryRepository.save(any(ConfigEntry.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(configEntryRepository.findAll()).thenReturn(List.of(sensitiveEntry));
        when(configHistoryRepository.findByConfigKey("weather.qweather.key"))
                .thenReturn(List.of(legacyHistory));
        when(credentialCipher.encrypt("legacy-old-key"))
                .thenReturn("v1:old-iv:old-payload");
        when(credentialCipher.encrypt("legacy-new-key"))
                .thenReturn("v1:new-iv:new-payload");

        stubCatalogLock();
        service.initializeCatalog();

        assertThat(sensitiveEntry.getConfigValue())
                .isEqualTo("v1:Y3VycmVudC1pdg==:Y3VycmVudC1wYXlsb2Fk");
        assertThat(legacyHistory.getOldValue()).isEqualTo("v1:old-iv:old-payload");
        assertThat(legacyHistory.getNewValue()).isEqualTo("v1:new-iv:new-payload");
        verify(configHistoryRepository).saveAll(List.of(legacyHistory));
    }

    private ConfigEntry entry(String key, String value, String valueType, String category, String refreshScope) {
        ConfigEntry configEntry = new ConfigEntry();
        configEntry.setConfigKey(key);
        configEntry.setConfigValue(value);
        configEntry.setValueType(valueType);
        configEntry.setCategory(category);
        configEntry.setRefreshScope(refreshScope);
        configEntry.setUpdatedAt(Instant.parse("2026-05-20T10:00:00Z"));
        return configEntry;
    }

    private CurrentUser currentUser(Set<String> permissions, Set<String> roles) {
        return new CurrentUser(UUID.randomUUID(), "subject", "tester", permissions, roles);
    }

    private void stubCatalogLock() {
        when(configEntryRepository.findByConfigKeyForUpdate("media.import.enabled"))
                .thenReturn(Optional.of(entry(
                        "media.import.enabled",
                        "true",
                        "BOOLEAN",
                        "media",
                        "HOT"
                )));
    }

    private ConfigHistory history(UUID id, String key, String oldValue, String newValue, String reason) {
        ConfigHistory h = new ConfigHistory();
        h.setId(id);
        h.setConfigKey(key);
        h.setOldValue(oldValue);
        h.setNewValue(newValue);
        h.setChangeReason(reason);
        h.setCreatedAt(Instant.parse("2026-05-20T10:00:00Z"));
        return h;
    }
}
