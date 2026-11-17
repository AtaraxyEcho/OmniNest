package com.omninest.common.util;

import java.nio.file.Path;

/**
 * 本地路径规范化与目录边界校验工具。
 *
 * @author OmniNest
 */
public final class PathSafety {
    private PathSafety() {
    }

    /**
     * 将用户路径解析到指定根目录内，并拒绝目录逃逸。
     *
     * @param baseDirectory 允许访问的根目录
     * @param userPath 用户提供的相对路径
     * @return 规范化后的绝对路径
     * @throws IllegalArgumentException 路径逃逸根目录时抛出
     */
    public static Path normalizeUnderBase(Path baseDirectory, String userPath) {
        Path base = baseDirectory.toAbsolutePath().normalize();
        Path resolved = base.resolve(userPath == null ? "" : userPath).normalize();
        if (!resolved.startsWith(base)) {
            throw new IllegalArgumentException("Path escapes base directory");
        }
        return resolved;
    }
}
