package com.omninest.modules.notification.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig;
import java.util.Properties;
import org.junit.jupiter.api.Test;
import org.springframework.mail.javamail.JavaMailSenderImpl;

/**
 * SMTP 传输组装与发送前置校验。
 *
 * @author OmniNest
 */
class NotificationEmailSenderTest {

    private final NotificationEmailRuntimeConfig runtimeConfig = mock(NotificationEmailRuntimeConfig.class);
    private final NotificationEmailSender sender = new NotificationEmailSender(runtimeConfig);

    @Test
    void sendRefusesWhenChannelHasNoHost() {
        when(runtimeConfig.configured()).thenReturn(false);

        assertThatThrownBy(() -> sender.send("alex@omninest.local", "标题", "正文"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("SMTP");
    }

    @Test
    void sendRefusesWhenSenderAddressMissing() {
        when(runtimeConfig.configured()).thenReturn(true);
        when(runtimeConfig.from()).thenReturn("");

        assertThatThrownBy(() -> sender.send("alex@omninest.local", "标题", "正文"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("发件人");
    }

    @Test
    void transportCarriesHostPortTimeoutAndAuth() {
        when(runtimeConfig.host()).thenReturn("mail.internal");
        when(runtimeConfig.port()).thenReturn(2525);
        when(runtimeConfig.username()).thenReturn("smtp-user");
        when(runtimeConfig.password()).thenReturn("smtp-password");
        when(runtimeConfig.starttls()).thenReturn(true);
        when(runtimeConfig.timeoutMillis()).thenReturn(15_000);

        JavaMailSenderImpl transport = sender.buildTransport();
        Properties properties = transport.getJavaMailProperties();

        assertThat(transport.getHost()).isEqualTo("mail.internal");
        assertThat(transport.getPort()).isEqualTo(2525);
        assertThat(transport.getUsername()).isEqualTo("smtp-user");
        assertThat(transport.getPassword()).isEqualTo("smtp-password");
        assertThat(properties.getProperty("mail.smtp.auth")).isEqualTo("true");
        assertThat(properties.getProperty("mail.smtp.starttls.enable")).isEqualTo("true");
        assertThat(properties.getProperty("mail.smtp.connectiontimeout")).isEqualTo("15000");
        assertThat(properties.getProperty("mail.smtp.timeout")).isEqualTo("15000");
        assertThat(properties.getProperty("mail.smtp.writetimeout")).isEqualTo("15000");
    }

    @Test
    void transportOmitsCredentialsAndStarttlsForAnonymousRelay() {
        when(runtimeConfig.host()).thenReturn("relay.internal");
        when(runtimeConfig.port()).thenReturn(25);
        when(runtimeConfig.username()).thenReturn("");
        when(runtimeConfig.starttls()).thenReturn(false);
        when(runtimeConfig.timeoutMillis()).thenReturn(10_000);

        JavaMailSenderImpl transport = sender.buildTransport();

        assertThat(transport.getUsername()).isNull();
        assertThat(transport.getPassword()).isNull();
        assertThat(transport.getJavaMailProperties().getProperty("mail.smtp.auth")).isEqualTo("false");
        assertThat(transport.getJavaMailProperties().getProperty("mail.smtp.starttls.enable")).isNull();
    }
}
