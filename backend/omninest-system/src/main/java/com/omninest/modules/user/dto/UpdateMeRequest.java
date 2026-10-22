package com.omninest.modules.user.dto;

import jakarta.validation.constraints.Size;

/**
 * 更新当前用户基础资料请求体。
 *
 * @param displayName 显示昵称；null 表示保持不变
 * @param email 邮箱；null 表示保持不变，空串表示清除
 */
public record UpdateMeRequest(
        @Size(max = 120, message = "显示昵称长度不能超过 120 个字符") String displayName,
        @Size(max = 255, message = "邮箱长度不能超过 255 个字符") String email
) {
}
