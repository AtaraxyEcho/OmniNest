package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuditLog;
import jakarta.persistence.EntityManager;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Repository;

/**
 * 审计日志写入仓库 — 使用 JPA 实体持久化。
 */
@Repository
@RequiredArgsConstructor
public class AdminAuditLogRepository {
    private final EntityManager entityManager;

    /**
     * 插入审计日志记录。
     */
    public void insert(UUID actorUserId, String action, String resourceType, UUID resourceId, Map<String, Object> metadata) {
        insert(actorUserId, action, resourceType, resourceId, metadata, null);
    }

    /**
     * 插入审计日志记录并写入变更上下文载荷。
     *
     * @param detailPayload 已序列化的变更上下文 JSON 字符串，敏感值必须先掩码，可为 null
     */
    public void insert(
            UUID actorUserId,
            String action,
            String resourceType,
            UUID resourceId,
            Map<String, Object> metadata,
            String detailPayload
    ) {
        AuditLog log = new AuditLog();
        log.setId(UUID.randomUUID());
        log.setActorUserId(actorUserId);
        log.setAction(action);
        log.setResourceType(resourceType);
        log.setResourceId(resourceId);
        log.setMetadata(metadata == null ? Map.of() : metadata);
        log.setDetailPayload(detailPayload);
        entityManager.persist(log);
    }
}
