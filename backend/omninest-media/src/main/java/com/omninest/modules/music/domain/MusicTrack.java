package com.omninest.modules.music.domain;

import com.omninest.modules.media.domain.MetadataStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.time.LocalDate;
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
@Table(name = "music_tracks", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class MusicTrack {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "file_node_id", nullable = false)
    private UUID fileNodeId;

    @Column(name = "album_id")
    private UUID albumId;

    @Column(name = "artist_id")
    private UUID artistId;

    @Column(nullable = false, length = 500)
    private String title;

    @Column(name = "artist_name", length = 300)
    private String artistName;

    @Column(name = "album_title", length = 500)
    private String albumTitle;

    @Column(length = 120)
    private String genre;

    @Column(name = "track_number")
    private Integer trackNumber;

    @Column(name = "disc_number")
    private Integer discNumber;

    @Column(name = "release_date")
    private LocalDate releaseDate;

    @Column(name = "duration_seconds")
    private Integer durationSeconds;

    @Column(length = 32)
    private String format;

    private Integer bitrate;

    @Column(name = "sample_rate")
    private Integer sampleRate;

    @Column(name = "file_size")
    private Long fileSize;

    @Column(name = "lyrics_raw", columnDefinition = "text")
    private String lyricsRaw;

    @Column(name = "lyrics_translation", columnDefinition = "text")
    private String lyricsTranslation;

    @Column(name = "cover_file_id")
    private UUID coverFileId;

    @Column(name = "metadata_status", nullable = false, length = 32)
    private String metadataStatus = MetadataStatus.PENDING.getValue();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "external_ids", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> externalIds = new LinkedHashMap<>();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "provider_metadata", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> providerMetadata = new LinkedHashMap<>();

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

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
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        if (updatedAt == null) {
            updatedAt = now;
        }
        if (externalIds == null) {
            externalIds = new LinkedHashMap<>();
        }
        if (providerMetadata == null) {
            providerMetadata = new LinkedHashMap<>();
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
        if (!(o instanceof MusicTrack other)) {
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
        return "MusicTrack{id=" + id + ", fileNodeId=" + fileNodeId + ", title=" + title
                + ", artistName=" + artistName + ", albumId=" + albumId + "}";
    }
}
