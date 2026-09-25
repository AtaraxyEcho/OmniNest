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
import org.springframework.stereotype.Service;

/** 存储位置内的安全只读目录浏览服务。 */
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
