package com.omninest.modules.user.service;

import com.alibaba.fastjson2.JSON;
import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.modules.user.repository.AdminAuditLogRepository;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

/**
 * 管理审计日志及对应实时失效事件写入服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class AdminAuditLogService implements AdminAuditRecorder {
    private static final String REQUEST_ID_MDC_KEY = "requestId";
    private static final int USER_AGENT_MAX_LENGTH = 500;

    private final AdminAuditLogRepository adminAuditLogRepository;
    private final AdminSyncEventService adminSyncEventService;

    /**
     * 记录管理审计日志。
     *
     * @param actorUserId 操作用户标识
     * @param action 管理动作
     * @param resourceType 资源类型
     * @param resourceId 资源标识
     */
    @Transactional(rollbackFor = Exception.class)
    public void record(UUID actorUserId, String action, String resourceType, UUID resourceId) {
        adminAuditLogRepository.insert(actorUserId, action, resourceType, resourceId, Map.of());
        adminSyncEventService.record(action, resourceType, resourceId);
    }

    /**
     * 记录审计日志并附带元数据。
     *
     * @param actorUserId 操作用户标识
     * @param action 管理动作
     * @param resourceType 资源类型
     * @param resourceId 资源标识
     * @param metadata 非敏感审计元数据
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void recordWithMetadata(
            UUID actorUserId,
            String action,
            String resourceType,
            UUID resourceId,
            Map<String, Object> metadata
    ) {
        adminAuditLogRepository.insert(actorUserId, action, resourceType, resourceId, metadata);
        adminSyncEventService.record(action, resourceType, resourceId);
    }

    /**
     * 记录审计日志并附带变更上下文载荷。
     *
     * <p>载荷写入 detail_payload 列供管理端展示，敏感值必须由调用方先掩码。
     * 请求线程内自动补充 requestId 与 User-Agent 上下文；定时任务等无请求
     * 上下文的调用不补充这两个字段。</p>
     *
     * @param actorUserId 操作用户标识
     * @param action 管理动作
     * @param resourceType 资源类型
     * @param resourceId 资源标识
     * @param payload 已掩码的变更上下文载荷
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void recordWithPayload(
            UUID actorUserId,
            String action,
            String resourceType,
            UUID resourceId,
            Map<String, Object> payload
    ) {
        Map<String, Object> enriched = payload == null ? new LinkedHashMap<>() : new LinkedHashMap<>(payload);
        appendRequestContext(enriched);
        String detailPayload = enriched.isEmpty() ? null : JSON.toJSONString(enriched);
        adminAuditLogRepository.insert(actorUserId, action, resourceType, resourceId, Map.of(), detailPayload);
        adminSyncEventService.record(action, resourceType, resourceId);
    }

    /**
     * 复用请求链路上下文：requestId 取自 RequestIdFilter 写入的 MDC，
     * User-Agent 取自当前请求线程；两者在无请求上下文时静默缺省。
     */
    private void appendRequestContext(Map<String, Object> payload) {
        if (!payload.containsKey("requestId")) {
            String requestId = currentRequestId();
            if (requestId != null) {
                payload.put("requestId", requestId);
            }
        }
        if (!payload.containsKey("userAgent")) {
            String userAgent = currentUserAgent();
            if (userAgent != null && !userAgent.isBlank()) {
                payload.put("userAgent", userAgent.length() > USER_AGENT_MAX_LENGTH
                        ? userAgent.substring(0, USER_AGENT_MAX_LENGTH)
                        : userAgent);
            }
        }
    }

    private String currentRequestId() {
        String requestId = MDC.get(REQUEST_ID_MDC_KEY);
        return requestId == null || requestId.isBlank() ? null : requestId;
    }

    private String currentUserAgent() {
        RequestAttributes attributes = RequestContextHolder.getRequestAttributes();
        if (attributes instanceof ServletRequestAttributes servletAttributes) {
            return servletAttributes.getRequest().getHeader("User-Agent");
        }
        log.debug("当前线程无请求上下文，审计载荷不补充 User-Agent");
        return null;
    }
}
