package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 扫码登录会话状态。
 *
 * @author OmniNest
 */
@Schema(description = "扫码登录会话")
public record QrSessionResponse(
        @Schema(description = "会话 ID") String sessionId,
        @Schema(description = "状态：PENDING/SCANNED/CONFIRMED/EXPIRED") String status,
        @Schema(description = "二维码内容或图片 URL") String qrContent,
        @Schema(description = "消息") String message
) {
}
