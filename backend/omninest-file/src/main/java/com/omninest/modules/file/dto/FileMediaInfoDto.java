package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 文件媒体元数据（ffprobe 探测结果）。
 *
 * <p>探测失败或字段缺失时对应项为 null，前端按缺省呈现。</p>
 *
 * @author OmniNest
 */
@Schema(description = "文件媒体元数据")
public record FileMediaInfoDto(
        @Schema(description = "时长（秒，保留毫秒）") Double durationSeconds,
        @Schema(description = "主视频流或图片宽度（像素）") Integer width,
        @Schema(description = "主视频流或图片高度（像素）") Integer height) {

    public boolean isEmpty() {
        return durationSeconds == null && width == null && height == null;
    }
}
