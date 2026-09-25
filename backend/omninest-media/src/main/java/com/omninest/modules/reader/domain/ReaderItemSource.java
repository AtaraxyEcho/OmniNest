package com.omninest.modules.reader.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 漫画来源实体，一个阅读条目可对应多个来源文件。
 */
@Entity
@Table(name = "reader_item_sources", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class ReaderItemSource {

    @Id
    private UUID id;

    /** 所属阅读条目 ID */
    @Column(name = "reader_item_id", nullable = false)
    private UUID readerItemId;

    /** 关联的文件节点 ID */
    @Column(name = "file_node_id", nullable = false)
    private UUID fileNodeId;

    /** 文件内容哈希（用于去重） */
    @Column(name = "content_hash", nullable = false, length = 64)
    private String contentHash;

    /** 文件格式（如 CBZ、ZIP） */
    @Column(name = "file_format", nullable = false, length = 20)
    private String fileFormat;

    /** 来源文件名称 */
    @Column(name = "source_name", length = 500)
    private String sourceName;

    /** 来源排序键：从文件名解析 Vol/Ch/话号/范围，用于确定分包顺序 */
    @Column(name = "source_sort_key", length = 200)
    private String sourceSortKey;

    /** 阅读方向，主要用于 EPUB fixed-layout 漫画 */
    @Column(name = "reading_direction", length = 10)
    private String readingDirection;

    /** 来源解析状态 */
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private ReaderSourceStatus status = ReaderSourceStatus.READY;

    /** 错误码 */
    @Column(name = "error_code", length = 50)
    private String errorCode;

    /** 错误信息 */
    @Column(name = "error_message")
    private String errorMessage;

    /** 重试次数 */
    @Column(name = "retry_count", nullable = false)
    private int retryCount = 0;

    /** 季号（从文件名解析） */
    @Column(name = "season_no")
    private Integer seasonNo;

    /** 卷号（从文件名解析） */
    @Column(name = "volume_no")
    private Integer volumeNo;

    /** 章节起始号（从文件名解析） */
    @Column(name = "chapter_start")
    private Integer chapterStart;

    /** 章节结束号（从文件名解析） */
    @Column(name = "chapter_end")
    private Integer chapterEnd;

    /** 番外/特别篇排序号（从文件名解析） */
    @Column(name = "extra_order")
    private Integer extraOrder;

    /** 来源文件总页数 */
    @Column(name = "page_count")
    private int pageCount;

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
        if (!(o instanceof ReaderItemSource other)) {
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
        return "ReaderItemSource{id=" + id + ", readerItemId=" + readerItemId + ", fileNodeId=" + fileNodeId
                + ", fileFormat=" + fileFormat + "}";
    }
}
