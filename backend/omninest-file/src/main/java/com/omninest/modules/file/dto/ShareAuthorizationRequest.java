package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Size;

/** 分享密码校验请求，密码只允许出现在 POST 请求体。 */
@Schema(description = "分享密码校验请求")
public record ShareAuthorizationRequest(
        @Schema(description = "分享密码；无密码分享可为空")
        @Size(max = 128, message = "分享密码长度不能超过 128 个字符")
        String password
) {
}
