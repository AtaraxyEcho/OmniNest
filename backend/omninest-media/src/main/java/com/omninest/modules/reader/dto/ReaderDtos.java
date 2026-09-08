package com.omninest.modules.reader.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Reader 模块 DTO 定义。
 */
public final class ReaderDtos {

    private ReaderDtos() {
    }

    // ==================== Response DTOs ====================

    /** 阅读条目摘要。 */
    public record ReaderItemDto(
            UUID id,
            String itemType,
            String contentKind,
            String title,
            String authorName,
            String coverUrl,
            String description,
            String publisher,
            String language,
            BigDecimal rating,
            Instant updatedAt,
            boolean addedToBookshelf,
            /** 当前用户阅读进度（0-1），未阅读时为 null */
            Double progressPercent,
            String spaceType,
            int manifestVersion,
            /** 导入状态：READY / PARSING / PARTIAL_FAILED / FAILED */
            String importStatus,
            /** 最近一次解析错误码 */
            String parseErrorCode,
            /** 最近一次解析错误信息 */
            String parseErrorMessage
    ) {
    }

    /** 阅读条目详情（含当前进度）。 */
    public record ReaderItemDetailDto(
            ReaderItemDto item,
            ReaderProgressDto progress
    ) {
    }

    /** 阅读进度。 */
    public record ReaderProgressDto(
            long charOffset,
            BigDecimal progressPercent,
            String readingMode,
            String chapterId,
            UUID pageId,
            Integer pageIndex,
            String pageFingerprint,
            UUID sourceId,
            Integer sourcePageIndex,
            String catalogKey,
            Integer manifestVersion,
            /** 漫画：页内偏移（滚动模式，0.0-1.0） */
            Double intraPageOffset,
            Instant updatedAt
    ) {
    }

    /** 书签。 */
    public record ReaderBookmarkDto(
            UUID id,
            UUID readerItemId,
            long charOffset,
            BigDecimal progressPercent,
            String note,
            Instant createdAt
    ) {
    }

    /** 批注（高亮 + 附注）。 */
    public record ReaderAnnotationDto(
            UUID id,
            UUID readerItemId,
            String chapterId,
            long startOffset,
            long endOffset,
            String highlightText,
            String note,
            String color,
            Instant createdAt
    ) {
    }

    /** 笔记。 */
    public record ReaderNoteDto(
            UUID id,
            UUID readerItemId,
            Long charOffset,
            String title,
            String content,
            Instant createdAt
    ) {
    }

    /** 仪表盘（概览 + 继续阅读 + 最近条目）。 */
    public record ReaderDashboardDto(
            ReaderOverviewDto overview,
            List<ReaderItemDto> continueReading,
            List<ReaderItemDto> recentItems
    ) {
    }

    /** 概览统计。 */
    public record ReaderOverviewDto(
            int totalItems,
            int continueCount
    ) {
    }

    /** 阅读统计。 */
    public record ReaderReadingStatsDto(
            int totalMinutesToday,
            int totalMinutesThisWeek,
            int currentStreak,
            int totalBooksRead
    ) {
    }

    // ==================== Request DTOs ====================

    /** 更新阅读进度请求。 */
    public record UpdateProgressRequest(
            @Min(value = 0, message = "charOffset 不能为负数")
            long charOffset,
            @NotNull(message = "progressPercent 不能为空")
            @DecimalMin(value = "0.0", message = "progressPercent 不能小于 0")
            @DecimalMax(value = "1.0", message = "progressPercent 不能大于 1")
            BigDecimal progressPercent,
            @Size(max = 50, message = "readingMode 长度不能超过 50")
            String readingMode,
            @Size(max = 128, message = "chapterId 长度不能超过 128")
            String chapterId,
            /** 漫画：页面 ID 锚点。 */
            UUID pageId,
            /** 漫画：页码索引。 */
            Integer pageIndex,
            /** 漫画：页面指纹（用于目录变更后定位）。 */
            @Size(max = 64, message = "pageFingerprint 长度不能超过 64")
            String pageFingerprint,
            /** 漫画：来源文件 ID。 */
            UUID sourceId,
            /** 漫画：来源文件内页码索引。 */
            Integer sourcePageIndex,
            /** 漫画：目录键。 */
            @Size(max = 500, message = "catalogKey 长度不能超过 500")
            String catalogKey,
            /** 漫画：清单版本号。 */
            Integer manifestVersion,
            /** 漫画：页内偏移（滚动模式，0.0-1.0） */
            Double intraPageOffset
    ) {
    }

    /** 创建书签请求。 */
    public record CreateBookmarkRequest(
            @Min(value = 0, message = "charOffset 不能为负数")
            long charOffset,
            @DecimalMin(value = "0.0", message = "progressPercent 不能小于 0")
            @DecimalMax(value = "1.0", message = "progressPercent 不能大于 1")
            BigDecimal progressPercent,
            @Size(max = 2000, message = "note 长度不能超过 2000")
            String note,
            @Size(max = 120, message = "clientOperationId 长度不能超过 120")
            String clientOperationId
    ) {
    }

    /** 创建批注请求。 */
    public record CreateAnnotationRequest(
            @Size(max = 128, message = "chapterId 长度不能超过 128")
            String chapterId,
            @Min(value = 0, message = "startOffset 不能为负数")
            long startOffset,
            @Min(value = 0, message = "endOffset 不能为负数")
            long endOffset,
            @Size(max = 5000, message = "highlightText 长度不能超过 5000")
            String highlightText,
            @Size(max = 2000, message = "note 长度不能超过 2000")
            String note,
            @Size(max = 20, message = "color 长度不能超过 20")
            String color,
            @Size(max = 120, message = "clientOperationId 长度不能超过 120")
            String clientOperationId
    ) {
    }

    /** 更新批注请求。 */
    public record UpdateAnnotationRequest(
            String note,
            String color
    ) {
    }

    /** 创建笔记请求。 */
    public record CreateNoteRequest(
            Long charOffset,
            String title,
            @NotBlank String content,
            @Size(max = 120, message = "clientOperationId 长度不能超过 120")
            String clientOperationId
    ) {
    }

    /** 更新笔记请求。 */
    public record UpdateNoteRequest(
            String title,
            @NotBlank String content
    ) {
    }

    /** 更新条目元数据请求。 */
    public record UpdateItemMetadataRequest(
            @Size(max = 500, message = "title 长度不能超过 500")
            String title,
            @Size(max = 300, message = "authorName 长度不能超过 300")
            String authorName,
            @Size(max = 5000, message = "description 长度不能超过 5000")
            String description,
            @Size(max = 300, message = "publisher 长度不能超过 300")
            String publisher,
            @Size(max = 50, message = "language 长度不能超过 50")
            String language
    ) {
    }

    /** 记录阅读会话请求。 */
    public record RecordSessionRequest(
            @Size(max = 128, message = "clientSessionId 长度不能超过 128")
            String clientSessionId,
            @NotNull Instant startedAt,
            @NotNull Instant endedAt,
            @Min(value = 1, message = "durationSeconds 必须大于 0")
            int durationSeconds
    ) {
    }

    /** 导入文件请求。 */
    public record ImportFileRequest(
            @NotNull
            UUID fileNodeId,
            boolean force,
            @Size(max = 20, message = "contentKindOverride 长度不能超过 20")
            String contentKindOverride
    ) {
    }

    /** 可导入文件候选条目。 */
    public record ImportCandidateDto(
            UUID fileNodeId,
            String fileName,
            String itemType,
            Long sizeBytes,
            String spaceType,
            Instant createdAt
    ) {
    }

    /** 从文件节点设置封面请求。 */
    public record SetCoverFromFileRequest(
            @NotNull UUID fileNodeId
    ) {
    }
}
