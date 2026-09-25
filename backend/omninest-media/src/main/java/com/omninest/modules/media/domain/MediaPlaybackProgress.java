package com.omninest.modules.media.domain;

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
 * 保存用户对任意可播放媒体的当前进度。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "media_playback_progresses", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class MediaPlaybackProgress {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "media_type", nullable = false, length = 16)
    private String mediaType;

    @Column(name = "media_key", nullable = false, length = 512)
    private String mediaKey;

    @Column(name = "position_seconds", nullable = false)
    private long positionSeconds;

    @Column(name = "duration_seconds", nullable = false)
    private long durationSeconds;

    @Column(name = "completed", nullable = false)
    private boolean completed;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "client_updated_at", nullable = false)
    private Instant clientUpdatedAt;

    @Column(name = "device_id", nullable = false, length = 128)
    private String deviceId;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillCreatedFields() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = Instant.now();
        }
        if (updatedAt == null) {
            updatedAt = Instant.now();
        }
        if (clientUpdatedAt == null) {
            clientUpdatedAt = updatedAt;
        }
        if (deviceId == null || deviceId.isBlank()) {
            deviceId = "legacy";
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
        if (!(o instanceof MediaPlaybackProgress other)) {
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
        return "MediaPlaybackProgress{id=" + id + ", ownerUserId=" + ownerUserId + ", mediaType=" + mediaType
                + ", mediaKey=" + mediaKey + "}";
    }
}
