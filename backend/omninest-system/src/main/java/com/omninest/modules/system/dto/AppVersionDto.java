package com.omninest.modules.system.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 客户端版本检查响应。
 *
 * @param latestVersion   最新版本号，未配置时为 null
 * @param releaseNotesUrl 当前版本发布说明地址，未配置时为 null
 * @param downloadUrl     安装包下载页地址，未配置时为 null
 * @author OmniNest
 */
@Schema(description = "客户端最新版本信息")
public record AppVersionDto(
        @Schema(description = "最新版本号，未配置时为 null") String latestVersion,
        @Schema(description = "发布说明地址，未配置时为 null") String releaseNotesUrl,
        @Schema(description = "安装包下载页地址，未配置时为 null") String downloadUrl
) {
}
