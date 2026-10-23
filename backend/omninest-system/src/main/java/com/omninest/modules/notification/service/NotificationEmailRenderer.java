package com.omninest.modules.notification.service;

import com.omninest.common.user.SystemInstanceInfo;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig.MessageFormat;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.web.util.HtmlUtils;

/**
 * 通知邮件正文渲染：模板由本类固定，数据一律转义后填入。
 *
 * <p>通知正文会带入外部来源文本（例如刮削失败时拼进来的异常信息），因此 HTML 侧不允许任何
 * 原始片段：只做转义、剥离控制字符与双向覆写字符（可把 {@code exe.} 显示成 {@code .exe}），
 * 并且不引用远程图片、字体或样式，避免邮件客户端反向请求暴露收件人。</p>
 *
 * <p>落款名称、文档语言与时间戳时区都取自安装向导写入的系统实例配置，不能各写一份常量，
 * 否则改了实例名与时区后邮件仍按出厂值发送。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class NotificationEmailRenderer {

    private static final int MAX_BODY_LENGTH = 4000;
    private static final DateTimeFormatter TIMESTAMP_FORMAT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final SystemInstanceInfo systemInstanceInfo;

    /**
     * 渲染结果。
     *
     * @param subject 主题
     * @param plainText 纯文本正文（始终提供，作为 HTML 的等价降级）
     * @param html HTML 正文，纯文本格式时为 null
     */
    public record Rendered(String subject, String plainText, String html) {
    }

    /**
     * 渲染一封通知邮件。
     *
     * @param subject 邮件主题
     * @param title 通知标题，作为正文首行大字
     * @param body 通知正文，可为空
     * @param typeLabel 通知类型显示名
     * @param createdAt 通知创建时刻
     * @param webBaseUrl 站点地址，空串表示正文不放链接
     * @param format 正文格式
     * @return 主题与两种正文表示
     */
    public Rendered render(
            String subject,
            String title,
            String body,
            String typeLabel,
            Instant createdAt,
            String webBaseUrl,
            MessageFormat format
    ) {
        String safeSubject = sanitize(subject);
        String safeTitle = sanitize(title);
        String safeBody = truncate(sanitize(body == null ? "" : body));
        String safeType = sanitize(typeLabel);
        String productName = sanitize(systemInstanceInfo.instanceName());
        String timestamp = TIMESTAMP_FORMAT
                .withZone(systemInstanceInfo.timeZone())
                .format(createdAt);
        String plainText = plainText(safeBody, safeType, timestamp, productName);
        if (format != MessageFormat.RICH) {
            return new Rendered(safeSubject, plainText, null);
        }
        return new Rendered(
                safeSubject,
                plainText,
                html(safeTitle, safeBody, safeType, timestamp, webBaseUrl,
                        productName, sanitize(systemInstanceInfo.defaultLocale())));
    }

    /**
     * 去掉控制字符、双向覆写字符、零宽字符与私用区字符，只保留常见排版空白。
     *
     * <p>这些字符在纯文本里也只是噪声，但混进 HTML 后可以改变可见顺序、伪造文件名或域名，
     * 因此不论格式都先清掉。</p>
     */
    private String sanitize(String raw) {
        if (raw == null) {
            return "";
        }
        StringBuilder cleaned = new StringBuilder(raw.length());
        for (int index = 0; index < raw.length(); index++) {
            char current = raw.charAt(index);
            int type = Character.getType(current);
            boolean allowedControl = current == '\n' || current == '\r' || current == '\t';
            if (type == Character.FORMAT || type == Character.SURROGATE
                    || type == Character.PRIVATE_USE || type == Character.UNASSIGNED
                    || (type == Character.CONTROL && !allowedControl)) {
                continue;
            }
            cleaned.append(current);
        }
        return cleaned.toString().trim();
    }

    private String truncate(String value) {
        if (value.length() <= MAX_BODY_LENGTH) {
            return value;
        }
        return value.substring(0, MAX_BODY_LENGTH) + "…（内容已截断）";
    }

    private String plainText(String body, String typeLabel, String timestamp, String productName) {
        StringBuilder text = new StringBuilder();
        if (!body.isBlank()) {
            text.append(body).append(System.lineSeparator()).append(System.lineSeparator());
        }
        text.append("通知类型：").append(typeLabel).append(System.lineSeparator())
                .append("创建时间：").append(timestamp).append(System.lineSeparator())
                .append(System.lineSeparator())
                .append("由 ").append(productName).append(" 通知邮件通道发送。");
        return text.toString();
    }

    private String html(String title, String body, String typeLabel, String timestamp, String webBaseUrl,
                        String productName, String localeTag) {
        String safeBaseUrl = webBaseUrl == null ? "" : webBaseUrl.trim();
        boolean hasLink = safeBaseUrl.startsWith("http://") || safeBaseUrl.startsWith("https://");
        String link = hasLink
                ? linkBlock(HtmlUtils.htmlEscape(safeBaseUrl), HtmlUtils.htmlEscape(productName))
                : "";
        return """
                <!doctype html>
                <html lang="%8$s">
                <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
                <title>%1$s</title>
                </head>
                <body style="margin:0;padding:0;background-color:#f1f5f9;">
                <table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0"
                       style="background-color:#f1f5f9;padding:24px 12px;">
                  <tr><td align="center">
                    <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0"
                           style="max-width:600px;width:100%%;background-color:#ffffff;
                                  border:1px solid #e2e8f0;font-family:-apple-system,Segoe UI,Roboto,
                                  Helvetica,Arial,'PingFang SC','Microsoft YaHei',sans-serif;
                                  color:#0f172a;font-size:14px;line-height:1.6;">
                      <tr><td style="padding:16px 20px;border-bottom:1px solid #e2e8f0;">
                        <table role="presentation" width="100%%" cellpadding="0" cellspacing="0" border="0">
                          <tr>
                            <td style="font-size:12px;letter-spacing:1px;color:#64748b;text-transform:uppercase;">
                              %2$s</td>
                            <td align="right" style="font-size:12px;color:#64748b;">%3$s</td>
                          </tr>
                        </table>
                      </td></tr>
                      <tr><td style="padding:20px;">
                        <div style="font-size:17px;font-weight:600;margin:0 0 12px 0;">%4$s</div>
                        %5$s
                        <div style="margin-top:16px;font-size:12px;color:#64748b;">创建时间：%6$s</div>
                      </td></tr>%7$s
                      <tr><td style="padding:14px 20px;border-top:1px solid #e2e8f0;
                                     font-size:12px;color:#64748b;">
                        本邮件不含远程图片与脚本；如无法显示，请查看等价的纯文本版本。
                      </td></tr>
                    </table>
                  </td></tr>
                </table>
                </body>
                </html>
                """.formatted(
                HtmlUtils.htmlEscape(title),
                HtmlUtils.htmlEscape(productName),
                HtmlUtils.htmlEscape(typeLabel),
                HtmlUtils.htmlEscape(title),
                bodyBlock(body),
                HtmlUtils.htmlEscape(timestamp),
                link,
                HtmlUtils.htmlEscape(localeTag));
    }

    private String bodyBlock(String body) {
        if (body.isBlank()) {
            return "";
        }
        String broken = HtmlUtils.htmlEscape(body).replace("\r\n", "<br>").replace("\n", "<br>");
        return "<div style=\"margin:0;white-space:normal;word-break:break-word;\">" + broken + "</div>";
    }

    private String linkBlock(String escapedBaseUrl, String escapedProductName) {
        return """
                        <tr><td style="padding:0 20px 20px 20px;">
                          <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                            <tr><td style="background-color:#1d4ed8;">
                              <a href="%s/#/notifications"
                                 style="display:inline-block;padding:10px 18px;color:#ffffff;
                                        text-decoration:none;font-size:13px;">打开 %s</a>
                            </td></tr>
                          </table>
                        </td></tr>
                """.formatted(escapedBaseUrl, escapedProductName);
    }
}
