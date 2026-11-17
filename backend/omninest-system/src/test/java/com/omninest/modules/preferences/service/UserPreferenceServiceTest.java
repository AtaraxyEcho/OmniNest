package com.omninest.modules.preferences.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.preferences.domain.UserPreference;
import com.omninest.modules.preferences.dto.UserPreferenceDtos.UserPreferenceDto;
import com.omninest.modules.preferences.dto.UserPreferenceDtos.UserPreferencePatchRequest;
import com.omninest.modules.preferences.repository.UserPreferenceRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.dao.DataIntegrityViolationException;
import tools.jackson.databind.ObjectMapper;

/**
 * 用户偏好读取、增量更新与并发校验测试。
 *
 * @author Notask Flow Team
 */
class UserPreferenceServiceTest {
    private final UserPreferenceRepository repository = Mockito.mock(UserPreferenceRepository.class);
    private final UserSyncEventRecorder syncEventRecorder = Mockito.mock(UserSyncEventRecorder.class);
    private final UserPreferenceService service = new UserPreferenceService(
            repository,
            new ObjectMapper(),
            syncEventRecorder
    );

    @Test
    void get_missingPreference_returnsVersionedEmptySnapshot() {
        UUID userId = UUID.randomUUID();
        Mockito.when(repository.findByOwnerUserIdAndScope(userId, "appearance.v1"))
                .thenReturn(Optional.empty());

        UserPreferenceDto result = service.get(userId, "appearance.v1");

        Assertions.assertThat(result.scope()).isEqualTo("appearance.v1");
        Assertions.assertThat(result.preferences()).isEmpty();
        Assertions.assertThat(result.version()).isNull();
    }

    @Test
    void findValues_returnsPublicPreferenceMap() {
        UUID userId = UUID.randomUUID();
        UserPreference preference = preference(
                userId,
                "weather",
                1L,
                Map.of("location", "北京")
        );
        Mockito.when(repository.findByOwnerUserIdAndScope(userId, "weather"))
                .thenReturn(Optional.of(preference));

        Map<String, Object> result = service.findValues(userId, "weather");

        Assertions.assertThat(result).containsExactlyEntriesOf(Map.of("location", "北京"));
    }

    @Test
    void patch_hierarchicalScope_acceptsDots() {
        UUID userId = UUID.randomUUID();
        Mockito.when(repository.findByOwnerUserIdAndScope(userId, "music.player.visual.v1"))
                .thenReturn(Optional.empty());
        Mockito.when(repository.saveAndFlush(Mockito.any(UserPreference.class)))
                .thenAnswer(invocation -> persisted(invocation.getArgument(0), 0L));

        UserPreferenceDto result = service.patch(
                userId,
                "music.player.visual.v1",
                new UserPreferencePatchRequest(null, Map.of("schemaVersion", 3), List.of())
        );

        Assertions.assertThat(result.scope()).isEqualTo("music.player.visual.v1");
        ArgumentCaptor<UserPreference> captor = ArgumentCaptor.forClass(UserPreference.class);
        Mockito.verify(repository).saveAndFlush(captor.capture());
        Assertions.assertThat(captor.getValue().getScope()).isEqualTo("music.player.visual.v1");
        ArgumentCaptor<SyncEventCommand> eventCaptor = ArgumentCaptor.forClass(SyncEventCommand.class);
        Mockito.verify(syncEventRecorder).record(eventCaptor.capture());
        Assertions.assertThat(eventCaptor.getValue().scope()).isEqualTo(SyncScope.PREFERENCES);
        Assertions.assertThat(eventCaptor.getValue().action()).isEqualTo(SyncAction.CREATED);
        Assertions.assertThat(eventCaptor.getValue().resourceId()).isEqualTo("music.player.visual.v1");
    }

    @Test
    void patch_existingPreference_mergesChangesAndRemovesExplicitKeys() {
        UUID userId = UUID.randomUUID();
        UserPreference preference = preference(userId, "appearance.v1", 3L, Map.of(
                "themeMode", "light",
                "legacy", true
        ));
        Mockito.when(repository.findByOwnerUserIdAndScope(userId, "appearance.v1"))
                .thenReturn(Optional.of(preference));
        Mockito.when(repository.saveAndFlush(preference))
                .thenAnswer(invocation -> persisted(invocation.getArgument(0), 4L));

        UserPreferenceDto result = service.patch(
                userId,
                "appearance.v1",
                new UserPreferencePatchRequest(3L, Map.of("themeMode", "dark"), List.of("legacy"))
        );

        Assertions.assertThat(result.preferences()).containsExactlyEntriesOf(Map.of("themeMode", "dark"));
        Assertions.assertThat(result.version()).isEqualTo(4L);
    }

    @Test
    void patch_staleVersion_returnsStableConflict() {
        UUID userId = UUID.randomUUID();
        UserPreference preference = preference(userId, "appearance.v1", 5L, Map.of("themeMode", "dark"));
        Mockito.when(repository.findByOwnerUserIdAndScope(userId, "appearance.v1"))
                .thenReturn(Optional.of(preference));

        Assertions.assertThatThrownBy(() -> service.patch(
                userId,
                "appearance.v1",
                new UserPreferencePatchRequest(4L, Map.of("themeMode", "light"), List.of())
        )).isInstanceOfSatisfying(BusinessException.class, exception -> {
            Assertions.assertThat(exception.errorCode()).isEqualTo(ErrorCode.PREFERENCE_VERSION_CONFLICT);
            Assertions.assertThat(exception.details()).containsEntry("currentVersion", 5L);
        });
    }

    @Test
    void patch_simultaneousFirstCreate_mapsUniqueConflict() {
        UUID userId = UUID.randomUUID();
        Mockito.when(repository.findByOwnerUserIdAndScope(userId, "appearance.v1"))
                .thenReturn(Optional.empty());
        Mockito.when(repository.saveAndFlush(Mockito.any(UserPreference.class)))
                .thenThrow(new DataIntegrityViolationException("duplicate scope"));

        Assertions.assertThatThrownBy(() -> service.patch(
                userId,
                "appearance.v1",
                new UserPreferencePatchRequest(null, Map.of("themeMode", "system"), List.of())
        )).isInstanceOfSatisfying(BusinessException.class, exception ->
                Assertions.assertThat(exception.errorCode()).isEqualTo(ErrorCode.PREFERENCE_VERSION_CONFLICT));
    }

    @Test
    void patch_missingPreferenceWithBaseVersion_rejectsCreate() {
        UUID userId = UUID.randomUUID();
        Mockito.when(repository.findByOwnerUserIdAndScope(userId, "appearance.v1"))
                .thenReturn(Optional.empty());

        Assertions.assertThatThrownBy(() -> service.patch(
                userId,
                "appearance.v1",
                new UserPreferencePatchRequest(2L, Map.of("themeMode", "dark"), List.of())
        )).isInstanceOfSatisfying(BusinessException.class, exception ->
                Assertions.assertThat(exception.errorCode()).isEqualTo(ErrorCode.PREFERENCE_VERSION_CONFLICT));
    }

    @Test
    void delete_matchingVersion_removesPreference() {
        UUID userId = UUID.randomUUID();
        UserPreference preference = preference(userId, "appearance.v1", 2L, Map.of());
        Mockito.when(repository.findByOwnerUserIdAndScope(userId, "appearance.v1"))
                .thenReturn(Optional.of(preference));

        service.delete(userId, "appearance.v1", 2L);

        Mockito.verify(repository).delete(preference);
        Mockito.verify(repository).flush();
    }

    @Test
    void patch_pathLikeScope_rejectsSlash() {
        UUID userId = UUID.randomUUID();

        Assertions.assertThatThrownBy(() -> service.patch(
                userId,
                "music/player",
                new UserPreferencePatchRequest(null, Map.of(), List.of())
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("偏好作用域不合法");
    }

    @Test
    void patch_oversizedSerializedPayload_rejectsRequest() {
        UUID userId = UUID.randomUUID();
        Mockito.when(repository.findByOwnerUserIdAndScope(userId, "appearance.v1"))
                .thenReturn(Optional.empty());

        Assertions.assertThatThrownBy(() -> service.patch(
                userId,
                "appearance.v1",
                new UserPreferencePatchRequest(null, Map.of("value", "x".repeat(17 * 1024)), List.of())
        )).isInstanceOf(BusinessException.class)
                .hasMessageContaining("偏好设置内容过大");
    }

    private UserPreference preference(UUID userId, String scope, Long version, Map<String, Object> values) {
        UserPreference preference = new UserPreference();
        preference.setId(UUID.randomUUID());
        preference.setOwnerUserId(userId);
        preference.setScope(scope);
        preference.setPreferences(values);
        preference.setCreatedAt(Instant.parse("2026-01-01T00:00:00Z"));
        preference.setUpdatedAt(Instant.parse("2026-01-01T00:00:00Z"));
        preference.setVersion(version);
        return preference;
    }

    private UserPreference persisted(UserPreference preference, Long version) {
        Instant now = Instant.parse("2026-01-02T00:00:00Z");
        if (preference.getId() == null) {
            preference.setId(UUID.randomUUID());
        }
        if (preference.getCreatedAt() == null) {
            preference.setCreatedAt(now);
        }
        preference.setUpdatedAt(now);
        preference.setVersion(version);
        return preference;
    }
}
