package com.omninest.modules.backdrop.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

/**
 * 背景库模块对外 DTO 集合。
 *
 * @author OmniNest
 */
public final class BackdropDtos {

    private BackdropDtos() {
    }

    /**
     * 背景素材 DTO。
     *
     * @param id 素材 ID,跨端稳定资源身份
     * @param title 展示标题
     * @param mediaType 媒体类型: image / gif / video
     * @param status 生命周期状态: PROCESSING / READY / FAILED
     * @param failReason 失败原因摘要,仅供展示
     * @param contentUrl 原始素材短期签名 URL,即将过期或对象缺失时可为空
     * @param contentUrlExpiresAt 签名 URL 过期时间
     * @param thumbUrl 缩略图短期签名 URL,视频/GIF/处理中为空
     * @param thumbUrlExpiresAt 缩略图 URL 过期时间
     * @param width 客户端上报的展示宽度,非可信字段
     * @param height 客户端上报的展示高度,非可信字段
     * @param durationMs 客户端上报的展示时长(毫秒),非可信字段
     * @param fileSize 素材大小(字节)
     * @param updatedAt 素材最后更新时间
     */
    @Schema(description = "背景素材")
    public record BackdropAssetDto(
            @Schema(description = "素材 ID") UUID id,
            @Schema(description = "展示标题") String title,
            @Schema(description = "媒体类型") String mediaType,
            @Schema(description = "生命周期状态") String status,
            @Schema(description = "失败原因摘要") String failReason,
            @Schema(description = "原始素材签名 URL") String contentUrl,
            @Schema(description = "签名 URL 过期时间") Instant contentUrlExpiresAt,
            @Schema(description = "缩略图签名 URL") String thumbUrl,
            @Schema(description = "缩略图 URL 过期时间") Instant thumbUrlExpiresAt,
            @Schema(description = "展示宽度") Integer width,
            @Schema(description = "展示高度") Integer height,
            @Schema(description = "展示时长(毫秒)") Integer durationMs,
            @Schema(description = "素材大小(字节)") long fileSize,
            @Schema(description = "最后更新时间") Instant updatedAt
    ) {
    }

    /**
     * 批量清空背景素材结果。
     *
     * @param deleted 成功删除数量
     * @param failed 失败数量
     */
    @Schema(description = "批量清空结果")
    public record BackdropDeleteAllResultDto(
            @Schema(description = "成功删除数量") int deleted,
            @Schema(description = "失败数量") int failed
    ) {
    }
}
