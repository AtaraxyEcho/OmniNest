package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

/**
 * 管理端全站分享链接条目。
 *
 * <p>与所有者视角的 {@link FileShareLinkDto} 分开：管理员需要知道链接是谁发的，
 * 而普通用户的列表不需要携带他人身份；两个契约共用一个 DTO 会让其中一侧长期为空字段。</p>
 *
 * @param id 分享链接 ID
 * @param ownerUserId 分享所有者用户 ID
 * @param ownerUsername 分享所有者用户名
 * @param resourceType 资源类型
 * @param resourceId 资源 ID
 * @param resourceName 资源名称，源文件已删除时为占位文案
 * @param status 分享状态
 * @param maxAccessCount 最大访问次数，null 表示不限
 * @param accessCount 已访问次数
 * @param expiresAt 过期时间
 * @param disabledAt 撤销时间
 * @param createdAt 创建时间
 * @author OmniNest
 */
public record AdminFileShareLinkDto(
        @Schema(description = "分享链接 ID") UUID id,
        @Schema(description = "分享所有者用户 ID") UUID ownerUserId,
        @Schema(description = "分享所有者用户名") String ownerUsername,
        @Schema(description = "资源类型", example = "FILE") String resourceType,
        @Schema(description = "资源 ID") UUID resourceId,
        @Schema(description = "资源名称", example = "文档.pdf") String resourceName,
        @Schema(description = "状态", example = "ACTIVE") String status,
        @Schema(description = "最大访问次数", example = "100") Integer maxAccessCount,
        @Schema(description = "已访问次数", example = "5") int accessCount,
        @Schema(description = "过期时间") Instant expiresAt,
        @Schema(description = "禁用时间") Instant disabledAt,
        @Schema(description = "创建时间") Instant createdAt
) {
}
