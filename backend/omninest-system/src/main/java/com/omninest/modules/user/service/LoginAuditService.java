package com.omninest.modules.user.service;

import com.omninest.modules.user.domain.AuthLoginAudit;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.AuthLoginAuditRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 登录审计服务，使用 REQUIRES_NEW 确保审计记录不随主事务回滚。
 */
@Service
@RequiredArgsConstructor
public class LoginAuditService {

    /**
     * 审计列宽（V001 的 auth_login_audit）。用户名、平台、设备与 UA 全部来自未认证请求的
     * 头部，越界值会在 NOT NULL 列上抛 DataIntegrityViolation，把一次登录请求变成 500；
     * 因此在写库前统一截断，超长不再影响认证结果。
     *
     * <p>包内可见：会话表用同一批头部与同样列宽，由 {@code AuthService} 复用这些常量，
     * 避免两处各写一份数字。
     */
    static final int USERNAME_MAX = 80;
    static final int LOGIN_RESULT_MAX = 32;
    static final int CLIENT_PLATFORM_MAX = 32;
    static final int DEVICE_ID_MAX = 128;
    static final int DEVICE_NAME_MAX = 255;
    static final int IP_ADDRESS_MAX = 45;
    static final int USER_AGENT_MAX = 500;
    static final int FAILURE_REASON_MAX = 255;

    private final AuthLoginAuditRepository auditRepository;

    /**
     * 记录登录审计日志。独立事务，不受主事务回滚影响。
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public void record(AuthUser user, String username, String clientPlatform,
                       String deviceId, String deviceName,
                       String ipAddress, String userAgent,
                       String result, String failureReason) {
        AuthLoginAudit audit = new AuthLoginAudit();
        audit.setId(UUID.randomUUID());
        audit.setUserId(user != null ? user.getId() : null);
        audit.setUsername(clamped(username, USERNAME_MAX));
        audit.setLoginResult(clamped(result, LOGIN_RESULT_MAX));
        audit.setClientPlatform(clamped(clientPlatform, CLIENT_PLATFORM_MAX));
        audit.setDeviceId(clamped(deviceId, DEVICE_ID_MAX));
        audit.setDeviceName(clamped(deviceName, DEVICE_NAME_MAX));
        audit.setIpAddress(clamped(ipAddress, IP_ADDRESS_MAX));
        audit.setUserAgent(clamped(userAgent, USER_AGENT_MAX));
        audit.setFailureReason(clamped(failureReason, FAILURE_REASON_MAX));
        auditRepository.save(audit);
    }

    /** 包内共用：会话记录写的是同一批未认证头部，列宽也同为 32/128/255/45。 */
    static String clamped(String value, int max) {
        if (value == null || value.length() <= max) {
            return value;
        }
        return value.substring(0, max);
    }
}
