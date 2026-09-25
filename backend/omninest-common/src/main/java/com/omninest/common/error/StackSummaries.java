package com.omninest.common.error;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.util.regex.Pattern;

/**
 * 生成脱敏截断的异常堆栈摘要，供 DLQ/失败任务记录使用。
 *
 * @author OmniNest
 */
public final class StackSummaries {

    private static final int MAX_CHARS = 2000;

    private static final Pattern BEARER_TOKEN = Pattern.compile(
            "(?i)(bearer\\s+)[A-Za-z0-9._\\-]+");

    private static final Pattern SENSITIVE_ASSIGNMENT = Pattern.compile(
            "(?i)\\b(password|passwd|pwd|token|secret|secret_key|secretkey|access_key|accesskey|"
                    + "api_key|apikey|authorization|credential|private_key)\\b(\\s*[=:]\\s*)([^\\s,;\"']+)");

    private static final Pattern JWT_LIKE = Pattern.compile(
            "\\beyJ[A-Za-z0-9_\\-]{10,}\\.[A-Za-z0-9_\\-]{5,}(?:\\.[A-Za-z0-9_\\-]{5,})?\\b");

    private static final Pattern LONG_HEX_SECRET = Pattern.compile(
            "\\b[0-9a-fA-F]{32,}\\b");

    private StackSummaries() {
    }

    /**
     * 提取异常类型、消息与堆栈，脱敏敏感片段后截断。
     *
     * @param throwable 异常
     * @return 脱敏摘要，可为空字符串
     */
    public static String summarize(Throwable throwable) {
        if (throwable == null) {
            return "";
        }
        StringWriter writer = new StringWriter();
        throwable.printStackTrace(new PrintWriter(writer));
        String redacted = redact(writer.toString());
        if (redacted.length() > MAX_CHARS) {
            redacted = redacted.substring(0, MAX_CHARS) + "...(truncated)";
        }
        return redacted;
    }

    /**
     * 掩码令牌、口令赋值与长密钥形态，保留异常结构便于诊断。
     *
     * @param raw 原始堆栈文本
     * @return 脱敏后的文本
     */
    static String redact(String raw) {
        if (raw == null || raw.isEmpty()) {
            return "";
        }
        String result = BEARER_TOKEN.matcher(raw).replaceAll("$1***");
        result = SENSITIVE_ASSIGNMENT.matcher(result).replaceAll("$1$2***");
        result = JWT_LIKE.matcher(result).replaceAll("***");
        result = LONG_HEX_SECRET.matcher(result).replaceAll("***");
        return result;
    }
}
