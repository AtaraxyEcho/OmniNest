package com.omninest.modules.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig.TransportSecurity;
import jakarta.mail.internet.MimeMessage;
import jakarta.mail.internet.MimeMultipart;
import jakarta.mail.internet.MimePart;
import java.util.Properties;
import org.junit.jupiter.api.Test;
import org.springframework.mail.javamail.JavaMailSenderImpl;

/**
 * SMTP 传输组装、消息结构与发送前置校验。
 *
 * @author OmniNest
 */
class NotificationEmailSenderTest {

    private final NotificationEmailRuntimeConfig runtimeConfig = mock(NotificationEmailRuntimeConfig.class);
    private final NotificationEmailSender sender = new NotificationEmailSender(runtimeConfig);

    @Test
    void sendRefusesWhenChannelHasNoHost() {
        when(runtimeConfig.configured()).thenReturn(false);

        assertThatThrownBy(() -> sender.send("alex@omninest.local", "标题", "正文", null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("SMTP");
    }

    @Test
    void sendRefusesWhenSenderAddressMissing() {
        when(runtimeConfig.configured()).thenReturn(true);
        when(runtimeConfig.from()).thenReturn("");

        assertThatThrownBy(() -> sender.send("alex@omninest.local", "标题", "正文", null))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("发件人");
    }

    @Test
    void starttlsModeRequiresUpgradeAndSendsAuthWhenAccountConfigured() {
        stubTransportBasics();
        when(runtimeConfig.security()).thenReturn(TransportSecurity.STARTTLS);
        when(runtimeConfig.username()).thenReturn("smtp-user");

        Properties properties = sender.buildTransport().getJavaMailProperties();

        assertThat(properties.getProperty("mail.smtp.starttls.enable")).isEqualTo("true");
        assertThat(properties.getProperty("mail.smtp.starttls.required")).isEqualTo("true");
        assertThat(properties.getProperty("mail.smtp.ssl.enable")).isNull();
        assertThat(properties.getProperty("mail.smtp.auth")).isEqualTo("true");
        assertThat(properties.getProperty("mail.smtp.connectiontimeout")).isEqualTo("15000");
        assertThat(properties.getProperty("mail.smtp.timeout")).isEqualTo("15000");
        assertThat(properties.getProperty("mail.smtp.writetimeout")).isEqualTo("15000");
    }

    @Test
    void sslModeEnablesImplicitTlsWithoutStarttls() {
        stubTransportBasics();
        when(runtimeConfig.security()).thenReturn(TransportSecurity.SSL);

        Properties properties = sender.buildTransport().getJavaMailProperties();

        assertThat(properties.getProperty("mail.smtp.ssl.enable")).isEqualTo("true");
        assertThat(properties.getProperty("mail.smtp.starttls.enable")).isNull();
    }

    @Test
    void noneModeLeavesBothTlsSwitchesOff() {
        stubTransportBasics();
        when(runtimeConfig.security()).thenReturn(TransportSecurity.NONE);

        JavaMailSenderImpl transport = sender.buildTransport();

        assertThat(transport.getUsername()).isEqualTo("smtp-user");
        assertThat(transport.getPassword()).isEqualTo("smtp-password");
        assertThat(transport.getJavaMailProperties().getProperty("mail.smtp.starttls.enable")).isNull();
        assertThat(transport.getJavaMailProperties().getProperty("mail.smtp.ssl.enable")).isNull();
    }

    @Test
    void trustHostsAreOnlyPassedWhenConfigured() {
        stubTransportBasics();
        when(runtimeConfig.security()).thenReturn(TransportSecurity.STARTTLS);
        when(runtimeConfig.trustHosts()).thenReturn("");
        assertThat(sender.buildTransport().getJavaMailProperties().getProperty("mail.smtp.ssl.trust")).isNull();

        when(runtimeConfig.trustHosts()).thenReturn("mail.internal");
        assertThat(sender.buildTransport().getJavaMailProperties().getProperty("mail.smtp.ssl.trust"))
                .isEqualTo("mail.internal");
    }

    @Test
    void anonymousRelayDisablesAuth() {
        when(runtimeConfig.host()).thenReturn("relay.internal");
        when(runtimeConfig.port()).thenReturn(25);
        when(runtimeConfig.username()).thenReturn("");
        when(runtimeConfig.security()).thenReturn(TransportSecurity.NONE);
        when(runtimeConfig.trustHosts()).thenReturn("");
        when(runtimeConfig.timeoutMillis()).thenReturn(10_000);

        JavaMailSenderImpl transport = sender.buildTransport();

        assertThat(transport.getUsername()).isNull();
        assertThat(transport.getJavaMailProperties().getProperty("mail.smtp.auth")).isEqualTo("false");
    }

    @Test
    void htmlMessageCarriesEquivalentPlainTextAlternative() throws Exception {
        stubTransportBasics();
        JavaMailSenderImpl transport = sender.buildTransport();

        MimeMessage message = sender.buildMimeMessage(
                transport,
                "notify@omninest.local",
                "alex@omninest.local",
                "任务已完成",
                "纯文本正文",
                "<p>HTML 正文</p>");

        // MIME 头在 saveChanges 时才由各部件补齐（发送路径本来也会做），先落头再断言结构。
        message.saveChanges();
        assertThat(message.getContent()).isInstanceOf(MimeMultipart.class);
        MimeMultipart multipart = (MimeMultipart) message.getContent();
        assertThat(multipart.getContentType()).startsWith("multipart/alternative");
        assertThat(multipart.getCount()).isEqualTo(2);
        assertThat(multipart.getBodyPart(0).getContentType()).startsWith("text/plain");
        assertThat(multipart.getBodyPart(1).getContentType()).startsWith("text/html");
        assertThat(((MimePart) multipart.getBodyPart(0)).getContent()).isEqualTo("纯文本正文");
    }

    @Test
    void plainMessageStaysSinglePart() {
        var message = sender.buildPlainMessage(
                "notify@omninest.local", "alex@omninest.local", "任务已完成", "纯文本正文");

        assertThat(message.getFrom()).isEqualTo("notify@omninest.local");
        assertThat(message.getTo()).containsExactly("alex@omninest.local");
        assertThat(message.getText()).isEqualTo("纯文本正文");
    }

    private void stubTransportBasics() {
        when(runtimeConfig.host()).thenReturn("mail.internal");
        when(runtimeConfig.port()).thenReturn(2525);
        when(runtimeConfig.username()).thenReturn("smtp-user");
        when(runtimeConfig.password()).thenReturn("smtp-password");
        when(runtimeConfig.timeoutMillis()).thenReturn(15_000);
        when(runtimeConfig.trustHosts()).thenReturn("");
        when(runtimeConfig.security()).thenReturn(TransportSecurity.STARTTLS);
    }
}
