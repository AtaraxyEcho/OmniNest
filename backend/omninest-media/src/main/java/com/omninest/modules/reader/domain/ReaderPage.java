package com.omninest.modules.reader.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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
 * 漫画页面实体，记录单页图像在来源文件中的位置及元数据。
 */
@Entity
@Table(name = "reader_pages", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class ReaderPage {

    @Id
    private UUID id;

    /** 所属阅读条目 ID */
    @Column(name = "reader_item_id", nullable = false)
    private UUID readerItemId;

    /** 来源文件 ID */
    @Column(name = "source_id", nullable = false)
    private UUID sourceId;

    /** 所属目录节点 ID（可选） */
    @Column(name = "catalog_node_id")
    private UUID catalogNodeId;

    /** 页面所属目录唯一键，用于重建 manifest 时保留解析器提供的目录锚点 */
    @Column(name = "catalog_key", length = 500)
    private String catalogKey;

    /** 页面在来源文件中的索引（从 0 开始） */
    @Column(name = "page_index", nullable = false)
    private int pageIndex;

    /** 来源文件内的页序号（用于稳定排序） */
    @Column(name = "source_page_index", nullable = false)
    private int sourcePageIndex = 0;

    /** 页面在来源文件中的内部路径 */
    @Column(name = "source_path", nullable = false, length = 1000)
    private String sourcePath;

    /** 图像宽度（像素） */
    private Integer width;

    /** 图像高度（像素） */
    private Integer height;

    /** 页面指纹（用于检测重复/变更） */
    @Column(length = 64)
    private String fingerprint;

    /** ZIP 内 entry 索引序号（用于快速定位，避免顺序扫描） */
    @Column(name = "entry_index")
    private Integer entryIndex;

    /** 图片 MIME 类型 */
    @Column(name = "mime_type", length = 50)
    private String mimeType;

    /** 图片字节大小 */
    @Column(name = "byte_size")
    private Long byteSize;

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
        if (!(o instanceof ReaderPage other)) {
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
        return "ReaderPage{id=" + id + ", readerItemId=" + readerItemId + ", pageIndex=" + pageIndex + "}";
    }
}
