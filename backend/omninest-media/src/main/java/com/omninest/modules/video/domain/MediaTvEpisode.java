package com.omninest.modules.video.domain;

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

/**
 * 剧集逻辑实体，承载元数据。一个剧集可关联多个 MediaVideoItem（多版本）。
 */
@Entity
@Table(name = "media_tv_episodes", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class MediaTvEpisode {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "series_id", nullable = false)
    private UUID seriesId;

    @Column(name = "season_id")
    private UUID seasonId;

    @Column(name = "season_number", nullable = false)
    private Integer seasonNumber;

    @Column(name = "episode_number", nullable = false)
    private Integer episodeNumber;

    @Column(name = "tmdb_id")
    private Integer tmdbId;

    @Column(length = 500)
    private String title;

    @Column(name = "original_title", length = 500)
    private String originalTitle;

    @Column(name = "air_date")
    private LocalDate airDate;

    @Column(columnDefinition = "text")
    private String overview;

    @Column(name = "runtime_seconds")
    private Integer runtimeSeconds;

    @Column(name = "rating")
    private Double rating;

    @Column(name = "vote_count", nullable = false)
    private Integer voteCount = 0;

    @Column(name = "still_file_id")
    private UUID stillFileId;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "external_ids", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> externalIds = new LinkedHashMap<>();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "provider_metadata", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> metadata = new LinkedHashMap<>();

    @Column(name = "metadata_status", nullable = false, length = 32)
    private String metadataStatus = MetadataStatus.PENDING.getValue();

    @Column(name = "last_scraped_at")
    private Instant lastScrapedAt;

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
        if (metadata == null) {
            metadata = new LinkedHashMap<>();
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
        if (!(o instanceof MediaTvEpisode other)) {
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
        return "MediaTvEpisode{id=" + id + ", seriesId=" + seriesId + ", seasonNumber=" + seasonNumber
                + ", episodeNumber=" + episodeNumber + ", title=" + title + "}";
    }
}
