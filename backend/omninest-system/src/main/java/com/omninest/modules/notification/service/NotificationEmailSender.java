package com.omninest.modules.notification.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig;
import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeBodyPart;
import jakarta.mail.internet.MimeMessage;
import jakarta.mail.internet.MimeMultipart;
import java.nio.charset.StandardCharsets;
import java.util.Properties;
import lombok.RequiredArgsConstructor;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSenderImpl;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;

/**
 * SMTP 投递执行体：每次发送按当前配置中心取值建立连接。
 *
 * <p>参数由管理员在配置中心热更新，因此不使用容器级 JavaMailSender Bean，
 * 避免改了配置还要重启进程。主机允许是内网地址（自建中继），加密方式由
 * {@code notification.email.security} 决定；证书链默认严格校验，只有
 * {@code notification.email.trust-hosts} 明确列出的主机才跳过校验。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class NotificationEmailSender {

    private final NotificationEmailRuntimeConfig runtimeConfig;

    /**
     * 发送一封邮件。
     *
     * @param recipient 收件地址
     * @param subject 主题
     * @param plainText 纯文本正文
     * @param html HTML 正文，为 null 或空时只发纯文本
     * @throws BusinessException 通道未配置或发件人缺失时抛出
     */
    public void send(String recipient, String subject, String plainText, String html) {
        if (!runtimeConfig.configured()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "邮件通道未配置 SMTP 主机");
        }
        String sender = runtimeConfig.from();
        if (sender.isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "邮件通道缺少发件人地址");
        }
        JavaMailSenderImpl transport = buildTransport();
        if (html == null || html.isBlank()) {
            transport.send(buildPlainMessage(sender, recipient, subject, plainText));
            return;
        }
        try {
            transport.send(buildMimeMessage(transport, sender, recipient, subject, plainText, html));
        } catch (MessagingException exception) {
            // 组装失败不是业务判定，保留原因交给消费端按失败重试处理。
            throw new IllegalStateException("邮件正文组装失败", exception);
        }
    }

    /**
     * 组装单部件纯文本消息。
     *
     * @param sender 发件人地址
     * @param recipient 收件地址
     * @param subject 主题
     * @param plainText 纯文本正文
     * @return 待发送消息
     */
    SimpleMailMessage buildPlainMessage(String sender, String recipient, String subject, String plainText) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(sender);
        message.setTo(recipient);
        message.setSubject(subject);
        message.setText(plainText);
        return message;
    }

    /**
     * 组装 multipart/alternative 消息。
     *
     * <p>纯文本部件始终带上：客户端关掉 HTML、或读屏取正文时用它，两者内容等价。</p>
     *
     * @param transport 已按配置组装的 SMTP 传输，用于创建消息骨架
     * @param sender 发件人地址
     * @param recipient 收件地址
     * @param subject 主题
     * @param plainText 纯文本正文
     * @param html HTML 正文
     * @return 待发送消息
     * @throws MessagingException 消息骨架构建或部件写入失败
     */
    MimeMessage buildMimeMessage(
            JavaMailSenderImpl transport,
            String sender,
            String recipient,
            String subject,
            String plainText,
            String html
    ) throws MessagingException {
        MimeMessage message = transport.createMimeMessage();
        MimeMessageHelper helper = new MimeMessageHelper(message, false, StandardCharsets.UTF_8.name());
        helper.setFrom(sender);
        helper.setTo(recipient);
        helper.setSubject(subject);
        // helper 只在 multipart 模式下支持双部件，而那会把根内容类型写成 mixed。通知邮件没有附件，
        // 这里直接搭标准 alternative 根：客户端的"纯文本降级"与读屏取正文都依赖根类型正确。
        MimeMultipart alternative = new MimeMultipart("alternative");
        MimeBodyPart textPart = new MimeBodyPart();
        textPart.setContent(plainText, "text/plain;charset=" + StandardCharsets.UTF_8);
        MimeBodyPart htmlPart = new MimeBodyPart();
        htmlPart.setContent(html, "text/html;charset=" + StandardCharsets.UTF_8);
        alternative.addBodyPart(textPart);
        alternative.addBodyPart(htmlPart);
        message.setContent(alternative);
        return message;
    }

    /**
     * 按当前配置组装 SMTP 传输。
     *
     * <p>包内可见以便单测直接核对端口、时限与加密方式的组装结果，不依赖真实连接。</p>
     *
     * @return 已填入连接参数的传输实例
     */
    JavaMailSenderImpl buildTransport() {
        String username = runtimeConfig.username();
        int timeout = runtimeConfig.timeoutMillis();
        JavaMailSenderImpl transport = new JavaMailSenderImpl();
        transport.setHost(runtimeConfig.host());
        transport.setPort(runtimeConfig.port());
        if (!username.isBlank()) {
            transport.setUsername(username);
            transport.setPassword(runtimeConfig.password());
        }
        Properties properties = transport.getJavaMailProperties();
        properties.put("mail.transport.protocol", "smtp");
        properties.put("mail.smtp.auth", String.valueOf(!username.isBlank()));
        properties.put("mail.smtp.connectiontimeout", String.valueOf(timeout));
        properties.put("mail.smtp.timeout", String.valueOf(timeout));
        properties.put("mail.smtp.writetimeout", String.valueOf(timeout));
        switch (runtimeConfig.security()) {
            case SSL -> properties.put("mail.smtp.ssl.enable", "true");
            case STARTTLS -> {
                properties.put("mail.smtp.starttls.enable", "true");
                properties.put("mail.smtp.starttls.required", "true");
            }
            case NONE -> {
                // 显式明文：不设置任何 TLS 开关，由管理员承担链路风险。
            }
        }
        String trustHosts = runtimeConfig.trustHosts();
        if (!trustHosts.isBlank()) {
            properties.put("mail.smtp.ssl.trust", trustHosts);
        }
        return transport;
    }
}
