package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.omninest.modules.user.domain.AuthLoginAudit;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.AuthLoginAuditRepository;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class LoginAuditServiceTest {

    private final AuthLoginAuditRepository auditRepository = mock(AuthLoginAuditRepository.class);
    private final LoginAuditService service = new LoginAuditService(auditRepository);

    @Test
    @DisplayName("未认证头部超过列宽时截断落库，不改变认证结果")
    void recordClampsEveryOversizedFieldToColumnWidth() {
        AuthUser user = new AuthUser();
        user.setId(UUID.fromString("10000000-0000-0000-0000-000000000001"));

        service.record(user, "u".repeat(120), "p".repeat(60), "d".repeat(200), "n".repeat(400),
                "1".repeat(60), "a".repeat(900), "r".repeat(70), "f".repeat(600));

        ArgumentCaptor<AuthLoginAudit> captor = ArgumentCaptor.forClass(AuthLoginAudit.class);
        verify(auditRepository).save(captor.capture());
        AuthLoginAudit audit = captor.getValue();
        assertThat(audit.getUserId()).isEqualTo(user.getId());
        assertThat(audit.getUsername()).hasSize(80);
        assertThat(audit.getLoginResult()).hasSize(32);
        assertThat(audit.getClientPlatform()).hasSize(32);
        assertThat(audit.getDeviceId()).hasSize(128);
        assertThat(audit.getDeviceName()).hasSize(255);
        assertThat(audit.getIpAddress()).hasSize(45);
        assertThat(audit.getUserAgent()).hasSize(500);
        assertThat(audit.getFailureReason()).hasSize(255);
    }

    @Test
    @DisplayName("截断保留前缀而不是丢弃整条记录")
    void recordKeepsLeadingCharacters() {
        service.record(null, "admin", "web", null, null, null, null, "FAILED", "密码错误");

        ArgumentCaptor<AuthLoginAudit> captor = ArgumentCaptor.forClass(AuthLoginAudit.class);
        verify(auditRepository).save(captor.capture());
        AuthLoginAudit audit = captor.getValue();
        assertThat(audit.getUsername()).isEqualTo("admin");
        assertThat(audit.getFailureReason()).isEqualTo("密码错误");
        assertThat(audit.getUserId()).isNull();
        assertThat(audit.getDeviceId()).isNull();
    }

    @Test
    @DisplayName("超长设备名截断后仍是原值前缀")
    void clampedTruncatesFromTheFront() {
        assertThat(LoginAuditService.clamped("abcdefghij", 4)).isEqualTo("abcd");
        assertThat(LoginAuditService.clamped("abcd", 4)).isEqualTo("abcd");
        assertThat(LoginAuditService.clamped(null, 4)).isNull();
    }
}
