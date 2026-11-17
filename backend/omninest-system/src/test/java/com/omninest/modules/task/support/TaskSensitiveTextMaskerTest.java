package com.omninest.modules.task.support;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * 任务文本脱敏测试。
 *
 * @author OmniNest
 */
class TaskSensitiveTextMaskerTest {

    @Test
    void masksWindowsAndUnixPaths() {
        String text = "失败: C:\\data\\users\\alice\\秘密.pdf 与 /srv/omninest/users/bob/照片.jpg";

        String masked = TaskSensitiveTextMasker.mask(text);

        assertThat(masked).doesNotContain("alice").doesNotContain("bob")
                .doesNotContain("秘密.pdf").doesNotContain("照片.jpg")
                .contains("已脱敏路径");
    }

    @Test
    void masksFileFieldsInJsonPayload() {
        String text = "{\"fileName\":\"体检报告.pdf\",\"fileId\":\"abc\",\"objectKey\":\"users/1/a.pdf\"}";

        String masked = TaskSensitiveTextMasker.mask(text);

        assertThat(masked).doesNotContain("体检报告").doesNotContain("users/1/a.pdf")
                .contains("\"fileName\":\"[已脱敏]\"")
                .contains("\"fileId\":\"abc\"");
    }

    @Test
    void leavesPlainDiagnosticsUntouched() {
        assertThat(TaskSensitiveTextMasker.mask("连接超时，已重试 3 次"))
                .isEqualTo("连接超时，已重试 3 次");
        assertThat(TaskSensitiveTextMasker.mask(null)).isNull();
    }
}
