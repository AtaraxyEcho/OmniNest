package com.omninest.modules.video.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
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

@Entity
@Table(name = "media_watch_history", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class MediaWatchHistory {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "video_item_id", nullable = false)
    private UUID videoItemId;

    @Column(name = "position_seconds", nullable = false)
    private long positionSeconds;

    @Column(name = "duration_seconds", nullable = false)
    private long durationSeconds;

    @Column(nullable = false)
    private boolean completed;

    @Column(name = "played_at", nullable = false)
    private Instant playedAt;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> metadata = new LinkedHashMap<>();

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillCreatedFields() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (playedAt == null) {
            playedAt = Instant.now();
        }
        if (metadata == null) {
            metadata = new LinkedHashMap<>();
        }
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof MediaWatchHistory other)) {
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
        return "MediaWatchHistory{id=" + id + ", ownerUserId=" + ownerUserId + ", videoItemId=" + videoItemId
                + ", completed=" + completed + "}";
    }
}
