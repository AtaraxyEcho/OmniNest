package com.omninest.modules.user.dto;

import java.util.Set;
import java.util.UUID;

/**
 * 跨模块使用的最小用户目录数据结构。
 *
 * @author OmniNest
 */
public final class UserDirectoryDtos {

    private UserDirectoryDtos() {
    }

    /** 用户授权画像。 */
    public record UserAuthorizationProfile(
            UUID id,
            String status,
            Set<String> roles,
            Set<String> permissions
    ) {
    }

    /** 媒体库授权用户候选。 */
    public record UserDirectoryEntry(
            UUID id,
            String username,
            String displayName,
            String status
    ) {
    }
}
