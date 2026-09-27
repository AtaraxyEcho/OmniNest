package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 外部存储连接器目录项。
 *
 * @param code 连接器编码
 * @param displayName 显示名称
 * @param authMode 鉴权模式
 * @param availability 可用性提示
 * @param oauthConfigured OAuth 类连接器的实例级应用是否已配置；非 OAuth 连接器恒为 true
 * @author OmniNest
 */
@Schema(description = "外部存储连接器目录项")
public record ExternalStorageConnectorDto(
        @Schema(description = "连接器编码", example = "WEBDAV") String code,
        @Schema(description = "显示名称", example = "WebDAV") String displayName,
        @Schema(description = "鉴权模式", example = "PASSWORD") String authMode,
        @Schema(description = "可用性", example = "AVAILABLE") String availability,
        @Schema(description = "OAuth 应用是否已配置") boolean oauthConfigured
) {
}
