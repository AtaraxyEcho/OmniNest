package com.omninest.modules.notification.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 通知类型配置实体，支持动态扩展通知类型。
 */
@Entity
@Table(name = "notification_types", schema = "omni")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class NotificationType {

    @Id
    private UUID id;

    @Column(name = "type_code", nullable = false, unique = true, length = 64)
    private String typeCode;

    @Column(nullable = false, length = 64)
    private String label;

    @Column(length = 256)
    private String description;

    @Column(length = 64)
    private String icon;

    @Column(length = 16)
    private String color;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(nullable = false)
    private boolean enabled = true;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @PrePersist
    void prePersist() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof NotificationType other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    @Override
    public String toString() {
        return "NotificationType{id=" + id + ", typeCode=" + typeCode + ", label=" + label + "}";
    }
}
