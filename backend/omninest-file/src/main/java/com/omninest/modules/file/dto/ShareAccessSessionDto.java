package com.omninest.modules.file.dto;

import java.time.Instant;

/** 已完成分享校验的短期会话。 */
public record ShareAccessSessionDto(String sessionToken, Instant expiresAt) {
}
