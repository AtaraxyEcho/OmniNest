package com.omninest.modules.video.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 本地媒体库的显式用户授权。
 *
 * @author OmniNest
 */
@Getter
@Setter
@Entity
@Table(name = "media_library_access", schema = "omni")
@NoArgsConstructor
public class MediaLibraryAccess {

    @Id
    private UUID id;

    @Column(name = "library_source_id", nullable = false)
    private UUID librarySourceId;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "created_by", nullable = false)
    private UUID createdBy;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

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
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof MediaLibraryAccess other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
