package com.omninest.modules.video.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.util.UUID;

/** 媒体发现、树形审核和按需入库接口结构。 */
public final class MediaScanDtos {

    private MediaScanDtos() {
    }

    @Schema(description = "媒体发现运行")
    public record MediaScanRunDto(
            UUID id,
            UUID librarySourceId,
            UUID discoveryTaskId,
            UUID applyTaskId,
            long generation,
            long selectionRevision,
            String status,
            String phase,
            int discoveredCount,
            int candidateCount,
            int existingCount,
            int conflictCount,
            int unmatchedCount,
            int missingCount,
            int selectedCount,
            int appliedCount,
            int failedCount,
            Instant startedAt,
            Instant finishedAt,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    @Schema(description = "候选树节点")
    public record MediaScanTreeNodeDto(
            String nodeId,
            String nodeType,
            String title,
            String subtitle,
            boolean hasChildren,
            long childCount,
            long candidateCount,
            long selectedCount,
            long issueCount,
            String selectionState,
            String matchStatus,
            String applyStatus,
            String reasonCode,
            UUID candidateId,
            Long sizeBytes
    ) {
    }

    @Schema(description = "更新候选选择范围")
    public record UpdateSelectionRequest(
            @NotBlank String nodeId,
            boolean selected,
            @NotNull Long expectedRevision
    ) {
    }

    @Schema(description = "开始按需入库")
    public record ApplySelectionRequest(@NotNull Long expectedRevision) {
    }

    @Schema(description = "选择汇总")
    public record SelectionSummaryDto(
            UUID scanRunId,
            long revision,
            long candidateCount,
            long selectedCount,
            long existingCount,
            long unmatchedCount,
            long failedCount
    ) {
    }

    @Schema(description = "不可用本地媒体摘要")
    public record UnavailableMediaDto(
            UUID videoItemId,
            UUID fileNodeId,
            UUID librarySourceId,
            String title,
            String availabilityStatus,
            Instant missingSince,
            int missingConfirmations
    ) {
    }
}
