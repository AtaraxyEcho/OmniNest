package com.omninest.modules.search.domain;

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
 * 搜索索引状态实体，记录索引版本和重建信息。
 */
@Entity
@Table(name = "search_index_states", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class SearchIndexState {

    @Id
    private UUID id;

    @Column(name = "owner_user_id")
    private UUID ownerUserId;

    @Column(name = "index_path", nullable = false, columnDefinition = "TEXT")
    private String indexPath;

    @Column(name = "schema_version", length = 32)
    private String schemaVersion;

    @Column(name = "analyzer_name", length = 80)
    private String analyzerName;

    @Column(name = "dictionary_version")
    private String dictionaryVersion;

    @Column(length = 32)
    private String status;

    @Column(name = "last_rebuild_task_id")
    private UUID lastRebuildTaskId;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillCreatedFields() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (updatedAt == null) {
            updatedAt = Instant.now();
        }
    }

    @PreUpdate
    void fillUpdatedAt() {
        updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof SearchIndexState other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    @Override
    public String toString() {
        return "SearchIndexState{id=" + id + ", ownerUserId=" + ownerUserId
                + ", status=" + status + ", schemaVersion=" + schemaVersion
                + ", analyzerName=" + analyzerName + "}";
    }
}
