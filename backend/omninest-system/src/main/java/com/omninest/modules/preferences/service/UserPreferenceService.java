package com.omninest.modules.preferences.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.preferences.UserPreferenceQuery;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.preferences.domain.UserPreference;
import com.omninest.modules.preferences.dto.UserPreferenceDtos.UserPreferenceDto;
import com.omninest.modules.preferences.dto.UserPreferenceDtos.UserPreferencePatchRequest;
import com.omninest.modules.preferences.repository.UserPreferenceRepository;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;

/**
 * 用户偏好设置服务，支持按 scope 读取和更新。
 *
 * @author Notask Flow Team
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class UserPreferenceService implements UserPreferenceQuery {
    private static final int MAX_SCOPE_LENGTH = 32;
    private static final int MAX_PREFERENCES_TEXT_LENGTH = 16 * 1024;
    private static final String SCOPE_PATTERN = "[a-z][a-z0-9._-]*";

    private final UserPreferenceRepository userPreferenceRepository;
    private final ObjectMapper objectMapper;
    private final UserSyncEventRecorder syncEventRecorder;

    /**
     * 读取指定作用域的偏好设置，不存在时返回空配置。
     *
     * @param ownerUserId 用户 ID
     * @param scope 作用域
     * @return 偏好设置
     */
    @Transactional(readOnly = true)
    public UserPreferenceDto get(UUID ownerUserId, String scope) {
        String normalizedScope = normalizeScope(scope);
        return userPreferenceRepository.findByOwnerUserIdAndScope(ownerUserId, normalizedScope)
                .map(this::toDto)
                .orElse(new UserPreferenceDto(normalizedScope, Map.of(), null, null, null));
    }

    /**
     * 查询指定作用域的不可变偏好值。
     *
     * @param ownerUserId 用户标识
     * @param scope 偏好作用域
     * @return 不可变偏好值
     */
    @Override
    @Transactional(readOnly = true)
    public Map<String, Object> findValues(UUID ownerUserId, String scope) {
        return get(ownerUserId, scope).preferences();
    }

    /**
     * 按客户端读取版本增量更新用户偏好。
     *
     * @param ownerUserId 用户 ID
     * @param scope 偏好作用域
     * @param request 增量更新请求
     * @return 更新后的用户偏好
     */
    @Transactional(rollbackFor = Exception.class)
    public UserPreferenceDto patch(UUID ownerUserId, String scope, UserPreferencePatchRequest request) {
        String normalizedScope = normalizeScope(scope);
        Map<String, Object> changes = request.changes() == null
                ? new LinkedHashMap<>()
                : new LinkedHashMap<>(request.changes());
        List<String> removeKeys = request.removeKeys() == null ? List.of() : List.copyOf(request.removeKeys());
        validatePreferenceKeys(changes, removeKeys);

        UserPreference preference = userPreferenceRepository.findByOwnerUserIdAndScope(ownerUserId, normalizedScope)
                .orElse(null);
        if (preference == null) {
            return createPreference(ownerUserId, normalizedScope, request.baseVersion(), changes, removeKeys);
        }
        verifyVersion(normalizedScope, request.baseVersion(), preference.getVersion());

        Map<String, Object> merged = new LinkedHashMap<>(preference.getPreferences());
        merged.putAll(changes);
        removeKeys.forEach(merged::remove);
        validatePreferencesSize(merged);
        preference.setPreferences(merged);
        try {
            UserPreference saved = userPreferenceRepository.saveAndFlush(preference);
            recordEvent(ownerUserId, normalizedScope, SyncAction.UPDATED, saved.getVersion());
            log.debug("用户偏好已增量更新: userId={}, scope={}, version={}",
                    ownerUserId, normalizedScope, saved.getVersion());
            return toDto(saved);
        } catch (ObjectOptimisticLockingFailureException exception) {
            throw versionConflict(normalizedScope, null, exception);
        }
    }

    /**
     * 按版本删除用户偏好。
     *
     * @param ownerUserId 用户 ID
     * @param scope 偏好作用域
     * @param baseVersion 客户端读取到的版本
     */
    @Transactional(rollbackFor = Exception.class)
    public void delete(UUID ownerUserId, String scope, Long baseVersion) {
        String normalizedScope = normalizeScope(scope);
        UserPreference preference = userPreferenceRepository.findByOwnerUserIdAndScope(ownerUserId, normalizedScope)
                .orElse(null);
        if (preference == null) {
            return;
        }
        verifyVersion(normalizedScope, baseVersion, preference.getVersion());
        try {
            userPreferenceRepository.delete(preference);
            userPreferenceRepository.flush();
            recordEvent(ownerUserId, normalizedScope, SyncAction.DELETED, preference.getVersion());
            log.debug("用户偏好已删除: userId={}, scope={}", ownerUserId, normalizedScope);
        } catch (ObjectOptimisticLockingFailureException exception) {
            throw versionConflict(normalizedScope, null, exception);
        }
    }

    private String normalizeScope(String scope) {
        String normalizedScope = scope == null ? "" : scope.trim();
        if (normalizedScope.isBlank()
                || normalizedScope.length() > MAX_SCOPE_LENGTH
                || !normalizedScope.matches(SCOPE_PATTERN)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "偏好作用域不合法");
        }
        return normalizedScope;
    }

    private void validatePreferencesSize(Map<String, Object> preferences) {
        if (objectMapper.writeValueAsBytes(preferences).length > MAX_PREFERENCES_TEXT_LENGTH) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "偏好设置内容过大");
        }
    }

    private void validatePreferenceKeys(Map<String, Object> changes, List<String> removeKeys) {
        boolean invalidChangeKey = changes.keySet().stream().anyMatch(this::isInvalidPreferenceKey);
        boolean invalidRemoveKey = removeKeys.stream().anyMatch(this::isInvalidPreferenceKey);
        if (invalidChangeKey || invalidRemoveKey) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "偏好键不合法");
        }
    }

    private boolean isInvalidPreferenceKey(String key) {
        return key == null || key.isBlank() || key.length() > 128;
    }

    private UserPreferenceDto createPreference(
            UUID ownerUserId,
            String scope,
            Long baseVersion,
            Map<String, Object> changes,
            List<String> removeKeys
    ) {
        if (baseVersion != null) {
            throw versionConflict(scope, null, null);
        }
        Map<String, Object> preferences = new LinkedHashMap<>(changes);
        removeKeys.forEach(preferences::remove);
        validatePreferencesSize(preferences);
        UserPreference preference = new UserPreference();
        preference.setOwnerUserId(ownerUserId);
        preference.setScope(scope);
        preference.setPreferences(preferences);
        try {
            UserPreference saved = userPreferenceRepository.saveAndFlush(preference);
            recordEvent(ownerUserId, scope, SyncAction.CREATED, saved.getVersion());
            return toDto(saved);
        } catch (DataIntegrityViolationException exception) {
            throw versionConflict(scope, null, exception);
        }
    }

    private void verifyVersion(String scope, Long baseVersion, Long currentVersion) {
        if (baseVersion == null || !baseVersion.equals(currentVersion)) {
            throw versionConflict(scope, currentVersion, null);
        }
    }

    private BusinessException versionConflict(String scope, Long currentVersion, Exception cause) {
        Map<String, Object> details = new LinkedHashMap<>();
        details.put("scope", scope);
        details.put("currentVersion", currentVersion);
        BusinessException exception = new BusinessException(
                ErrorCode.PREFERENCE_VERSION_CONFLICT,
                "用户偏好已在其他位置更新，请刷新后重试",
                details
        );
        if (cause != null) {
            exception.initCause(cause);
        }
        return exception;
    }

    private UserPreferenceDto toDto(UserPreference preference) {
        return new UserPreferenceDto(
                preference.getScope(),
                Collections.unmodifiableMap(new LinkedHashMap<>(preference.getPreferences())),
                preference.getCreatedAt(),
                preference.getUpdatedAt(),
                preference.getVersion()
        );
    }

    private void recordEvent(UUID ownerUserId, String scope, SyncAction action, Long version) {
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId,
                SyncScope.PREFERENCES,
                "USER_PREFERENCE",
                scope,
                action,
                version,
                Map.of("scope", scope)
        ));
    }

    /**
     * 管理端账户删除配套：物理清空该用户全部偏好记录。
     *
     * @param ownerUserId 用户标识
     */
    @Transactional(rollbackFor = Exception.class)
    public void adminPurgeForUser(UUID ownerUserId) {
        userPreferenceRepository.deleteByOwnerUserId(ownerUserId);
    }
}
