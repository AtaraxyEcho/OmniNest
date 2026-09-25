package com.omninest.modules.music.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 保存用户对本地或在线音乐的播放历史快照。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "music_play_history", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class MusicPlayHistory {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "track_id")
    private UUID trackId;

    @Column(name = "playable_key", nullable = false, length = 512)
    private String playableKey;

    @Column(length = 32)
    private String platform;

    @Column(name = "external_song_id", length = 255)
    private String externalSongId;

    @Column(length = 500)
    private String title;

    @Column(name = "artist_name", length = 300)
    private String artistName;

    @Column(name = "album_title", length = 500)
    private String albumTitle;

    @Column(name = "cover_url", length = 2048)
    private String coverUrl;

    @Column(name = "duration_seconds")
    private Integer durationSeconds;

    @Column(name = "media_mid", length = 255)
    private String mediaMid;

    @Column(name = "play_duration")
    private Integer playDuration;

    @Column(name = "played_at", nullable = false)
    private Instant playedAt;

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
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof MusicPlayHistory other)) {
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
        return "MusicPlayHistory{id=" + id + ", ownerUserId=" + ownerUserId + ", trackId=" + trackId
                + ", title=" + title + "}";
    }
}
