package com.omninest.modules.sync.domain;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * 用户同步事件及其可靠发布状态。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "sync_events", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class SyncEvent {

    @Id
    private UUID id;

    @Column(name = "sequence_no", nullable = false, insertable = false, updatable = false)
    private Long sequenceNo;

    @Column(name = "recipient_user_id", nullable = false)
    private UUID recipientUserId;

    @Enumerated(EnumType.STRING)
    @Column(name = "scope", nullable = false, length = 32)
    private SyncScope scope;

    @Column(name = "resource_type", nullable = false, length = 64)
    private String resourceType;

    @Column(name = "resource_id", length = 128)
    private String resourceId;

    @Enumerated(EnumType.STRING)
    @Column(name = "action", nullable = false, length = 32)
    private SyncAction action;

    @Column(name = "resource_version")
    private Long resourceVersion;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "payload", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> payload = new LinkedHashMap<>();

    @Column(name = "publish_status", nullable = false, length = 16)
    private String publishStatus;

    @Column(name = "publish_attempts", nullable = false)
    private int publishAttempts;

    @Column(name = "available_at", nullable = false)
    private Instant availableAt;

    @Column(name = "locked_by", length = 128)
    private String lockedBy;

    @Column(name = "locked_until")
    private Instant lockedUntil;

    @Column(name = "published_at")
    private Instant publishedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(name = "version", nullable = false)
    private long version;

    @PrePersist
    void fillDefaults() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (payload == null) {
            payload = new LinkedHashMap<>();
        }
        if (publishStatus == null || publishStatus.isBlank()) {
            publishStatus = "PENDING";
        }
        Instant now = Instant.now();
        if (availableAt == null) {
            availableAt = now;
        }
        if (createdAt == null) {
            createdAt = now;
        }
        if (updatedAt == null) {
            updatedAt = now;
        }
    }

    @PreUpdate
    void fillUpdatedAt() {
        updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof SyncEvent other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    /**
     * 仅输出标识与事件类型，避免 JSON 载荷进入日志。
     */
    @Override
    public String toString() {
        return "SyncEvent{id=" + id + ", resourceType=" + resourceType + ", action=" + action + "}";
    }
}
