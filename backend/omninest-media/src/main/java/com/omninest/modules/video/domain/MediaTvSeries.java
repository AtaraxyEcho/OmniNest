package com.omninest.modules.video.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.video.domain.SeriesType;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "media_tv_series", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class MediaTvSeries {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "library_source_id")
    private UUID librarySourceId;

    @Column(name = "tmdb_id")
    private Integer tmdbId;

    @Column(nullable = false, length = 500)
    private String title;

    @Column(name = "sort_title", length = 500)
    private String sortTitle;

    @Column(name = "original_title", length = 500)
    private String originalTitle;

    @Column(name = "original_language", length = 32)
    private String originalLanguage;

    @Column(name = "first_air_date")
    private LocalDate firstAirDate;

    @Column(columnDefinition = "text")
    private String overview;

    @Column(name = "poster_file_id")
    private UUID posterFileId;

    @Column(name = "backdrop_file_id")
    private UUID backdropFileId;

    @Column(name = "rating")
    private Double rating;

    @Column(name = "vote_count", nullable = false)
    private Integer voteCount = 0;

    @Column(name = "popularity")
    private Double popularity;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "genres", columnDefinition = "jsonb", nullable = false)
    private List<Map<String, Object>> genres = new ArrayList<>();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "cast_members", columnDefinition = "jsonb", nullable = false)
    private List<Map<String, Object>> castMembers = new ArrayList<>();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "crew_members", columnDefinition = "jsonb", nullable = false)
    private List<Map<String, Object>> crewMembers = new ArrayList<>();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "studios", columnDefinition = "jsonb", nullable = false)
    private List<Map<String, Object>> studios = new ArrayList<>();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "countries", columnDefinition = "jsonb", nullable = false)
    private List<Map<String, Object>> countries = new ArrayList<>();

    @Column(name = "content_rating", length = 64)
    private String contentRating;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "external_ids", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> externalIds = new LinkedHashMap<>();

    @Column(name = "metadata_status", nullable = false, length = 32)
    private String metadataStatus = MetadataStatus.PENDING.getValue();

    @Column(name = "series_type", nullable = false, length = 32)
    private String seriesType = SeriesType.TV.getValue();

    @Column(name = "scrape_locked", nullable = false)
    private boolean scrapeLocked;

    @Column(name = "last_scraped_at")
    private Instant lastScrapedAt;

    @Column(name = "is_favorite", nullable = false)
    private boolean favorite;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "provider_metadata", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> metadata = new LinkedHashMap<>();

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
        if (genres == null) {
            genres = new ArrayList<>();
        }
        if (castMembers == null) {
            castMembers = new ArrayList<>();
        }
        if (crewMembers == null) {
            crewMembers = new ArrayList<>();
        }
        if (studios == null) {
            studios = new ArrayList<>();
        }
        if (countries == null) {
            countries = new ArrayList<>();
        }
        if (externalIds == null) {
            externalIds = new LinkedHashMap<>();
        }
        if (metadata == null) {
            metadata = new LinkedHashMap<>();
        }
        if (seriesType == null) {
            seriesType = SeriesType.TV.getValue();
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
        if (!(o instanceof MediaTvSeries other)) {
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
        return "MediaTvSeries{id=" + id + ", ownerUserId=" + ownerUserId + ", title=" + title
                + ", tmdbId=" + tmdbId + ", seriesType=" + seriesType + "}";
    }
}
