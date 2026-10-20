package com.omninest.modules.notification.dto;

/**
 * 邮件通道测试请求。
 *
 * @param to 收件地址，留空时投递到当前管理员自己的邮箱
 * @author OmniNest
 */
public record EmailTestRequest(String to) {
}
