package com.omninest.modules.sync.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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
 * 同步事件保留水位检查点。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "sync_event_checkpoints", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class SyncEventCheckpoint {

    @Id
    private UUID id;

    @Column(name = "checkpoint_key", nullable = false, length = 64)
    private String checkpointKey;

    @Column(name = "sequence_no", nullable = false)
    private long sequenceNo;

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
        Instant now = Instant.now();
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
        if (!(o instanceof SyncEventCheckpoint other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    @Override
    public String toString() {
        return "SyncEventCheckpoint{id=" + id + ", checkpointKey=" + checkpointKey
                + ", sequenceNo=" + sequenceNo + "}";
    }
}
