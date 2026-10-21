package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;

/**
 * 文件权限设置请求。
 *
 * <p>三个权限位都是必填：全局宽松绑定会把缺席的原始布尔按 {@code false} 绑上，
 * 于是"只想改下载却漏发分享"会被静默执行成收回分享权限。写权限是不可逆的作者意图，
 * 缺席必须报错而不是默认拒绝。</p>
 *
 * @param allowDownload 是否允许下载
 * @param allowShare 是否允许分享
 * @param allowEdit 是否允许编辑
 * @author OmniNest
 */
@Schema(description = "文件权限设置请求")
public record PermissionRequest(
        @Schema(description = "允许下载", example = "true") @NotNull(message = "允许下载不能为空") Boolean allowDownload,
        @Schema(description = "允许分享", example = "false") @NotNull(message = "允许分享不能为空") Boolean allowShare,
        @Schema(description = "允许编辑", example = "false") @NotNull(message = "允许编辑不能为空") Boolean allowEdit
) {
}
