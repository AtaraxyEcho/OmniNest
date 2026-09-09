package com.omninest.common.security;

import java.util.Set;

/**
 * 系统权限编码常量。
 *
 * @author OmniNest
 */
public final class Permissions {
    public static final String PROFILE_READ = "profile:read";
    public static final String PROFILE_WRITE = "profile:write";
    public static final String FILE_READ = "file:read";
    public static final String FILE_WRITE = "file:write";
    public static final String MEDIA_READ = "media:read";
    public static final String MEDIA_WRITE = "media:write";
    public static final String MEDIA_LIBRARY_MANAGE = "media:library:manage";
    public static final String PHOTO_READ = "photo:read";
    public static final String PHOTO_WRITE = "photo:write";
    public static final String PHOTO_ADMIN = "photo:admin";
    public static final String BACKDROP_READ = "backdrop:read";
    public static final String BACKDROP_WRITE = "backdrop:write";
    public static final String TASK_READ = "task:read";
    public static final String TASK_ADMIN = "task:admin";
    public static final String SYSTEM_CONFIG_READ = "system:config:read";
    public static final String SYSTEM_CONFIG_MANAGE = "system:config:manage";
    public static final String SYSTEM_USER_READ = "system:user:read";
    public static final String SYSTEM_USER_MANAGE = "system:user:manage";

    public static final Set<String> SUPER_ADMIN_PERMISSIONS = Set.of(
            PROFILE_READ,
            PROFILE_WRITE,
            FILE_READ,
            FILE_WRITE,
            MEDIA_READ,
            MEDIA_WRITE,
            MEDIA_LIBRARY_MANAGE,
            PHOTO_READ,
            PHOTO_WRITE,
            PHOTO_ADMIN,
            BACKDROP_READ,
            BACKDROP_WRITE,
            TASK_READ,
            TASK_ADMIN,
            SYSTEM_CONFIG_READ,
            SYSTEM_CONFIG_MANAGE,
            SYSTEM_USER_READ,
            SYSTEM_USER_MANAGE
    );

    private Permissions() {
    }
}
