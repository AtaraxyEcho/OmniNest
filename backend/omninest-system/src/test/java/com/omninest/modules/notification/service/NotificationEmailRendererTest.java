package com.omninest.modules.notification.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig.MessageFormat;
import java.time.Instant;
import org.junit.jupiter.api.Test;

/**
 * 邮件正文渲染的转义、净化与链接白名单行为。
 *
 * @author OmniNest
 */
class NotificationEmailRendererTest {

    private static final Instant CREATED_AT = Instant.parse("2026-10-20T02:00:00Z");

    private final NotificationEmailRenderer renderer = new NotificationEmailRenderer();

    @Test
    void plainFormatProducesNoHtmlPart() {
        var rendered = renderer.render(
                "任务已完成", "任务已完成", "备份 3 个文件", "任务完成", CREATED_AT, "", MessageFormat.PLAIN);

        assertThat(rendered.html()).isNull();
        assertThat(rendered.subject()).isEqualTo("任务已完成");
        assertThat(rendered.plainText())
                .contains("备份 3 个文件")
                .contains("通知类型：任务完成")
                .contains("由 OmniNest 通知邮件通道发送");
    }

    @Test
    void richFormatKeepsPlainTextAlternativeAndBreaksLines() {
        var rendered = renderer.render(
                "任务失败", "任务失败", "第一行\n第二行", "任务失败", CREATED_AT, "", MessageFormat.RICH);

        assertThat(rendered.plainText()).contains("第一行");
        assertThat(rendered.html())
                .contains("第一行<br>第二行")
                .contains("创建时间：");
    }

    @Test
    void userDataNeverBecomesMarkup() {
        String injectedTitle = "<script>alert(1)</script> 完成";
        String injectedBody = "</td></tr><img src=\"https://track.example/px\"> & \"引号\"";

        var rendered = renderer.render(
                injectedTitle, injectedTitle, injectedBody, "任务完成", CREATED_AT, "", MessageFormat.RICH);

        assertThat(rendered.html())
                .contains("&lt;script&gt;alert(1)&lt;/script&gt;")
                .contains("&lt;/td&gt;&lt;/tr&gt;")
                .contains("&amp;")
                .doesNotContain("<script")
                .doesNotContain("<img")
                // 远程引用只作为惰性文本存在，不能还原成属性或链接。
                .doesNotContain("src=\"http")
                .doesNotContain("src='http");
    }

    @Test
    void bidirectionalAndZeroWidthCharactersAreStripped() {
        // U+202E 会把 "exe.nos" 显示成 "nos.exe"，零宽字符用于隐藏真实文本：都不该进邮件。
        String spoofed = "报价\u202Eexe.nosj\u200Bson";
        var rendered = renderer.render(
                spoofed, spoofed, spoofed, "文件", CREATED_AT, "", MessageFormat.RICH);

        assertThat(rendered.subject()).doesNotContain("\u202E").doesNotContain("\u200B");
        assertThat(rendered.html()).doesNotContain("\u202E").doesNotContain("\u200B");
        assertThat(rendered.plainText()).doesNotContain("\u202E").doesNotContain("\u200B");
    }

    @Test
    void oversizedBodyIsTruncatedInBothRepresentations() {
        String huge = "字".repeat(5000);
        var rendered = renderer.render("标题", "标题", huge, "任务完成", CREATED_AT, "", MessageFormat.RICH);

        assertThat(rendered.plainText()).contains("内容已截断");
        assertThat(rendered.html()).contains("内容已截断");
        assertThat(rendered.plainText()).hasSizeLessThan(huge.length() + 200);
    }

    @Test
    void linkAppearsOnlyWhenSiteAddressConfiguredAndIsTheOnlyAnchor() {
        var withoutLink = renderer.render(
                "标题", "标题", "正文", "任务完成", CREATED_AT, "", MessageFormat.RICH);
        var withLink = renderer.render(
                "标题", "标题", "正文", "任务完成", CREATED_AT, "https://nest.example.test", MessageFormat.RICH);

        assertThat(withoutLink.html()).doesNotContain("<a href=");
        assertThat(withLink.html()).contains("href=\"https://nest.example.test/#/notifications\"");
        assertThat(countAnchors(withLink.html())).isEqualTo(1);
    }

    @Test
    void nonHttpSiteAddressIsRejectedInsteadOfEmbedded() {
        var rendered = renderer.render(
                "标题", "标题", "正文", "任务完成", CREATED_AT, "file:///etc/passwd", MessageFormat.RICH);

        assertThat(rendered.html()).doesNotContain("<a href=").doesNotContain("file:");
    }

    @Test
    void documentDeclaresContentSecurityPolicyWithoutRemoteSources() {
        var rendered = renderer.render(
                "标题", "标题", "正文", "任务完成", CREATED_AT, "", MessageFormat.RICH);

        assertThat(rendered.html())
                .contains("Content-Security-Policy")
                .contains("default-src 'none'")
                .doesNotContain("src=\"http")
                .doesNotContain("@import")
                .doesNotContain("<style");
    }

    private int countAnchors(String html) {
        int count = 0;
        int cursor = 0;
        while ((cursor = html.indexOf("<a href=", cursor)) >= 0) {
            count++;
            cursor += "<a href=".length();
        }
        return count;
    }
}
