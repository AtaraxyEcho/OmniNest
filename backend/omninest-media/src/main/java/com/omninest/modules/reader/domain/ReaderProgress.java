package com.omninest.modules.reader.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "reader_progress", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class ReaderProgress {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "reader_item_id", nullable = false)
    private UUID readerItemId;

    @Column(name = "char_offset", nullable = false)
    private long charOffset = 0;

    @Column(name = "progress_percent", nullable = false)
    private BigDecimal progressPercent = BigDecimal.ZERO;

    @Column(name = "reading_mode", nullable = false, length = 50)
    private String readingMode = "scroll";

    @Column(name = "chapter_id", nullable = false, length = 128)
    private String chapterId = "";

    /** 漫画当前页面 ID */
    @Column(name = "page_id")
    private UUID pageId;

    /** 漫画当前页面索引 */
    @Column(name = "page_index")
    private Integer pageIndex;

    /** 漫画当前页面指纹（用于校验页面未变更） */
    @Column(name = "page_fingerprint", length = 64)
    private String pageFingerprint;

    /** 漫画当前来源文件 ID */
    @Column(name = "source_id")
    private UUID sourceId;

    /** 漫画当前页面在来源文件内的索引 */
    @Column(name = "source_page_index")
    private Integer sourcePageIndex;

    /** 漫画当前页面所属目录键 */
    @Column(name = "catalog_key", length = 500)
    private String catalogKey;

    /** 漫画：页内偏移（滚动模式，0.0-1.0） */
    @Column(name = "intra_page_offset")
    private Double intraPageOffset;

    /** 漫画目录清单版本号（用于检测目录结构变更） */
    @Column(name = "manifest_version")
    private Integer manifestVersion = 0;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillId() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (createdAt == null) {
            createdAt = Instant.now();
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
        if (!(o instanceof ReaderProgress other)) {
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
        return "ReaderProgress{id=" + id + ", readerItemId=" + readerItemId + "}";
    }
}
