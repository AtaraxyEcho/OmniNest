package com.omninest.modules.reader.service.model;

import java.util.List;
import java.util.UUID;

/**
 * 漫画清单草稿：Parser 输出，Builder 消费。
 * 不含数据库实体，仅描述解析结果。
 */
public record ComicManifestDraft(
        UUID itemId,
        UUID sourceId,
        List<ComicPageDraft> pages,
        List<ComicCatalogDraftNode> catalogNodes,
        String readingDirection,
        String sourceTitle,
        String sourceAuthor
) {

    /**
     * 页面草稿：描述单个可阅读页面。
     * sourcePath 为 ZIP/EPUB 内的 entry 路径，用于按需读取图片。
     */
    public record ComicPageDraft(
            UUID sourceId,
            String sourcePath,
            int sourcePageIndex,
            int width,
            int height,
            String mimeType,
            String fingerprint,
            long byteSize,
            Integer entryIndex,
            String catalogKey
    ) {}

    /**
     * 目录节点草稿：描述目录树中的一个节点。
     * catalogKey 为唯一键，用于父子关系和页面分配。
     * sourceId 仅叶子节点需要，聚合节点为 null。
     */
    public record ComicCatalogDraftNode(
            String catalogKey,
            String parentKey,
            String title,
            String nodeType,
            int sortOrder,
            UUID sourceId
    ) {}
}
