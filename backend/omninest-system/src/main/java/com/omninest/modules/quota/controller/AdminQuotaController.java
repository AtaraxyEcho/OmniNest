package com.omninest.modules.quota.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.common.user.UserAccountDetails;
import com.omninest.modules.quota.dto.BatchUpdateQuotaRequest;
import com.omninest.modules.quota.dto.UpdateQuotaRequest;
import com.omninest.modules.quota.service.StorageQuotaService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * 管理员存储配额管理接口。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "配额管理", description = "用户存储配额的查询与管理")
public class AdminQuotaController {

    private final StorageQuotaService storageQuotaService;
    private final CurrentUserContext currentUserContext;

    @Operation(summary = "更新用户配额", description = "管理员为指定用户设置存储配额")
    @PatchMapping("/api/v1/admin/users/{userId}/quota")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_USER_MANAGE + "')")
    ApiResponse<UserAccountDetails> updateQuota(
            @PathVariable UUID userId,
            @Valid @RequestBody UpdateQuotaRequest request
    ) {
        UUID operatorId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(storageQuotaService.updateQuotaAndGetDetails(
                userId,
                request.quotaBytes(),
                operatorId
        ));
    }

    @Operation(summary = "批量更新配额", description = "管理员批量为多个用户设置存储配额")
    @PatchMapping("/api/v1/admin/users/quota/batch")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_USER_MANAGE + "')")
    ApiResponse<Integer> batchUpdateQuota(
            @Valid @RequestBody BatchUpdateQuotaRequest request
    ) {
        UUID operatorId = currentUserContext.requireCurrentUserId();
        int updated = storageQuotaService.batchUpdateQuota(
                request.userIds(), request.quotaBytes(), operatorId);
        return ApiResponse.success(updated);
    }
}
