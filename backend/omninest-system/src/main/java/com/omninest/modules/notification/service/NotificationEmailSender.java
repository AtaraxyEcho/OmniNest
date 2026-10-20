package com.omninest.modules.notification.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig;
import java.util.Properties;
import lombok.RequiredArgsConstructor;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSenderImpl;
import org.springframework.stereotype.Service;

/**
 * SMTP 投递执行体：每次发送按当前配置中心取值建立连接。
 *
 * <p>参数由管理员在配置中心热更新，因此不使用容器级 JavaMailSender Bean，
 * 避免改了配置还要重启进程。主机允许是内网地址（自建中继），是否加密由
 * {@code notification.email.starttls} 决定。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class NotificationEmailSender {

    private final NotificationEmailRuntimeConfig runtimeConfig;

    /**
     * 发送一封纯文本邮件。
     *
     * @param recipient 收件地址
     * @param subject 主题
     * @param body 正文
     * @throws BusinessException 通道未配置或发件人缺失时抛出
     */
    public void send(String recipient, String subject, String body) {
        if (!runtimeConfig.configured()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "邮件通道未配置 SMTP 主机");
        }
        String sender = runtimeConfig.from();
        if (sender.isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "邮件通道缺少发件人地址");
        }
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(sender);
        message.setTo(recipient);
        message.setSubject(subject);
        message.setText(body);
        buildTransport().send(message);
    }

    /**
     * 按当前配置组装 SMTP 传输。
     *
     * <p>包内可见以便单测直接核对端口、时限与 TLS 开关的组装结果，不依赖真实连接。</p>
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
        if (runtimeConfig.starttls()) {
            properties.put("mail.smtp.starttls.enable", "true");
        }
        return transport;
    }
}
