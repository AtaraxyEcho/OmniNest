package com.omninest.modules.reader.domain;

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

@Entity
@Table(name = "reader_annotations", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class ReaderAnnotation {
    @Id
    private UUID id;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "reader_item_id", nullable = false)
    private UUID readerItemId;

    @Column(name = "chapter_id", length = 128)
    private String chapterId;

    @Column(name = "client_operation_id", length = 120)
    private String clientOperationId;

    @Column(name = "start_offset", nullable = false)
    private long startOffset;

    @Column(name = "end_offset", nullable = false)
    private long endOffset;

    @Column(name = "highlight_text", columnDefinition = "text")
    private String highlightText;

    @Column(columnDefinition = "text")
    private String note;

    @Column(nullable = false, length = 20)
    private String color = "#FFEB3B";

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
        if (!(o instanceof ReaderAnnotation other)) {
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
        return "ReaderAnnotation{id=" + id + ", readerItemId=" + readerItemId + ", chapterId=" + chapterId + "}";
    }
}
