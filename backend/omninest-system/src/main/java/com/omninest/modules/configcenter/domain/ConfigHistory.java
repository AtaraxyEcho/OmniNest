package com.omninest.modules.configcenter.domain;

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

@Entity
@Table(name = "config_histories", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class ConfigHistory {
    @Id
    private UUID id;

    @Column(name = "config_key", nullable = false, length = 160)
    private String configKey;

    @Column(name = "old_value")
    private String oldValue;

    @Column(name = "new_value")
    private String newValue;

    @Column(name = "changed_by")
    private UUID changedBy;

    @Column(name = "change_reason", length = 500)
    private String changeReason;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @PrePersist
    void fillCreateFields() {
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
        if (!(o instanceof ConfigHistory other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    /**
     * 仅输出标识与配置键，避免新旧配置值（可能含密）进入日志。
     */
    @Override
    public String toString() {
        return "ConfigHistory{id=" + id + ", configKey=" + configKey + "}";
    }
}
