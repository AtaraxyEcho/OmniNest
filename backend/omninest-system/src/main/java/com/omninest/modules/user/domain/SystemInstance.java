package com.omninest.modules.user.domain;

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
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 系统实例单例，保存首次安装状态和实例基础信息。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "system_instances", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class SystemInstance {
    public static final UUID SINGLETON_ID = UUID.fromString("00000000-0000-0000-0000-000000000001");

    @Id
    private UUID id;

    @Column(name = "installation_id", nullable = false, unique = true)
    private UUID installationId;

    @Enumerated(EnumType.STRING)
    @Column(name = "setup_state", nullable = false, length = 32)
    private SystemInstanceState setupState = SystemInstanceState.SETUP_REQUIRED;

    @Column(name = "instance_name", nullable = false, length = 120)
    private String instanceName = "OmniNest";

    @Column(name = "default_locale", nullable = false, length = 20)
    private String defaultLocale = "zh-CN";

    @Column(name = "default_timezone", nullable = false, length = 64)
    private String defaultTimezone = "Asia/Shanghai";

    @Column(name = "setup_completed_by")
    private UUID setupCompletedBy;

    @Column(name = "setup_completed_at")
    private Instant setupCompletedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

    /**
     * 将系统实例标记为安装完成。
     *
     * @param administratorId 首个超级管理员标识
     * @param configuredName 实例名称
     * @param configuredLocale 默认语言
     * @param configuredTimezone 默认时区
     */
    public void complete(
            UUID administratorId,
            String configuredName,
            String configuredLocale,
            String configuredTimezone
    ) {
        setupState = SystemInstanceState.READY;
        setupCompletedBy = administratorId;
        setupCompletedAt = Instant.now();
        instanceName = configuredName;
        defaultLocale = configuredLocale;
        defaultTimezone = configuredTimezone;
    }

    @PrePersist
    void initialize() {
        Instant now = Instant.now();
        if (id == null) {
            id = SINGLETON_ID;
        }
        if (installationId == null) {
            installationId = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = now;
        }
        updatedAt = now;
    }

    @PreUpdate
    void touchUpdatedAt() {
        updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof SystemInstance other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    @Override
    public String toString() {
        return "SystemInstance{id=" + id + ", installationId=" + installationId
                + ", setupState=" + setupState + "}";
    }
}
