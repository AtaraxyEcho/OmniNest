package com.omninest.modules.configcenter.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import com.omninest.modules.configcenter.domain.ConfigValueType;
import com.omninest.modules.configcenter.domain.RefreshScope;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "config_entries", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class ConfigEntry {
    @Id
    private UUID id;

    @Column(name = "config_key", nullable = false, length = 160, unique = true)
    private String configKey;

    @Column(name = "config_value")
    private String configValue;

    @Column(name = "value_type", nullable = false, length = 32)
    private String valueType = ConfigValueType.STRING.getValue();

    @Column(nullable = false, length = 80)
    private String category;

    @Column(name = "refresh_scope", nullable = false, length = 32)
    private String refreshScope = RefreshScope.HOT.getValue();

    @Column(columnDefinition = "text")
    private String description;

    @Column(name = "is_sensitive", nullable = false)
    private boolean sensitive;

    @Column(name = "updated_by")
    private UUID updatedBy;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillCreateFields() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        if (updatedAt == null) {
            updatedAt = now;
        }
    }

    @PreUpdate
    void fillUpdateFields() {
        updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof ConfigEntry other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    /**
     * 仅输出标识与配置键，避免可能含密的配置值进入日志。
     */
    @Override
    public String toString() {
        return "ConfigEntry{id=" + id + ", configKey=" + configKey + ", category=" + category + "}";
    }
}
