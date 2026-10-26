package com.omninest.modules.notification.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 邮件通道测试请求。
 *
 * @param to 收件地址，留空时投递到当前管理员自己的邮箱
 * @author OmniNest
 */
public record EmailTestRequest(
        @Email(message = "收件邮箱格式不正确")
        @Size(max = 254, message = "收件邮箱长度不能超过 254")
        @Pattern(regexp = "^[^\\r\\n]*$", message = "收件邮箱不能包含换行符")
        String to
) {
}
