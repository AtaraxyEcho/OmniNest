package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 外部存储目录列表响应。
 */
@Schema(description = "外部存储目录列表响应")
public record ExternalFileListDto(
        @Schema(description = "文件/目录列表（当前页）") List<ExternalFileItemDto> items,
        @Schema(description = "当前远程路径", example = "/photos") String remotePath,
        @Schema(description = "页码，从零开始") int page,
        @Schema(description = "每页条数") int size,
        @Schema(description = "目录条目总数") int totalElements,
        @Schema(description = "总页数") int totalPages
) {

    /**
     * 兼容旧调用（无分页语义）的构造：整目录视作第 0 页。
     */
    public ExternalFileListDto(List<ExternalFileItemDto> items, String remotePath) {
        this(items, remotePath, 0, items.size(), items.size(), items.isEmpty() ? 0 : 1);
    }
}
