package com.omninest.modules.user.dto;

/**
 * 更新当前用户基础资料请求体。
 *
 * @param displayName 显示昵称；null 表示保持不变
 * @param email 邮箱；null 表示保持不变，空串表示清除
 */
public record UpdateMeRequest(String displayName, String email) {
}
