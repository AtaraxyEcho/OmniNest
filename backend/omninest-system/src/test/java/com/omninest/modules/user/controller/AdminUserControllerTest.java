package com.omninest.modules.user.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.user.service.AdminUserDeletionService;
import com.omninest.modules.user.service.AdminUserService;
import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.data.domain.Page;
import org.springframework.security.access.prepost.PreAuthorize;

/**
 * 管理端用户接口契约测试：锁定搜索过滤参数透传与删除端点权限。
 */
class AdminUserControllerTest {
    private final AdminUserService adminUserService = Mockito.mock(AdminUserService.class);
    private final AdminUserDeletionService adminUserDeletionService =
            Mockito.mock(AdminUserDeletionService.class);
    private final AdminUserController controller = new AdminUserController(
            adminUserService, adminUserDeletionService);

    @Test
    void listUsersDelegatesSearchAndRoleFilters() {
        when(adminUserService.listUsers(1, 25, "alice", "MEMBER", "username", "asc")).thenReturn(Page.empty());

        controller.listUsers(1, 25, "alice", "MEMBER", "username", "asc");

        verify(adminUserService).listUsers(1, 25, "alice", "MEMBER", "username", "asc");
    }

    @Test
    void deleteUserDelegatesToDeletionService() {
        UUID userId = UUID.fromString("10000000-0000-0000-0000-000000000001");

        controller.deleteUser(userId);

        verify(adminUserDeletionService).deleteUser(userId);
    }

    @Test
    void userEndpointsUseExpectedPermissionCodes() {
        assertThat(preAuthorizeOf("listUsers")).contains("system:user:read");
        assertThat(preAuthorizeOf("createUser")).contains("system:user:manage");
        assertThat(preAuthorizeOf("updateUserStatus")).contains("system:user:manage");
        assertThat(preAuthorizeOf("updateUserRoles")).contains("system:user:manage");
        assertThat(preAuthorizeOf("deleteUser")).contains("system:user:manage");
    }

    private String preAuthorizeOf(String methodName) {
        Method method = Arrays.stream(AdminUserController.class.getDeclaredMethods())
                .filter(candidate -> candidate.getName().equals(methodName))
                .findFirst()
                .orElseThrow(() -> new AssertionError("未找到方法 AdminUserController#" + methodName));
        PreAuthorize annotation = method.getAnnotation(PreAuthorize.class);
        assertThat(annotation).as(methodName + " 缺少 @PreAuthorize").isNotNull();
        return annotation.value();
    }
}
