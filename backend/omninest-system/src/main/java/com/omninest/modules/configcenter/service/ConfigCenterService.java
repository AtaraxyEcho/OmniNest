package com.omninest.modules.configcenter.service;

import com.omninest.common.config.ConfigRefreshEvent;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.config.RuntimeConfigCommand;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.DomainEventPublisher;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.security.CredentialCipher;
import com.omninest.common.security.CurrentUser;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.common.security.Roles;
import com.omninest.modules.configcenter.domain.ConfigDefinition;
import com.omninest.modules.configcenter.domain.ConfigDefinitionCatalog;
import com.omninest.modules.configcenter.domain.ConfigEntry;
import com.omninest.modules.configcenter.domain.ConfigHistory;
import com.omninest.modules.configcenter.domain.ConfigSurface;
import com.omninest.modules.configcenter.dto.ConfigEntryDto;
import com.omninest.modules.configcenter.dto.ConfigHistoryDto;
import com.omninest.modules.configcenter.repository.ConfigEntryRepository;
import com.omninest.modules.configcenter.repository.ConfigHistoryRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 配置中心应用服务。管理 API 只允许访问受控目录中的运行时配置。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ConfigCenterService implements RuntimeConfigCommand {
    private static final int DEFAULT_HISTORY_LIMIT = 100;
    private static final String SENSITIVE_MASK = "******";
    private static final String CATALOG_LOCK_KEY = "media.import.enabled";

    private final ConfigEntryRepository configEntryRepository;
    private final ConfigHistoryRepository configHistoryRepository;
    private final DomainEventPublisher publisher;
    private final CredentialCipher credentialCipher;
    private final CurrentUserContext currentUserContext;
    private final RuntimeConfigCache runtimeConfigCache;

    /**
     * 在 API 角色启动阶段同步配置目录及兼容数据。
     * 调用方必须通过 Spring 代理进入本方法，确保整个迁移位于同一事务内。
     */
    @Transactional(rollbackFor = Exception.class)
    public void initializeCatalog() {
        configEntryRepository.findByConfigKeyForUpdate(CATALOG_LOCK_KEY)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.CONFIG_NOT_FOUND,
                        "配置目录未初始化，请先执行配置目录升级脚本"
                ));
        List<ConfigEntry> existingEntries = configEntryRepository.findAll();
        Map<String, ConfigEntry> entriesByKey = existingEntries.stream()
                .collect(Collectors.toMap(
                        ConfigEntry::getConfigKey,
                        entry -> entry,
                        (left, right) -> left,
                        LinkedHashMap::new
                ));
        List<ConfigEntry> allEntries = new ArrayList<>(existingEntries);
        List<ConfigEntry> catalogEntries = new ArrayList<>();
        for (ConfigDefinition definition : ConfigDefinitionCatalog.definitions()) {
            ConfigEntry entry = entriesByKey.get(definition.key());
            if (entry == null) {
                entry = new ConfigEntry();
                entry.setConfigKey(definition.key());
                entry.setConfigValue(definition.defaultValue());
                entriesByKey.put(definition.key(), entry);
                allEntries.add(entry);
            }
            applyDefinitionMetadata(entry, definition);
            catalogEntries.add(entry);
        }
        configEntryRepository.saveAll(catalogEntries);
        encryptLegacySensitiveValues(allEntries);
    }

    @Transactional(readOnly = true)
    public List<ConfigEntryDto> list() {
        return list(null);
    }

    /**
     * 查询允许在管理界面展示的配置，可按界面归属过滤。
     *
     * @param surface 界面归属；null 表示 GENERAL 与 INTEGRATION
     * @return 受控配置列表
     */
    @Transactional(readOnly = true)
    public List<ConfigEntryDto> list(ConfigSurface surface) {
        return configEntryRepository.findAll(Sort.by(Sort.Direction.ASC, "configKey"))
                .stream()
                .map(entry -> ConfigDefinitionCatalog.find(entry.getConfigKey())
                        .map(definition -> new ConfigEntryWithDefinition(entry, definition))
                        .orElse(null))
                .filter(Objects::nonNull)
                .filter(item -> surface == null || item.definition().surface() == surface)
                .map(item -> toDto(item.entry(), item.definition()))
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public ConfigEntryDto update(String key, String value, String reason, UUID changedBy) {
        ConfigDefinition definition = requireEditable(key);
        requireWritePermission(definition);
        String normalized = normalize(definition, value);
        if (definition.sensitive() && SENSITIVE_MASK.equals(normalized)) {
            throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "敏感配置占位符不能作为新值保存");
        }
        ConfigEntry entry = configEntryRepository.findByConfigKey(key)
                .orElseThrow(() -> new BusinessException(ErrorCode.CONFIG_NOT_FOUND, "配置项不存在: " + key));
        String oldValue = entry.getConfigValue();
        String storedValue = definition.sensitive() && !normalized.isBlank()
                ? credentialCipher.encrypt(normalized)
                : normalized;
        entry.setConfigValue(storedValue);
        entry.setUpdatedBy(changedBy);
        applyDefinitionMetadata(entry, definition);
        ConfigEntry saved = configEntryRepository.save(entry);
        configHistoryRepository.save(history(key, oldValue, storedValue, reason, changedBy));
        evictAndPublishAfterCommit(key);
        return toDto(saved, definition);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void updateValue(String key, String value, String reason, UUID changedBy) {
        update(key, value, reason, changedBy);
    }

    /**
     * 内部播种已存在的配置行并逐出运行期缓存。
     *
     * <p>供首次安装等没有认证上下文的内部流程使用：不经管理 API 的权限校验，
     * 不写变更历史，也不发布配置刷新事件；配置行不存在时不创建。</p>
     *
     * @param configKey 配置键
     * @param value 待写入的配置值
     */
    @Transactional(rollbackFor = Exception.class)
    public void seedSystemConfigValue(String configKey, String value) {
        configEntryRepository.findByConfigKey(configKey)
                .ifPresent(entry -> {
                    entry.setConfigValue(value);
                    configEntryRepository.save(entry);
                });
        // 播种不广播刷新事件（安装期 worker/scheduler 尚未启动），但必须等提交后再逐出，
        // 否则并发读可能把旧值回填进缓存。
        evictAfterCommit(configKey);
    }

    /**
     * 查询配置键的审计上下文：是否敏感以及当前存储值。
     *
     * <p>供管理审计构建 detail_payload：敏感配置的旧值与新值必须以
     * {@link ConfigHistoryDto#MASK} 呈现，禁止明文或密文进入审计载荷。</p>
     *
     * @param key 配置键
     * @return 审计上下文；配置项不存在时 oldValue 为 null
     */
    @Transactional(readOnly = true)
    public ConfigAuditContext auditContext(String key) {
        boolean sensitive = ConfigDefinitionCatalog.find(key)
                .map(ConfigDefinition::sensitive)
                .orElse(false);
        String oldValue = configEntryRepository.findByConfigKey(key)
                .map(ConfigEntry::getConfigValue)
                .orElse(null);
        return new ConfigAuditContext(sensitive, oldValue);
    }

    /**
     * 配置审计上下文。
     *
     * @param sensitive 配置是否敏感，敏感时任何值都必须掩码后进入审计载荷
     * @param oldValue 当前存储值（敏感配置为密文，不得直接展示）
     */
    public record ConfigAuditContext(boolean sensitive, String oldValue) {
    }

    @Transactional(readOnly = true)
    public List<ConfigHistoryDto> listHistory(String configKey) {
        ConfigDefinition definition = requireEditable(configKey);
        return configHistoryRepository.findByConfigKeyOrderByCreatedAtDesc(
                        configKey,
                        PageRequest.of(0, DEFAULT_HISTORY_LIMIT)
                )
                .stream()
                .map(history -> ConfigHistoryDto.from(history, definition.sensitive()))
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public ConfigEntryDto rollback(UUID historyId, UUID changedBy) {
        ConfigHistory historyRecord = configHistoryRepository.findById(historyId)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.NOT_FOUND,
                        "历史记录不存在: " + historyId
                ));
        String configKey = historyRecord.getConfigKey();
        ConfigDefinition definition = requireEditable(configKey);
        requireWritePermission(definition);
        ConfigEntry entry = configEntryRepository.findByConfigKey(configKey)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.CONFIG_NOT_FOUND,
                        "配置项不存在: " + configKey
                ));
        String currentValue = entry.getConfigValue();
        String rollbackValue = normalizeHistoryValue(definition, historyRecord.getOldValue());
        entry.setConfigValue(rollbackValue);
        entry.setUpdatedBy(changedBy);
        applyDefinitionMetadata(entry, definition);
        ConfigEntry saved = configEntryRepository.save(entry);
        configHistoryRepository.save(history(
                configKey,
                currentValue,
                rollbackValue,
                "回滚至历史记录 " + historyId,
                changedBy
        ));
        evictAndPublishAfterCommit(configKey);
        log.info("配置回滚成功: key={}, historyId={}", configKey, historyId);
        return toDto(saved, definition);
    }

    @Transactional(readOnly = true)
    public String getConfigKeyByHistoryId(UUID historyId) {
        return configHistoryRepository.findById(historyId)
                .map(ConfigHistory::getConfigKey)
                .orElseThrow(() -> new BusinessException(
                        ErrorCode.NOT_FOUND,
                        "历史记录不存在: " + historyId
                ));
    }

    private ConfigDefinition requireEditable(String key) {
        return ConfigDefinitionCatalog.find(key)
                .orElseThrow(() -> {
                    ErrorCode code = ConfigDefinitionCatalog.isKnownHidden(key)
                            ? ErrorCode.CONFIG_VALUE_INVALID
                            : ErrorCode.CONFIG_NOT_FOUND;
                    return new BusinessException(code, "配置项不允许运行时编辑: " + key);
                });
    }

    private void requireWritePermission(ConfigDefinition definition) {
        CurrentUser currentUser = currentUserContext.requireCurrentUser();
        if (currentUser.permissions() == null
                || !currentUser.permissions().contains(Permissions.SYSTEM_CONFIG_MANAGE)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "当前用户无权修改系统配置");
        }
        if (definition.superAdminOnly()
                && (currentUser.roles() == null || !currentUser.roles().contains(Roles.SUPER_ADMIN))) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "该配置仅允许超级管理员修改");
        }
    }

    private String normalize(ConfigDefinition definition, String value) {
        try {
            return definition.normalize(value);
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(
                    ErrorCode.CONFIG_VALUE_INVALID,
                    "配置值不合法: " + definition.key()
            );
        }
    }

    private String normalizeHistoryValue(ConfigDefinition definition, String storedValue) {
        if (!definition.sensitive()) {
            return normalize(definition, storedValue);
        }
        if (storedValue == null || storedValue.isBlank()) {
            return "";
        }
        String plaintext = isEncryptedValue(storedValue) ? credentialCipher.decrypt(storedValue) : storedValue;
        String normalized = normalize(definition, plaintext);
        return normalized.isBlank() ? "" : credentialCipher.encrypt(normalized);
    }

    private void applyDefinitionMetadata(ConfigEntry entry, ConfigDefinition definition) {
        entry.setValueType(definition.valueType().getValue());
        entry.setCategory(definition.category());
        entry.setRefreshScope(definition.refreshScope().getValue());
        entry.setDescription(definition.description());
        entry.setSensitive(definition.sensitive());
    }

    private void encryptLegacySensitiveValues(List<ConfigEntry> entries) {
        List<ConfigEntry> sensitiveEntries = entries.stream()
                .filter(ConfigEntry::isSensitive)
                .toList();
        if (sensitiveEntries.isEmpty()) {
            return;
        }
        Set<String> sensitiveKeys = sensitiveEntries.stream()
                .map(ConfigEntry::getConfigKey)
                .collect(Collectors.toSet());
        Map<String, List<ConfigHistory>> historiesByKey = configHistoryRepository
                .findByConfigKeyIn(sensitiveKeys)
                .stream()
                .collect(Collectors.groupingBy(ConfigHistory::getConfigKey));
        List<ConfigEntry> entriesToSave = new ArrayList<>();
        for (ConfigEntry entry : sensitiveEntries) {
            boolean migratedCurrentValue = hasPlaintextValue(entry.getConfigValue());
            if (migratedCurrentValue) {
                entry.setConfigValue(credentialCipher.encrypt(entry.getConfigValue()));
                entriesToSave.add(entry);
            }
            List<ConfigHistory> histories = historiesByKey.getOrDefault(entry.getConfigKey(), List.of());
            boolean historyChanged = false;
            for (ConfigHistory history : histories) {
                if (hasPlaintextValue(history.getOldValue())) {
                    history.setOldValue(credentialCipher.encrypt(history.getOldValue()));
                    historyChanged = true;
                }
                if (hasPlaintextValue(history.getNewValue())) {
                    history.setNewValue(credentialCipher.encrypt(history.getNewValue()));
                    historyChanged = true;
                }
            }
            if (historyChanged) {
                configHistoryRepository.saveAll(histories);
            }
            if (migratedCurrentValue) {
                log.info("已迁移敏感配置为密文存储: key={}", entry.getConfigKey());
            }
        }
        if (!entriesToSave.isEmpty()) {
            configEntryRepository.saveAll(entriesToSave);
        }
    }

    private boolean hasPlaintextValue(String value) {
        return value != null && !value.isBlank() && !isEncryptedValue(value);
    }

    private boolean isEncryptedValue(String value) {
        return value.matches("v\\d+:[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+");
    }

    private ConfigHistory history(String key, String oldValue, String newValue, String reason, UUID changedBy) {
        ConfigHistory configHistory = new ConfigHistory();
        configHistory.setConfigKey(key);
        configHistory.setOldValue(oldValue);
        configHistory.setNewValue(newValue);
        configHistory.setChangeReason(reason);
        configHistory.setChangedBy(changedBy);
        return configHistory;
    }

    /**
     * 广播配置刷新。
     *
     * <p>必须等数据库事务提交后再发：在事务体内广播时，其他节点的消费者会立刻清缓存并
     * 回查数据库，读到提交前的旧值再写回共享缓存，配置看似已改却在各节点上停留在旧值，
     * 直到下一次失效才自愈。无事务同步（如内置目录初始化）时按原样直接发送。</p>
     */
    private void evictAndPublishAfterCommit(String key) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    runtimeConfigCache.evict(key);
                    // afterCommit 派发时事务同步仍然活跃，此处若再注册新的同步，其 afterCommit
                    // 回调不会进入本轮快照，广播会被静默丢弃；提交已发生，直接发布。
                    publishRefreshEvent(key);
                }
            });
            return;
        }
        runtimeConfigCache.evict(key);
        publishRefreshEvent(key);
    }

    private void evictAfterCommit(String key) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    runtimeConfigCache.evict(key);
                }
            });
            return;
        }
        runtimeConfigCache.evict(key);
    }

    private void publishRefreshEvent(String key) {
        publisher.publishFanout(
                QueueNames.CONFIG_REFRESH_EXCHANGE,
                new ConfigRefreshEvent(UUID.randomUUID(), key, Instant.now())
        );
    }

    private ConfigEntryDto toDto(ConfigEntry entry, ConfigDefinition definition) {
        boolean sensitiveConfigured = definition.sensitive()
                && entry.getConfigValue() != null
                && !entry.getConfigValue().isBlank();
        return new ConfigEntryDto(
                entry.getConfigKey(),
                definition.sensitive() ? null : entry.getConfigValue(),
                definition.valueType().getValue(),
                definition.category(),
                definition.refreshScope().getValue(),
                entry.getUpdatedAt(),
                definition.description(),
                definition.surface().name(),
                definition.displayCode(),
                true,
                sensitiveConfigured,
                definition.allowedValues()
        );
    }

    private record ConfigEntryWithDefinition(ConfigEntry entry, ConfigDefinition definition) {
    }
}
