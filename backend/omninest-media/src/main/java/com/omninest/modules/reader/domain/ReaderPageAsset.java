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
 * 漫画页面派生资源实体，记录阅读态可直接读取的页面图片 FileNode。
 *
 * <p>对象定位（bucket/object key）由 File 模块持有，本实体只保留业务关联与派生 FileNode ID。</p>
 *
 * @author OmniNest
 */
@Entity
@Table(name = "reader_page_assets", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class ReaderPageAsset {

    @Id
    private UUID id;

    /** 所属页面 ID */
    @Column(name = "page_id", nullable = false)
    private UUID pageId;

    /** 所属阅读条目 ID */
    @Column(name = "reader_item_id", nullable = false)
    private UUID readerItemId;

    /** 所属来源 ID */
    @Column(name = "source_id", nullable = false)
    private UUID sourceId;

    /** 资源对应的清单版本 */
    @Column(name = "manifest_version", nullable = false)
    private int manifestVersion;

    /** 派生资产 FileNode ID，对象定位由 File 模块解析 */
    @Column(name = "file_node_id", nullable = false)
    private UUID fileNodeId;

    /** 图片 MIME 类型 */
    @Column(name = "mime_type", nullable = false, length = 50)
    private String mimeType;

    /** 图片字节数 */
    @Column(name = "byte_size", nullable = false)
    private long byteSize;

    /** 图片校验指纹 */
    @Column(length = 64)
    private String checksum;

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
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ReaderPageAsset that)) {
            return false;
        }
        return id != null && id.equals(that.id);
    }

    @Override
    public int hashCode() {
        return id == null ? ReaderPageAsset.class.hashCode() : id.hashCode();
    }

    @Override
    public String toString() {
        return "ReaderPageAsset{id=" + id + ", pageId=" + pageId + ", fileNodeId=" + fileNodeId + "}";
    }
}
