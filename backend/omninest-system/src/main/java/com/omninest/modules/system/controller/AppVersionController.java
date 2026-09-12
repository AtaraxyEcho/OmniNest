package com.omninest.modules.system.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.modules.system.dto.AppVersionDto;
import com.omninest.modules.system.service.AppVersionPolicyService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 应用版本检查端点（自托管"检查更新"）。
 *
 * <p>信息由管理员在配置中心维护，未配置时 latestVersion 为 null，
 * 客户端视为已是最新版本。</p>
 *
 * @author OmniNest
 */
@Tag(name = "App Version", description = "应用版本检查")
@RestController
@RequestMapping("/api/v1/app")
public class AppVersionController {

    private final AppVersionPolicyService appVersionPolicyService;

    public AppVersionController(AppVersionPolicyService appVersionPolicyService) {
        this.appVersionPolicyService = appVersionPolicyService;
    }

    /**
     * 查询最新客户端版本信息。
     *
     * @return 版本号、发布说明地址与下载页地址（未配置的项为 null）
     */
    @Operation(summary = "查询最新客户端版本", description = "返回管理员配置的最新版本号、发布说明与下载页地址")
    @GetMapping("/version")
    public ApiResponse<AppVersionDto> version() {
        return ApiResponse.success(
                new AppVersionDto(
                        appVersionPolicyService.stringValue(AppVersionPolicyService.LATEST_VERSION_KEY),
                        appVersionPolicyService.stringValue(AppVersionPolicyService.RELEASE_NOTES_URL_KEY),
                        appVersionPolicyService.stringValue(AppVersionPolicyService.DOWNLOAD_URL_KEY)
                )
        );
    }
}
