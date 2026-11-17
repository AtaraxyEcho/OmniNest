package com.omninest.modules.search.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.UUID;

@Schema(description = "搜索结果")
public record SearchResultDto(
        @Schema(description = "文件 ID") UUID fileId,
        @Schema(description = "文件标题", example = "文档.pdf") String title,
        @Schema(description = "匹配摘要") String snippet,
        @Schema(description = "相关度评分", example = "0.95") double score
) {
}
