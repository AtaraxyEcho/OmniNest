package com.omninest.modules.task.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageClamps;
import com.omninest.common.api.PageResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.task.dto.TaskDto;
import com.omninest.modules.task.service.TaskQueryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
@Tag(name = "任务管理", description = "系统异步任务的查询与管理")
public class TaskController {
    private final TaskQueryService taskQueryService;
    private final CurrentUserContext currentUserContext;

    /**
     * 分页查询任务列表，支持可选的状态过滤
     */
    @Operation(summary = "分页查询任务列表", description = "查询当前用户拥有的异步任务列表，支持按状态过滤和分页")
    @GetMapping("/api/v1/tasks")
    @PreAuthorize("hasAuthority('" + Permissions.TASK_READ + "')")
    ApiResponse<PageResponse<TaskDto>> list(
            @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        int safePage = PageClamps.safePage(page);
        int safeSize = PageClamps.safeSize(size);
        var result = taskQueryService.listOwned(
                ownerUserId, status, PageRequest.of(safePage, safeSize));
        return ApiResponse.success(PageResponse.of(
                result.getContent(), safePage, safeSize, result.getTotalElements()));
    }

    /**
     * 查询当前用户拥有的指定任务。
     *
     * @param taskId 任务 ID
     * @return 任务信息
     */
    @Operation(summary = "查询任务详情", description = "查询当前用户拥有的指定异步任务")
    @GetMapping("/api/v1/tasks/{taskId}")
    @PreAuthorize("hasAuthority('" + Permissions.TASK_READ + "')")
    ApiResponse<TaskDto> get(@PathVariable UUID taskId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(taskQueryService.getOwned(ownerUserId, taskId));
    }

    /**
     * 查询死信队列中的任务
     */
    @Operation(summary = "查询死信队列任务", description = "查询死信队列中处理失败的任务列表")
    @GetMapping("/api/v1/tasks/dlq")
    @PreAuthorize("hasAuthority('" + Permissions.TASK_ADMIN + "')")
    ApiResponse<List<TaskDto>> listDlq(@RequestParam(defaultValue = "20") int limit) {
        return ApiResponse.success(taskQueryService.listDlq(PageClamps.safeLimit(limit, 20)));
    }

    /**
     * 重试死信队列中的任务
     *
     * <p>授权用 task:admin 而非系统配置管理：任务重试属任务处置，
     * 管理员角色需要能独立完成，不必因此拿到全站配置写权限。</p>
     */
    @Operation(summary = "重试死信队列任务", description = "将死信队列中的指定任务重新投入正常队列进行重试")
    @PostMapping("/api/v1/tasks/dlq/{taskId}/retry")
    @PreAuthorize("hasAuthority('" + Permissions.TASK_ADMIN + "')")
    ApiResponse<Void> retryDlqEntry(@PathVariable UUID taskId) {
        taskQueryService.retryDlqEntry(taskId);
        return ApiResponse.success();
    }

    /**
     * 重试当前用户拥有的失败任务。
     */
    @Operation(summary = "重试本人任务", description = "将当前用户拥有的 FAILED 任务重新投入队列；DLQ 请使用管理端重试")
    @PostMapping("/api/v1/tasks/{taskId}/retry")
    @PreAuthorize("hasAuthority('" + Permissions.TASK_READ + "')")
    ApiResponse<Void> retryOwned(@PathVariable UUID taskId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        taskQueryService.retryOwned(ownerUserId, taskId);
        return ApiResponse.success();
    }
}
