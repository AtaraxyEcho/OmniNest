package com.omninest.modules.configcenter.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.modules.configcenter.domain.ConfigSurface;
import com.omninest.modules.configcenter.service.ConfigCenterService;
import com.omninest.common.security.FreshAdminActorVerifier;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * 配置中心管理接口契约测试。
 */
class ConfigCenterControllerTest {
    private final ConfigCenterService configCenterService = mock(ConfigCenterService.class);
    private final CurrentUserContext currentUserContext = mock(CurrentUserContext.class);
    private final FreshAdminActorVerifier adminActorGuard = mock(FreshAdminActorVerifier.class);
    private final AdminAuditRecorder adminAuditRecorder = mock(AdminAuditRecorder.class);
    private final ConfigCenterController controller = new ConfigCenterController(
            configCenterService,
            currentUserContext,
            adminActorGuard,
            adminAuditRecorder
    );

    @Test
    void delegatesSurfaceFilterToControlledCatalogService() {
        when(configCenterService.list(ConfigSurface.GENERAL)).thenReturn(List.of());

        controller.list(ConfigSurface.GENERAL);

        verify(configCenterService).list(ConfigSurface.GENERAL);
    }

    @Test
    void rejectsMissingOrOversizedUpdateValues() {
        try (var factory = Validation.buildDefaultValidatorFactory()) {
            Validator validator = factory.getValidator();

            assertThat(validator.validate(new ConfigCenterController.UpdateConfigRequest(null, null)))
                    .isNotEmpty();
            assertThat(validator.validate(new ConfigCenterController.UpdateConfigRequest(
                    "x".repeat(8193),
                    "x".repeat(501)
            )))
                    .hasSize(2);
        }
    }
}
