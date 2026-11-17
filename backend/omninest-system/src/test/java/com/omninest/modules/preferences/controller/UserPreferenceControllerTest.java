package com.omninest.modules.preferences.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.modules.preferences.dto.UserPreferenceDtos.UserPreferenceDto;
import com.omninest.modules.preferences.dto.UserPreferenceDtos.UserPreferencePatchRequest;
import com.omninest.modules.preferences.service.UserPreferenceService;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 验证用户偏好控制器的身份边界和请求参数传递。
 *
 * @author Notask Flow Team
 */
class UserPreferenceControllerTest {
    private final CurrentUserContext currentUserContext = Mockito.mock(CurrentUserContext.class);
    private final UserPreferenceService userPreferenceService = Mockito.mock(UserPreferenceService.class);
    private final UserPreferenceController controller = new UserPreferenceController(
            currentUserContext,
            userPreferenceService
    );

    @Test
    void get_usesAuthenticatedUserAndReturnsServicePayload() {
        UUID userId = UUID.randomUUID();
        UserPreferenceDto preference = preference("appearance.v1", Map.of("themeMode", "dark"), 3L);
        Mockito.when(currentUserContext.requireCurrentUserId()).thenReturn(userId);
        Mockito.when(userPreferenceService.get(userId, "appearance.v1")).thenReturn(preference);

        ApiResponse<UserPreferenceDto> response = controller.get("appearance.v1");

        Assertions.assertThat(response.getData()).isSameAs(preference);
        Mockito.verify(currentUserContext).requireCurrentUserId();
        Mockito.verify(userPreferenceService).get(userId, "appearance.v1");
    }

    @Test
    void patch_usesAuthenticatedUserAndForwardsVersionedMutation() {
        UUID userId = UUID.randomUUID();
        UserPreferencePatchRequest request = new UserPreferencePatchRequest(
                2L,
                Map.of("themeMode", "system"),
                List.of("legacy")
        );
        UserPreferenceDto preference = preference("appearance.v1", request.changes(), 3L);
        Mockito.when(currentUserContext.requireCurrentUserId()).thenReturn(userId);
        Mockito.when(userPreferenceService.patch(userId, "appearance.v1", request)).thenReturn(preference);

        ApiResponse<UserPreferenceDto> response = controller.patch("appearance.v1", request);

        Assertions.assertThat(response.getData()).isSameAs(preference);
        Mockito.verify(userPreferenceService).patch(userId, "appearance.v1", request);
    }

    @Test
    void delete_usesAuthenticatedUserAndForwardsBaseVersion() {
        UUID userId = UUID.randomUUID();
        Mockito.when(currentUserContext.requireCurrentUserId()).thenReturn(userId);

        ApiResponse<Void> response = controller.delete("appearance.v1", 7L);

        Assertions.assertThat(response.getData()).isNull();
        Mockito.verify(userPreferenceService).delete(userId, "appearance.v1", 7L);
    }

    private UserPreferenceDto preference(String scope, Map<String, Object> values, Long version) {
        Instant now = Instant.parse("2026-07-15T00:00:00Z");
        return new UserPreferenceDto(scope, values, now, now, version);
    }
}
