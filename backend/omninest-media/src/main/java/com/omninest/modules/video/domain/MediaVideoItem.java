package com.omninest.modules.video.domain;

import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.video.domain.NfoStatus;
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
 * 媒体文件条目，仅承载文件级信息（编码、分辨率等）和版本关联。
 * 元数据由 MediaMovie / MediaTvEpisode 承载。
 */
@Entity
@Table(name = "media_video_items", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class MediaVideoItem {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "file_node_id", nullable = false)
    private UUID fileNodeId;

    @Column(name = "library_source_id")
    private UUID librarySourceId;

    @Column(name = "media_type", nullable = false, length = 32)
    private String mediaType = MediaType.MOVIE.getValue();

    @Column(name = "series_id")
    private UUID seriesId;

    @Column(name = "season_id")
    private UUID seasonId;

    @Column(name = "season_number")
    private Integer seasonNumber;

    @Column(name = "episode_number")
    private Integer episodeNumber;

    @Column(name = "movie_id")
    private UUID movieId;

    @Column(name = "episode_id")
    private UUID episodeId;

    @Column(name = "version_label", length = 128)
    private String versionLabel;

    @Column(name = "is_default_version", nullable = false)
    private boolean defaultVersion;

    @Column(name = "source_video_item_id")
    private UUID sourceVideoItemId;

    @Column(name = "video_codec", length = 64)
    private String videoCodec;

    @Column(name = "audio_codec", length = 64)
    private String audioCodec;

    @Column(name = "container_format", length = 64)
    private String containerFormat;

    @Column(name = "resolution_width")
    private Integer resolutionWidth;

    @Column(name = "resolution_height")
    private Integer resolutionHeight;

    @Column(name = "duration_seconds")
    private Integer durationSeconds;

    @Column(name = "metadata_status", nullable = false, length = 32)
    private String metadataStatus = MetadataStatus.PENDING.getValue();

    @Column(name = "scrape_locked", nullable = false)
    private boolean scrapeLocked;

    @Column(name = "nfo_status", nullable = false, length = 32)
    private String nfoStatus = NfoStatus.DISABLED.getValue();

    @Column(name = "nfo_updated_at")
    private Instant nfoUpdatedAt;

    @Column(name = "nfo_path")
    private String nfoPath;

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
        if (!(o instanceof MediaVideoItem other)) {
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
        return "MediaVideoItem{id=" + id + ", fileNodeId=" + fileNodeId + ", mediaType=" + mediaType
                + ", movieId=" + movieId + ", episodeId=" + episodeId + "}";
    }
}
