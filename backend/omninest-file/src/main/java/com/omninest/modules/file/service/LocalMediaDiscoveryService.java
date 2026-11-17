package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.dto.LocalMediaDiscoveredFile;
import com.omninest.modules.file.dto.LocalMediaDiscoveryResult;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.Iterator;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.function.Consumer;
import java.util.stream.Stream;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 以有界流方式遍历本地媒体目录，不创建 FileNode 或媒体实体。
 */
@Service
@RequiredArgsConstructor
public class LocalMediaDiscoveryService {
    private static final Set<String> VIDEO_EXTENSIONS = Set.of(
            "mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "ts", "m2ts", "3gp"
    );

    private final StorageLocationService storageLocationService;
    private final LocalMediaPathResolver pathResolver;
    private final LocalMediaRuntimeConfigService runtimeConfigService;

    /**
     * 流式发现来源下的视频文件。
     *
     * @param ownerUserId 当前用户
     * @param storageLocationId 存储位置
     * @param sourceRelativeRoot 来源相对根
     * @param visitor 每发现一个视频立即回调
     * @return 遍历汇总
     */
    public LocalMediaDiscoveryResult discover(
            UUID ownerUserId,
            UUID storageLocationId,
            String sourceRelativeRoot,
            Consumer<LocalMediaDiscoveredFile> visitor
    ) {
        StorageLocation location = storageLocationService.requireAccessibleLocation(ownerUserId, storageLocationId);
        Path locationRoot = pathResolver.resolveLocationRoot(location);
        Path scanRoot = pathResolver.resolveDirectory(location, sourceRelativeRoot);
        int maxScanDepth = runtimeConfigService.maxScanDepth();
        int maxFilesPerScan = runtimeConfigService.maxFilesPerScan();
        int scanned = 0;
        int videos = 0;
        try (Stream<Path> paths = Files.walk(scanRoot, maxScanDepth)) {
            Iterator<Path> iterator = paths.iterator();
            while (iterator.hasNext()) {
                Path path = iterator.next();
                if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
                    continue;
                }
                scanned++;
                if (scanned > maxFilesPerScan) {
                    throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "本地媒体发现文件数量超过扫描限制");
                }
                if (!isVideoFile(path)) {
                    continue;
                }
                visitor.accept(describe(locationRoot, path));
                videos++;
            }
            return new LocalMediaDiscoveryResult(scanned, videos);
        } catch (BusinessException e) {
            throw e;
        } catch (IOException e) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体目录发现失败");
        }
    }

    private LocalMediaDiscoveredFile describe(Path locationRoot, Path path) {
        try {
            Path realPath = path.toRealPath(LinkOption.NOFOLLOW_LINKS);
            if (!realPath.startsWith(locationRoot)) {
                throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "本地媒体文件超出存储位置目录");
            }
            BasicFileAttributes attributes = Files.readAttributes(
                    realPath,
                    BasicFileAttributes.class,
                    LinkOption.NOFOLLOW_LINKS
            );
            String relativePath = locationRoot.relativize(realPath).toString().replace('\\', '/');
            return new LocalMediaDiscoveredFile(
                    relativePath,
                    realPath.getFileName().toString(),
                    attributes.size(),
                    attributes.lastModifiedTime().toInstant(),
                    attributes.size() + ":" + attributes.lastModifiedTime().toMillis()
            );
        } catch (IOException e) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体文件属性读取失败");
        }
    }

    private boolean isVideoFile(Path path) {
        String name = path.getFileName().toString();
        int dot = name.lastIndexOf('.');
        if (dot < 0 || dot == name.length() - 1) {
            return false;
        }
        return VIDEO_EXTENSIONS.contains(name.substring(dot + 1).toLowerCase(Locale.ROOT));
    }
}
