package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Size;
import java.util.UUID;

/**
 * 接受分享请求。
 */
@Schema(description = "接受分享请求")
public record AcceptShareRequest(
        @Schema(description = "兼容旧客户端的访问密码，不再从公开页面 URL 传输")
        @Size(max = 128, message = "分享密码长度不能超过 128 个字符")
        String password,
        @Schema(description = "目标文件夹 ID，null 表示保存到根目录") UUID targetParentId
) {
}
