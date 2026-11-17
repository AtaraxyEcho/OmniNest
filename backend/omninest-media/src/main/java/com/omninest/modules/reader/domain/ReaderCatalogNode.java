package com.omninest.modules.reader.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 漫画目录节点，支持季/卷/话/合集/番外多层结构。
 */
@Entity
@Table(name = "reader_catalog_nodes", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class ReaderCatalogNode {

    @Id
    private UUID id;

    /** 所属阅读条目 ID */
    @Column(name = "reader_item_id", nullable = false)
    private UUID readerItemId;

    /** 父节点 ID（顶层为 null） */
    @Column(name = "parent_id")
    private UUID parentId;

    /** 节点类型（如 SEASON、VOLUME、CHAPTER、COLLECTION、EXTRA） */
    @Column(name = "node_type", nullable = false, length = 20)
    private String nodeType;

    /** 目录标题 */
    @Column(nullable = false, length = 500)
    private String title;

    /** 同级排序索引 */
    @Column(name = "sort_index", nullable = false)
    private int sortIndex;

    /** 该节点下的总页数 */
    @Column(name = "page_count")
    private int pageCount;

    /** 来源文件 ID（用于多源区分） */
    @Column(name = "source_id")
    private UUID sourceId;

    /** 目录唯一键（用于父子关系和页面分配，如 "season:1/volume:2"） */
    @Column(name = "catalog_key", length = 500)
    private String catalogKey;

    /** 该节点的起始全局页码 */
    @Column(name = "page_start_index")
    private Integer pageIndexStart;

    /** 该节点的结束全局页码（含） */
    @Column(name = "page_end_index")
    private Integer pageIndexEnd;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @PrePersist
    @PreUpdate
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
        if (!(o instanceof ReaderCatalogNode other)) {
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
        return "ReaderCatalogNode{id=" + id + ", readerItemId=" + readerItemId + ", nodeType=" + nodeType
                + ", title=" + title + "}";
    }
}
