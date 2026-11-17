package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.nio.charset.StandardCharsets;

/**
 * 分享密码进入 BCrypt 前的长度边界。
 *
 * <p>BCrypt 只接受 72 字节以内的口令，超出时 {@code encode} 抛
 * {@link IllegalArgumentException} 并以 500 收场。字符数上限无法约束字节数
 * （中日韩字符每字三字节），因此创建与更新密码前必须按 UTF-8 字节数校验。</p>
 *
 * @author OmniNest
 */
final class SharePasswordPolicy {

    /** BCrypt 允许的最大口令字节数。 */
    static final int MAX_PASSWORD_BYTES = 72;

    private SharePasswordPolicy() {
    }

    /**
     * 校验明文密码可被 BCrypt 编码。
     *
     * @param password 明文密码，null 视为不设置密码
     */
    static void requireEncodable(String password) {
        if (password != null && password.getBytes(StandardCharsets.UTF_8).length > MAX_PASSWORD_BYTES) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "分享密码不能超过 72 字节");
        }
    }
}
