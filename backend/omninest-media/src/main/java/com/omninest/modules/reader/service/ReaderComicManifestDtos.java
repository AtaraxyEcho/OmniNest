package com.omninest.modules.reader.service;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 漫画清单查询的传输对象集合。
 */
public final class ReaderComicManifestDtos {

    private ReaderComicManifestDtos() {
    }

    /**
     * 漫画清单 DTO：包含来源文件列表、目录树和页面列表。
     */
    public record ComicManifestDto(
            UUID itemId,
            String importStatus,
            int manifestVersion,
            String readingDirection,
            List<ComicSourceDto> sources,
            List<ComicCatalogDto> catalog,
            List<ComicPageDto> pages,
            ComicParseTaskDto parseTask
    ) {}

    /**
     * 漫画解析任务状态 DTO。
     */
    public record ComicParseTaskDto(
            UUID id,
            String status,
            int progress,
            String errorMessage,
            Instant updatedAt
    ) {}

    /**
     * 漫画来源 DTO。
     */
    public record ComicSourceDto(
            UUID id,
            UUID fileNodeId,
            String fileFormat,
            String sourceName,
            String sourceSortKey,
            String readingDirection,
            String status,
            String errorCode,
            String errorMessage,
            int retryCount,
            Integer seasonNo,
            Integer volumeNo,
            Integer chapterStart,
            Integer chapterEnd,
            Integer extraOrder,
            int pageCount,
            Instant createdAt
    ) {}

    /**
     * 漫画目录 DTO。
     */
    public record ComicCatalogDto(
            UUID id,
            UUID parentId,
            UUID sourceId,
            String nodeType,
            String title,
            int sortOrder,
            int pageCount,
            String catalogKey,
            Integer pageStartIndex,
            Integer pageEndIndex
    ) {}

    /**
     * 漫画页面 DTO。
     */
    public record ComicPageDto(
            UUID id,
            UUID sourceId,
            UUID catalogNodeId,
            String catalogKey,
            int pageIndex,
            int sourcePageIndex,
            String sourcePath,
            Integer width,
            Integer height,
            String fingerprint,
            Integer entryIndex,
            String mimeType,
            Long byteSize
    ) {}
}
