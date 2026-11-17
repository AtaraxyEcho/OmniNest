package com.omninest.modules.music.service.platform;

import com.omninest.modules.music.dto.OnlineMusicDtos.PlatformUserInfo;
import java.time.Instant;

/**
 * 在线音乐平台的用户级凭据上下文。
 *
 * @param cookie 平台 Cookie
 * @param externalUserId 外部用户 ID
 * @param userInfo 脱敏用户信息
 * @param lastVerifiedAt 最近验证时间
 * @author OmniNest
 */
public record MusicPlatformCredential(
        String cookie,
        String externalUserId,
        PlatformUserInfo userInfo,
        Instant lastVerifiedAt
) {
}
