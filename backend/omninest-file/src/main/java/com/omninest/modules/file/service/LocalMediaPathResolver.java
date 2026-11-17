package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.config.LocalMediaStorageProperties;
import com.omninest.modules.file.domain.StorageLocation;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.Objects;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 本地媒体路径解析与目录逃逸防护服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class LocalMediaPathResolver {

    private final LocalMediaStorageProperties properties;

    /**
     * 解析并校验存储位置根目录。
     *
     * @param location 存储位置
     * @return 已解析的真实目录
     */
    public Path resolveLocationRoot(StorageLocation location) {
        requireEnabled();
        LocalMediaStorageProperties.MountProperties mount = requireMount(location.getMountKey());
        Path configuredRoot = requireConfiguredRoot(mount);
        requireNoLinkOrReparse(configuredRoot);
        Path locationRoot = configuredRoot.resolve(normalizeRelativePath(location.getRelativeRoot())).normalize();
        requireWithin(configuredRoot, locationRoot);
        requireNoLinkOrReparse(locationRoot);
        try {
            Path realConfiguredRoot = configuredRoot.toRealPath();
            Path realLocationRoot = locationRoot.toRealPath();
            requireWithin(realConfiguredRoot, realLocationRoot);
            if (!Files.isDirectory(realLocationRoot, LinkOption.NOFOLLOW_LINKS)
                    || !Files.isReadable(realLocationRoot)) {
                throw unavailable();
            }
            return realLocationRoot;
        } catch (IOException e) {
            throw unavailable();
        }
    }

    /**
     * 解析并校验存储位置内的普通文件。
     *
     * @param location 存储位置
     * @param relativePath 相对路径
     * @return 已解析的真实文件路径
     */
    public Path resolveFile(StorageLocation location, String relativePath) {
        Path locationRoot = resolveLocationRoot(location);
        Path candidate = locationRoot.resolve(normalizeRelativePath(relativePath)).normalize();
        requireWithin(locationRoot, candidate);
        requireNoLinkOrReparse(candidate);
        try {
            Path realFile = candidate.toRealPath();
            requireWithin(locationRoot, realFile);
            if (!Files.isRegularFile(realFile, LinkOption.NOFOLLOW_LINKS) || !Files.isReadable(realFile)) {
                throw unavailable();
            }
            return realFile;
        } catch (IOException e) {
            throw unavailable();
        }
    }

    /**
     * 解析并校验存储位置内的目录。
     *
     * @param location 存储位置
     * @param relativePath 相对目录
     * @return 已解析的真实目录
     */
    public Path resolveDirectory(StorageLocation location, String relativePath) {
        Path locationRoot = resolveLocationRoot(location);
        Path candidate = locationRoot.resolve(normalizeRelativePath(relativePath)).normalize();
        requireWithin(locationRoot, candidate);
        requireNoLinkOrReparse(candidate);
        try {
            Path realDirectory = candidate.toRealPath();
            requireWithin(locationRoot, realDirectory);
            if (!Files.isDirectory(realDirectory, LinkOption.NOFOLLOW_LINKS)
                    || !Files.isReadable(realDirectory)) {
                throw unavailable();
            }
            return realDirectory;
        } catch (IOException e) {
            throw unavailable();
        }
    }

    /**
     * 生成受信任媒体进程使用的只读容器路径。
     *
     * @param location 存储位置
     * @param relativePath 文件相对路径
     * @return 容器内路径
     */
    public String resolveProcessPath(StorageLocation location, String relativePath) {
        LocalMediaStorageProperties.MountProperties mount = requireMount(location.getMountKey());
        if (mount.getProcessPath() == null || mount.getProcessPath().isBlank()) {
            throw new BusinessException(ErrorCode.MEDIA_TRANSCODE_FAILED, "本地媒体挂载未配置进程读取路径");
        }
        resolveFile(location, relativePath);
        String base = trimTrailingSlash(mount.getProcessPath().trim().replace('\\', '/'));
        String locationPart = normalizeRelativePath(location.getRelativeRoot()).toString().replace('\\', '/');
        String filePart = normalizeRelativePath(relativePath).toString().replace('\\', '/');
        return joinProcessPath(base, locationPart, filePart);
    }

    /**
     * 检查存储位置在当前节点是否可读。
     *
     * @param location 存储位置
     * @return 可读时返回 true
     */
    public boolean isAvailable(StorageLocation location) {
        if (!location.isEnabled() || !properties.isEnabled()) {
            return false;
        }
        try {
            resolveLocationRoot(location);
            return true;
        } catch (BusinessException e) {
            return false;
        }
    }

    private void requireEnabled() {
        if (!properties.isEnabled()) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体功能未启用");
        }
    }

    private LocalMediaStorageProperties.MountProperties requireMount(String mountKey) {
        requireEnabled();
        LocalMediaStorageProperties.MountProperties mount = properties.getMounts().get(mountKey);
        if (mount == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "存储位置挂载键未在部署配置中声明");
        }
        return mount;
    }

    private Path requireConfiguredRoot(LocalMediaStorageProperties.MountProperties mount) {
        if (mount.getHostPath() == null || mount.getHostPath().isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "本地媒体挂载缺少宿主机路径配置");
        }
        return Path.of(mount.getHostPath()).toAbsolutePath().normalize();
    }

    private Path normalizeRelativePath(String value) {
        String normalizedValue = value == null || value.isBlank() ? "." : value.trim();
        if (containsUnsafeCharacter(normalizedValue) || hasDrivePrefix(normalizedValue)) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "本地媒体路径必须是安全的相对路径");
        }
        try {
            Path path = Path.of(normalizedValue).normalize();
            if (path.isAbsolute() || path.startsWith("..")) {
                throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "本地媒体路径必须是安全的相对路径");
            }
            return path;
        } catch (InvalidPathException e) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "本地媒体路径格式无效");
        }
    }

    private boolean containsUnsafeCharacter(String value) {
        return value.chars().anyMatch(character -> character < 0x20 || character == 0x7f);
    }

    private boolean hasDrivePrefix(String value) {
        return value.length() >= 2
                && Character.isLetter(value.charAt(0))
                && value.charAt(1) == ':';
    }

    private void requireWithin(Path root, Path candidate) {
        if (!candidate.startsWith(root)) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "本地媒体路径超出允许目录");
        }
    }

    private void requireNoLinkOrReparse(Path candidate) {
        Path absolute = candidate.toAbsolutePath().normalize();
        Path current = absolute.getRoot();
        for (Path segment : absolute) {
            current = current == null ? segment : current.resolve(segment);
            if (!Files.exists(current, LinkOption.NOFOLLOW_LINKS)) {
                continue;
            }
            try {
                BasicFileAttributes attributes = Files.readAttributes(
                        current,
                        BasicFileAttributes.class,
                        LinkOption.NOFOLLOW_LINKS
                );
                if (attributes.isSymbolicLink() || attributes.isOther()) {
                    throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "本地媒体路径不能包含链接或重解析点");
                }
            } catch (IOException exception) {
                throw unavailable();
            }
        }
    }

    private String trimTrailingSlash(String value) {
        String result = Objects.requireNonNull(value);
        while (result.length() > 1 && result.endsWith("/")) {
            result = result.substring(0, result.length() - 1);
        }
        return result;
    }

    private String joinProcessPath(String base, String locationPart, String filePart) {
        StringBuilder result = new StringBuilder(base);
        if (!".".equals(locationPart) && !locationPart.isBlank()) {
            result.append('/').append(locationPart);
        }
        if (!".".equals(filePart) && !filePart.isBlank()) {
            result.append('/').append(filePart);
        }
        return result.toString();
    }

    private BusinessException unavailable() {
        return new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体存储位置当前不可用");
    }
}
