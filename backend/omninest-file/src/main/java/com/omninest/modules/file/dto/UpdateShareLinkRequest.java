package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Size;
import java.time.Instant;

/**
 * 更新分享链接设置的请求。
 *
 * <p>令牌与资源不变：改密码、改有效期或改次数上限都不应让已发出的地址失效，
 * 否则分享出去的内容会因为一次编辑而打不开。字段为 null 表示保持原值。</p>
 *
 * @param password 新访问密码；null 表示不改，空白串表示清除密码
 * @param expiresAt 过期时间，格式与创建请求一致；null 表示不改，空白串表示改为长期有效
 * @param maxAccessCount 最大访问次数；null 表示不改，0 表示不限次数
 * @author OmniNest
 */
public record UpdateShareLinkRequest(
        @Schema(description = "自定义访问密码；不传表示保持原密码")
        @Size(max = 128, message = "分享密码长度不能超过 128 个字符")
        String password,
        @Schema(
                description = "过期时间；接受 ISO-8601 即时区标记或 yyyy-MM-dd HH:mm:ss（按 UTC）",
                example = "2026-09-26T00:00:00Z"
        ) String expiresAt,
        @Schema(description = "最大访问次数，0 表示不限", example = "100") Integer maxAccessCount
) {

    /**
     * 解析过期时间，格式规则与 {@link CreateShareLinkRequest} 完全一致。
     *
     * @return 解析后的即时；未提供或传空白串时为 null
     */
    public Instant parsedExpiresAt() {
        return CreateShareLinkRequest.parseExpiresAt(expiresAt);
    }
}
