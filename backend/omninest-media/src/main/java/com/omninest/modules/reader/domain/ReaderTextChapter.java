package com.omninest.modules.reader.domain;

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
 * 文本书籍章节清单，保存服务端解析得到的稳定阅读顺序和源文件定位信息。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "reader_text_chapters", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class ReaderTextChapter {

    @Id
    private UUID id;

    @Column(name = "reader_item_id", nullable = false)
    private UUID readerItemId;

    @Column(name = "chapter_index", nullable = false)
    private int chapterIndex;

    @Column(name = "chapter_key", nullable = false, length = 128)
    private String chapterKey;

    @Column(nullable = false, length = 500)
    private String title;

    @Column(name = "content_path", length = 1000)
    private String contentPath;

    @Column(name = "source_start_offset")
    private Long sourceStartOffset;

    @Column(name = "source_end_offset")
    private Long sourceEndOffset;

    @Column(name = "char_count", nullable = false)
    private int charCount;

    @Column(nullable = false)
    private int level;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillDefaults() {
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
        if (!(o instanceof ReaderTextChapter other)) {
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
        return "ReaderTextChapter{id=" + id + ", readerItemId=" + readerItemId + ", chapterIndex=" + chapterIndex
                + ", title=" + title + "}";
    }
}
