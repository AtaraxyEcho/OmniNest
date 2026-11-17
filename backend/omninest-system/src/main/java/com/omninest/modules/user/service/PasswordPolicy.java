package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Set;
import org.springframework.stereotype.Component;

/**
 * 统一校验本地账户密码，确保所有账号创建和改密入口使用相同边界。
 *
 * @author OmniNest
 */
@Component
public class PasswordPolicy {

    public static final int MIN_LENGTH = 8;
    public static final int MAX_LENGTH = 64;
    public static final int MAX_UTF8_BYTES = 72;

    private static final Set<String> BLOCKED_PASSWORDS = Set.of(
            "12341234",
            "12345678",
            "123456789",
            "123456789012",
            "admin12345678",
            "password",
            "password123",
            "password1234",
            "qwerty123456"
    );

    /**
     * 校验密码长度和常见弱口令。
     *
     * <p>BCrypt 只读取前 72 个 UTF-8 字节。长度上限放宽到 64 个字符后，
     * 必须单独校验字节数：否则 25 个以上全 3 字节字符仍会被静默截断。</p>
     *
     * @param username 账户名
     * @param password 待校验密码
     */
    public void validate(String username, String password) {
        if (password == null
                || password.length() < MIN_LENGTH
                || password.length() > MAX_LENGTH
                || password.getBytes(StandardCharsets.UTF_8).length > MAX_UTF8_BYTES) {
            throw new BusinessException(
                    ErrorCode.BAD_REQUEST,
                    "密码长度必须在 8 到 64 个字符之间，且不超过 72 个 UTF-8 字节"
            );
        }
        String normalizedPassword = password.toLowerCase(Locale.ROOT);
        String normalizedUsername = username == null ? "" : username.trim().toLowerCase(Locale.ROOT);
        if (BLOCKED_PASSWORDS.contains(normalizedPassword)
                || (!normalizedUsername.isEmpty() && normalizedPassword.equals(normalizedUsername))) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "密码不能使用常见弱口令或与用户名相同");
        }
    }
}
