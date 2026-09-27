package com.omninest.modules.file.service;

import com.omninest.common.api.PageResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.dto.StorageLocationDtos.StorageDirectoryDto;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.util.stream.Stream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/** 存储位置内的安全只读目录浏览服务。 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StorageDirectoryService {

    private final StorageLocationService storageLocationService;
    private final LocalMediaPathResolver pathResolver;

    /** 懒加载指定目录的直接子目录。 */
    public PageResponse<StorageDirectoryDto> listChildren(
            UUID ownerUserId,
            UUID storageLocationId,
            String parentRelativePath,
            int page,
            int size
    ) {
        StorageLocation location = storageLocationService.requireAccessibleLocation(ownerUserId, storageLocationId);
        return listChildren(location, parentRelativePath, page, size);
    }

    /** 从部署白名单挂载内浏览目录，不暴露物理路径。 */
    public PageResponse<StorageDirectoryDto> listMountChildren(
            String mountKey,
            String parentRelativePath,
            int page,
            int size
    ) {
        StorageLocation location = new StorageLocation();
        location.setMountKey(mountKey);
        location.setRelativeRoot(".");
        location.setEnabled(true);
        return listChildren(location, parentRelativePath, page, size);
    }

    /**
     * 在挂载根下确保约定子目录存在（仅固定安全名称）。
     *
     * <p>LOCAL 挂载对用户内容只读；此处仅初始化 Movie/TV/Anime 目录骨架。
     * 目录不可写或创建失败时返回 false，不中断业务，由扫描侧表现为空库。</p>
     *
     * @param mountKey 部署可信挂载键
     * @param directoryNames 约定目录名列表（由调用方给出固定值）
     * @return 全部已存在或创建成功时 true
     */
    public boolean ensureMountDirectories(String mountKey, List<String> directoryNames) {
        StorageLocation location = new StorageLocation();
        location.setMountKey(mountKey);
        location.setRelativeRoot(".");
        location.setEnabled(true);
        try {
            Path mountRoot = pathResolver.resolveLocationRoot(location);
            for (String name : directoryNames) {
                if (hasIgnoreCaseChild(mountRoot, name)) {
                    continue;
                }
                Path child = mountRoot.resolve(name).normalize();
                if (!child.startsWith(mountRoot)) {
                    return false;
                }
                Files.createDirectories(child);
            }
            return true;
        } catch (IOException | BusinessException exception) {
            log.warn("挂载目录初始化失败: mountKey={}", mountKey, exception);
            return false;
        }
    }


    private boolean hasIgnoreCaseChild(Path mountRoot, String name) {
        try (Stream<Path> children = Files.list(mountRoot)) {
            return children.anyMatch(path -> {
                Path fileName = path.getFileName();
                return fileName != null && fileName.toString().equalsIgnoreCase(name);
            });
        } catch (IOException exception) {
            log.debug("列举挂载子目录失败，视为已存在: mountRoot={}", mountRoot, exception);
            return true;
        }
    }
    private PageResponse<StorageDirectoryDto> listChildren(
            StorageLocation location,
            String parentRelativePath,
            int page,
            int size
    ) {
        String parent = parentRelativePath == null || parentRelativePath.isBlank() ? "." : parentRelativePath;
        Path locationRoot = pathResolver.resolveLocationRoot(location);
        Path directory = pathResolver.resolveDirectory(location, parent);
        int safePage = Math.max(0, page);
        int safeSize = com.omninest.common.api.PageClamps.safeSize(size);
        try (Stream<Path> children = Files.list(directory)) {
            List<Path> directories = children
                    .filter(path -> Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS))
                    .filter(path -> !Files.isSymbolicLink(path))
                    .sorted(Comparator.comparing(path -> path.getFileName().toString(), String.CASE_INSENSITIVE_ORDER))
                    .toList();
            int from = Math.min(directories.size(), safePage * safeSize);
            int to = Math.min(directories.size(), from + safeSize);
            List<StorageDirectoryDto> items = directories.subList(from, to).stream()
                    .map(path -> toDto(locationRoot, path))
                    .toList();
            return PageResponse.of(items, safePage, safeSize, directories.size());
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体目录读取失败");
        }
    }

    private StorageDirectoryDto toDto(Path locationRoot, Path path) {
        try {
            Path realPath = path.toRealPath(LinkOption.NOFOLLOW_LINKS);
            if (!realPath.startsWith(locationRoot)) {
                throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "本地媒体目录超出存储位置");
            }
            String relativePath = locationRoot.relativize(realPath).toString().replace('\\', '/');
            return new StorageDirectoryDto(
                    relativePath,
                    realPath.getFileName().toString(),
                    relativePath,
                    hasDirectoryChild(realPath)
            );
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体目录解析失败");
        }
    }

    private boolean hasDirectoryChild(Path directory) {
        try (Stream<Path> children = Files.list(directory)) {
            return children.anyMatch(path -> Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)
                    && !Files.isSymbolicLink(path));
        } catch (IOException exception) {
            return false;
        }
    }
}
