package com.omninest.common.error;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * 堆栈摘要脱敏与截断测试。
 *
 * @author OmniNest
 */
class StackSummariesTest {

    @Test
    void redactMasksTokensPasswordsAndLongSecrets() {
        String raw = """
                java.lang.RuntimeException: failed password=hunter2 token=abc.def.ghi
                Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sigvalue
                secret_key=0123456789abcdef0123456789abcdef0123456789abcdef
                """;
        String redacted = StackSummaries.redact(raw);

        assertThat(redacted).doesNotContain("hunter2");
        assertThat(redacted).doesNotContain("abc.def.ghi");
        assertThat(redacted).doesNotContain("eyJhbGciOiJIUzI1NiJ9");
        assertThat(redacted).doesNotContain("0123456789abcdef0123456789abcdef");
        assertThat(redacted).contains("***");
    }

    @Test
    void summarizeKeepsExceptionTypeAndTruncates() {
        Exception error = new IllegalStateException("boom password=topsecret");
        String summary = StackSummaries.summarize(error);

        assertThat(summary).contains("IllegalStateException");
        assertThat(summary).doesNotContain("topsecret");
    }

    @Test
    void summarizeReturnsEmptyForNull() {
        assertThat(StackSummaries.summarize(null)).isEmpty();
    }
}
