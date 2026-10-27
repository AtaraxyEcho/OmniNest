package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Size;

/**
 * 安装向导生成两步验证秘钥的请求。
 *
 * <p>用户名只用于生成 otpauth URI 的账户标签，可省略；长度与创建超管一致。</p>
 *
 * @author OmniNest
 */
@Schema(description = "安装向导生成两步验证秘钥请求")
public record TwoFactorSecretRequest(
        @Schema(description = "用户名，用于 otpauth URI 的账户标签", example = "root")
        @Size(max = 80, message = "用户名长度不能超过 80 个字符")
        String username
) {
}
