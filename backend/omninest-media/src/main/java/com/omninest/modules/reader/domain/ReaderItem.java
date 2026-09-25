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
@Table(name = "reader_items", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class ReaderItem {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "file_node_id")
    private UUID fileNodeId;

    @Column(name = "content_hash", length = 64)
    private String contentHash;

    @Column(name = "item_type", nullable = false, length = 50)
    private String itemType;

    /** 内容类型：TEXT（书籍）或 COMIC（漫画） */
    @Column(name = "content_kind", nullable = false, length = 20)
    private String contentKind = "TEXT";

    @Column(nullable = false, length = 500)
    private String title;

    @Column(name = "author_name", length = 300)
    private String authorName;

    @Column(columnDefinition = "text")
    private String description;

    @Column(name = "cover_file_id")
    private UUID coverFileId;

    @Column(length = 300)
    private String publisher;

    @Column(length = 50)
    private String language;

    @Column(name = "release_date")
    private LocalDate releaseDate;

    private BigDecimal rating;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> genres = new LinkedHashMap<>();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "external_ids", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> externalIds = new LinkedHashMap<>();

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    /** 导入状态：READY / PARSING / FAILED */
    @Column(name = "import_status", nullable = false, length = 20)
    private String importStatus = "READY";

    /** 解析错误码 */
    @Column(name = "parse_error_code", length = 50)
    private String parseErrorCode;

    /** 解析错误信息 */
    @Column(name = "parse_error_message")
    private String parseErrorMessage;

    /** 最近一次解析完成时间 */
    @Column(name = "parsed_at")
    private Instant parsedAt;

    /** 漫画清单版本号：每次重建目录或追加分包时递增 */
    @Column(name = "manifest_version", nullable = false)
    private int manifestVersion = 0;

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
            genres = new LinkedHashMap<>();
        }
        if (externalIds == null) {
            externalIds = new LinkedHashMap<>();
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
        if (!(o instanceof ReaderItem other)) {
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
        return "ReaderItem{id=" + id + ", itemType=" + itemType + ", title=" + title + "}";
    }
}
