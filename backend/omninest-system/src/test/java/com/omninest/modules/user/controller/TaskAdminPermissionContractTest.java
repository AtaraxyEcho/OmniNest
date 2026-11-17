package com.omninest.modules.user.controller;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.security.Permissions;
import com.omninest.modules.task.controller.TaskController;
import java.lang.reflect.Method;
import java.util.Arrays;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.access.prepost.PreAuthorize;

/**
 * 任务相关接口权限契约测试。
 *
 * <p>锁定个人任务与全站任务的权限码边界，防止 MEMBER 通过管理端接口读取全站任务。</p>
 */
class TaskAdminPermissionContractTest {

    @Test
    @DisplayName("全站任务管理接口使用 task:admin")
    void adminTaskEndpointsRequireTaskAdmin() {
        assertThat(preAuthorizeOf(AdminOperationsController.class, "tasks"))
                .contains(Permissions.TASK_ADMIN);
        assertThat(preAuthorizeOf(AdminOperationsController.class, "taskPage"))
                .contains(Permissions.TASK_ADMIN);
    }

    @Test
    @DisplayName("全站任务重试使用 task:admin（任务处置，不要求配置写权限）")
    void adminTaskRetryRequiresTaskAdmin() {
        assertThat(preAuthorizeOf(AdminOperationsController.class, "retryTask"))
                .contains(Permissions.TASK_ADMIN);
    }

    @Test
    @DisplayName("个人任务接口使用 task:read")
    void personalTaskEndpointsRequireTaskRead() {
        assertThat(preAuthorizeOf(TaskController.class, "list"))
                .contains(Permissions.TASK_READ);
        assertThat(preAuthorizeOf(TaskController.class, "get"))
                .contains(Permissions.TASK_READ);
    }

    @Test
    @DisplayName("死信队列查看与重试均使用 task:admin")
    void dlqEndpointsUseTaskAdmin() {
        assertThat(preAuthorizeOf(TaskController.class, "listDlq"))
                .contains(Permissions.TASK_ADMIN);
        assertThat(preAuthorizeOf(TaskController.class, "retryDlqEntry"))
                .contains(Permissions.TASK_ADMIN);
    }

    @Test
    @DisplayName("task:admin 纳入超级管理员权限目录")
    void taskAdminIncludedInSuperAdminCatalog() {
        assertThat(Permissions.SUPER_ADMIN_PERMISSIONS).contains(Permissions.TASK_ADMIN);
        assertThat(Permissions.TASK_ADMIN).isEqualTo("task:admin");
    }

    private String preAuthorizeOf(Class<?> controllerType, String methodName) {
        Method method = Arrays.stream(controllerType.getDeclaredMethods())
                .filter(candidate -> candidate.getName().equals(methodName))
                .findFirst()
                .orElseThrow(() -> new AssertionError(
                        "未找到方法 " + controllerType.getSimpleName() + "#" + methodName));
        PreAuthorize annotation = method.getAnnotation(PreAuthorize.class);
        assertThat(annotation).as(methodName + " 缺少 @PreAuthorize").isNotNull();
        return annotation.value();
    }
}
