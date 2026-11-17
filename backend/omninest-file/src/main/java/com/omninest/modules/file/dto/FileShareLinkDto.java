package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

@Schema(description = "分享链接信息")
public record FileShareLinkDto(
        @Schema(description = "分享链接 ID") UUID id,
        @Schema(description = "资源类型", example = "FILE") String resourceType,
        @Schema(description = "资源 ID") UUID resourceId,
        @Schema(description = "资源名称", example = "文档.pdf") String resourceName,
        @Schema(description = "分享码", example = "abc123") String shareCode,
        @Schema(description = "状态", example = "ACTIVE") String status,
        @Schema(description = "最大访问次数", example = "100") Integer maxAccessCount,
        @Schema(description = "已访问次数", example = "5") int accessCount,
        @Schema(description = "过期时间") Instant expiresAt,
        @Schema(description = "禁用时间") Instant disabledAt,
        @Schema(description = "创建时间") Instant createdAt,
        @Schema(description = "自动生成的密码") String generatedPassword,
        @Schema(description = "访客是否可以下载或转存文件") boolean allowDownloads,
        @Schema(description = "访客是否可获取原图") boolean originalQuality,
        @Schema(description = "访客可见内容是否包含位置信息") boolean includeLocation
) {
    /** 保留旧客户端与现有服务端调用方的构造签名。 */
    public FileShareLinkDto(
            UUID id,
            String resourceType,
            UUID resourceId,
            String resourceName,
            String shareCode,
            String status,
            Integer maxAccessCount,
            int accessCount,
            Instant expiresAt,
            Instant disabledAt,
            Instant createdAt,
            String generatedPassword) {
        this(id, resourceType, resourceId, resourceName, shareCode, status, maxAccessCount,
                accessCount, expiresAt, disabledAt, createdAt, generatedPassword, true, true, true);
    }
}
