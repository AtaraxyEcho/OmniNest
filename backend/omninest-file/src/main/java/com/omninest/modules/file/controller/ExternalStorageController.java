package com.omninest.modules.file.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.api.PageResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
import com.omninest.common.security.ClientIpResolver;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.dto.CreateImportTaskRequest;
import com.omninest.modules.file.dto.ExternalFileListDto;
import com.omninest.modules.file.dto.ExternalSpaceDto;
import com.omninest.modules.file.dto.ImportTaskDto;
import com.omninest.modules.file.service.ExternalStorageService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 外部存储 API。远程源只读浏览与导入，不提供远端写操作。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "外部存储", description = "远程来源浏览与导入到受管存储")
public class ExternalStorageController {
    private final ExternalStorageService externalStorageService;
    private final CurrentUserContext currentUserContext;
    private final com.omninest.modules.file.service.ExternalStorageOAuthService oauthService;
    private final RateLimitService rateLimitService;
    private final ClientIpResolver clientIpResolver;

    @Operation(summary = "列出连接器目录", description = "返回可接入的远程存储类型")
    @GetMapping("/api/v1/external-connectors")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<List<com.omninest.modules.file.dto.ExternalStorageConnectorDto>> listConnectors() {
        return ApiResponse.success(externalStorageService.listConnectors());
    }

    @Operation(summary = "开始 OAuth 授权", description = "返回第三方授权 URL")
    @PostMapping("/api/v1/external-connectors/{code}/oauth/start")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<com.omninest.modules.file.dto.OAuthStartResponse> oauthStart(
            @PathVariable String code,
            @RequestParam UUID accountId
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(oauthService.start(ownerUserId, code, accountId));
    }

    /**
     * 三方授权回调。
     *
     * <p>授权码的查询参数名由 OAuth2 协议固定为 {@code code}，与路径上的连接器编码变量同名；
     * 路径变量必须改名绑定，否则回调永远取不到授权码。端点由浏览器匿名回跳命中，靠
     * {@code state} 关联本次授权会话并定位账户，因此不再要求 Bearer 令牌。</p>
     */
    @Operation(summary = "OAuth 回调", description = "处理授权码并绑定 token，浏览器匿名回跳")
    @GetMapping("/api/v1/external-connectors/{providerCode}/oauth/callback")
    ApiResponse<Void> oauthCallback(
            @PathVariable("providerCode") String providerCode,
            @RequestParam(value = "state", required = false) String state,
            @RequestParam(value = "code", required = false) String authorizationCode,
            @RequestParam(value = "error", required = false) String error,
            HttpServletRequest request
    ) {
        // 匿名端点：按可信代理边界取客户端地址做限流，避免成为可无限重放的探测入口。
        String clientIp = clientIpResolver.resolve(
                request.getRemoteAddr(),
                request.getHeader("X-Forwarded-For"),
                request.getHeader("X-Real-IP")
        );
        if (!rateLimitService.tryAcquire(
                "ip:" + clientIp + ":external-oauth-callback", 20, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "OAuth 回调请求过于频繁，请稍后再试");
        }
        if (error != null && !error.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "授权被第三方拒绝: " + error);
        }
        oauthService.handleCallback(providerCode, state, authorizationCode);
        return ApiResponse.success();
    }

    @Operation(summary = "测试连接", description = "验证外部存储账户是否可连通")
    @PostMapping("/api/v1/external-storages/{accountId}/test")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<com.omninest.modules.file.dto.ExternalStorageTestResultDto> testConnection(
            @PathVariable UUID accountId
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(externalStorageService.testConnection(ownerUserId, accountId));
    }

    @Operation(summary = "浏览外部存储", description = "浏览指定外部存储账户中的文件和目录")
    @GetMapping("/api/v1/external-storages/{accountId}/browse")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<ExternalFileListDto> browse(
            @PathVariable UUID accountId,
            @RequestParam(required = false, defaultValue = "/") String path,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "200") int size
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(
                externalStorageService.browse(ownerUserId, accountId, path, page, size));
    }

    @Operation(summary = "获取空间使用情况", description = "查询指定外部存储账户的空间使用量和配额")
    @GetMapping("/api/v1/external-storages/{accountId}/space")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<ExternalSpaceDto> getSpaceUsage(@PathVariable UUID accountId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(externalStorageService.getSpaceUsage(ownerUserId, accountId));
    }

    @Operation(summary = "获取文件系统信息", description = "获取指定外部存储账户的文件系统元信息")
    @GetMapping("/api/v1/external-storages/{accountId}/info")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<Map<String, Object>> getFsInfo(@PathVariable UUID accountId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(externalStorageService.getFsInfo(ownerUserId, accountId));
    }

    @Operation(summary = "创建导入任务", description = "从外部存储导入文件到本地存储")
    @PostMapping("/api/v1/external-storages/{accountId}/import")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<ImportTaskDto> createImportTask(
            @PathVariable UUID accountId,
            @Valid @RequestBody CreateImportTaskRequest body
    ) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(externalStorageService.createImportTask(ownerUserId, accountId, body));
    }

    @Operation(summary = "列出导入任务", description = "列出当前用户的所有导入任务")
    @GetMapping("/api/v1/external-storages/import-tasks")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<PageResponse<ImportTaskDto>> listImportTasks() {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        List<ImportTaskDto> items = externalStorageService.listImportTasks(ownerUserId);
        // 本端点不分页（任务数量级为几十），size 必须报实际返回条数，
        // 写死 50 会让总数超过 50 时分页元数据自相矛盾。
        return ApiResponse.success(PageResponse.of(items, 0, items.size(), items.size()));
    }

    @Operation(summary = "取消导入任务", description = "取消指定的导入任务")
    @DeleteMapping("/api/v1/external-storages/import-tasks/{taskId}")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_WRITE + "')")
    ApiResponse<Void> cancelImportTask(@PathVariable UUID taskId) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        externalStorageService.cancelImportTask(ownerUserId, taskId);
        return ApiResponse.success();
    }

    @Operation(summary = "列出 OAuth 应用", description = "列出实例级连接器 OAuth 应用配置")
    @GetMapping("/api/v1/admin/external-connectors/oauth-apps")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_READ + "')")
    ApiResponse<List<com.omninest.modules.file.dto.ConnectorOAuthAppDto>> listOAuthApps() {
        return ApiResponse.success(oauthService.listApps());
    }

    @Operation(summary = "保存 OAuth 应用", description = "创建或更新连接器 OAuth 应用")
    @PostMapping("/api/v1/admin/external-connectors/oauth-apps")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<com.omninest.modules.file.dto.ConnectorOAuthAppDto> saveOAuthApp(
            @Valid @RequestBody com.omninest.modules.file.dto.SaveConnectorOAuthAppRequest body
    ) {
        return ApiResponse.success(oauthService.saveApp(body));
    }
}
