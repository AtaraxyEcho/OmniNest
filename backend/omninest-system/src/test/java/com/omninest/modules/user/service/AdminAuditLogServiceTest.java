package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.verify;

import com.omninest.modules.user.repository.AdminAuditLogRepository;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.slf4j.MDC;
import org.springframework.web.context.request.RequestContextHolder;

/**
 * 管理审计日志写入服务测试：变更上下文载荷序列化与请求上下文补充。
 *
 * @author OmniNest
 */
class AdminAuditLogServiceTest {

    private final AdminAuditLogRepository adminAuditLogRepository = Mockito.mock(AdminAuditLogRepository.class);
    private final AdminSyncEventService adminSyncEventService = Mockito.mock(AdminSyncEventService.class);
    private final AdminAuditLogService service = new AdminAuditLogService(adminAuditLogRepository, adminSyncEventService);

    @Test
    void recordWithPayloadSerializesContextAsJson() {
        UUID actorUserId = UUID.randomUUID();
        UUID resourceId = UUID.randomUUID();
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("oldValue", "100");
        payload.put("newValue", "180");
        payload.put("reason", "调整默认限流");

        service.recordWithPayload(actorUserId, "ADMIN_CONFIG_UPDATE", "config_entries", resourceId, payload);

        ArgumentCaptor<String> detailCaptor = ArgumentCaptor.forClass(String.class);
        verify(adminAuditLogRepository).insert(
                eq(actorUserId), eq("ADMIN_CONFIG_UPDATE"), eq("config_entries"), eq(resourceId),
                eq(Map.of()), detailCaptor.capture());
        assertThat(detailCaptor.getValue())
                .contains("\"oldValue\":\"100\"")
                .contains("\"newValue\":\"180\"")
                .contains("\"reason\":\"调整默认限流\"");
        verify(adminSyncEventService).record("ADMIN_CONFIG_UPDATE", "config_entries", resourceId);
    }

    @Test
    void recordWithPayloadWritesNullDetailWhenPayloadEmpty() {
        UUID actorUserId = UUID.randomUUID();
        // 清理同线程可能残留的请求上下文，保证空载荷不补充 requestId 与 User-Agent。
        MDC.clear();
        RequestContextHolder.resetRequestAttributes();

        service.recordWithPayload(actorUserId, "ADMIN_TASK_RETRY", "sys_tasks", null, Map.of());

        verify(adminAuditLogRepository).insert(
                eq(actorUserId), eq("ADMIN_TASK_RETRY"), eq("sys_tasks"), isNull(),
                eq(Map.of()), isNull());
    }

    @Test
    void recordDelegatesWithoutDetailPayload() {
        UUID actorUserId = UUID.randomUUID();
        UUID resourceId = UUID.randomUUID();

        service.record(actorUserId, "ADMIN_SESSION_REVOKE", "auth_active_sessions", resourceId);

        verify(adminAuditLogRepository).insert(
                eq(actorUserId), eq("ADMIN_SESSION_REVOKE"), eq("auth_active_sessions"), eq(resourceId),
                eq(Map.of()));
        verify(adminAuditLogRepository, Mockito.never()).insert(
                any(), anyString(), anyString(), any(), any(), any());
        verify(adminSyncEventService).record("ADMIN_SESSION_REVOKE", "auth_active_sessions", resourceId);
    }
}
