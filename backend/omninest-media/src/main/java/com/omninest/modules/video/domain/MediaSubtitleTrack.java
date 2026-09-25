package com.omninest.modules.video.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import com.omninest.modules.video.domain.TrackKind;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "media_subtitle_tracks", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class MediaSubtitleTrack {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "video_item_id", nullable = false)
    private UUID videoItemId;

    @Column(name = "file_node_id")
    private UUID fileNodeId;

    @Column(nullable = false, length = 64)
    private String language;

    @Column(nullable = false, length = 120)
    private String label;

    @Column(name = "track_kind", nullable = false, length = 32)
    private String trackKind = TrackKind.SUBTITLE.getValue();

    @Column(name = "stream_index")
    private Integer streamIndex;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

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
        if (!(o instanceof MediaSubtitleTrack other)) {
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
        return "MediaSubtitleTrack{id=" + id + ", videoItemId=" + videoItemId + ", language=" + language
                + ", label=" + label + "}";
    }
}
