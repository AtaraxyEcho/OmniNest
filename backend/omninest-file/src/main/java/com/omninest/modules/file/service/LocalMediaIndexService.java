package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileContentRef;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.dto.LocalMediaScanResult;
import com.omninest.modules.file.dto.LocalMediaScanEntry;
import com.omninest.modules.file.repository.FileContentRefRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Stream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 本地只读媒体目录发现与文件引用登记服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class LocalMediaIndexService {
    private static final String AVAILABLE = "AVAILABLE";
    private static final String MISSING = "MISSING";
    private static final String LOCAL_FILESYSTEM = "LOCAL_FILESYSTEM";
    private static final Set<String> VIDEO_EXTENSIONS = Set.of(
            "mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "ts", "m2ts", "3gp"
    );

    private final StorageLocationService storageLocationService;
    private final LocalMediaPathResolver pathResolver;
    private final LocalMediaRuntimeConfigService runtimeConfigService;
    private final FileContentRefRepository contentRefRepository;
    private final FileNodeRepository fileNodeRepository;
    private final PlatformTransactionManager transactionManager;

    /**
     * 将用户已确认的候选文件登记为本地只读 FileNode。
     *
     * <p>相对路径会在登记前由 File 模块重新解析，不能直接信任候选表中的文件属性。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param storageLocationId 存储位置 ID
     * @param relativePath 安全相对路径
     * @return 可供 Media 分类器消费的文件节点条目
     */
    public LocalMediaScanEntry registerSelected(
            UUID ownerUserId,
            UUID storageLocationId,
            String relativePath
    ) {
        StorageLocation location = storageLocationService.requireAccessibleLocation(ownerUserId, storageLocationId);
        Path locationRoot = pathResolver.resolveLocationRoot(location);
        Path file = pathResolver.resolveFile(location, relativePath);
        String verifiedRelativePath = toRelativePath(locationRoot, file);
        TransactionTemplate writeTx = new TransactionTemplate(transactionManager);
        Registration registration = writeTx.execute(status -> register(
                ownerUserId,
                location,
                verifiedRelativePath,
                file
        ));
        if (registration == null) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "本地媒体引用登记失败");
        }
        return new LocalMediaScanEntry(
                registration.fileNodeId(),
                verifiedRelativePath,
                file.getFileName().toString()
        );
    }

    /**
     * 扫描当前用户可访问的本地媒体目录并登记视频引用。
     *
     * @param ownerUserId 所有者用户 ID
     * @param storageLocationId 存储位置 ID
     * @param sourceRelativeRoot 来源相对目录
     * @return 扫描结果
     */
    public LocalMediaScanResult scan(UUID ownerUserId, UUID storageLocationId, String sourceRelativeRoot) {
        StorageLocation location = storageLocationService.requireAccessibleLocation(ownerUserId, storageLocationId);
        String sourceRoot = normalizeRelativePath(sourceRelativeRoot);
        Path locationRoot = pathResolver.resolveLocationRoot(location);
        Path scanRoot = pathResolver.resolveDirectory(location, sourceRoot);
        List<Path> videoFiles = discoverVideoFiles(scanRoot);
        List<LocalMediaScanEntry> entries = new ArrayList<>();
        Set<String> seenPaths = new HashSet<>();
        int created = 0;
        int updated = 0;

        TransactionTemplate writeTx = new TransactionTemplate(transactionManager);
        for (Path file : videoFiles) {
            String relativePath = toRelativePath(locationRoot, file);
            seenPaths.add(relativePath);
            Registration registration = writeTx.execute(status -> register(
                    ownerUserId,
                    location,
                    relativePath,
                    file
            ));
            if (registration == null) {
                continue;
            }
            entries.add(new LocalMediaScanEntry(
                    registration.fileNodeId(),
                    relativePath,
                    file.getFileName().toString()
            ));
            if (registration.created()) {
                created++;
            } else {
                updated++;
            }
        }
        int missing = markMissing(writeTx, ownerUserId, location.getId(), sourceRoot, seenPaths);
        log.info("本地媒体扫描完成: locationId={}, scanned={}, videos={}, created={}, updated={}, missing={}",
                location.getId(), videoFiles.size(), entries.size(), created, updated, missing);
        return new LocalMediaScanResult(
                videoFiles.size(),
                entries.size(),
                created,
                updated,
                missing,
                List.copyOf(entries)
        );
    }

    private List<Path> discoverVideoFiles(Path scanRoot) {
        List<Path> result = new ArrayList<>();
        int maxScanDepth = runtimeConfigService.maxScanDepth();
        int maxFilesPerScan = runtimeConfigService.maxFilesPerScan();
        try (Stream<Path> paths = Files.walk(scanRoot, maxScanDepth)) {
            Iterator<Path> iterator = paths.iterator();
            int scanned = 0;
            while (iterator.hasNext()) {
                Path path = iterator.next();
                if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
                    continue;
                }
                scanned++;
                if (scanned > maxFilesPerScan) {
                    throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "本地媒体扫描文件数量超过扫描限制");
                }
                if (isVideoFile(path)) {
                    result.add(path);
                }
            }
            return result;
        } catch (BusinessException e) {
            throw e;
        } catch (IOException e) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体目录扫描失败");
        }
    }

    private Registration register(
            UUID ownerUserId,
            StorageLocation location,
            String relativePath,
            Path file
    ) {
        FileContentRef existing = contentRefRepository
                .findByOwnerUserIdAndStorageLocationIdAndRelativePath(ownerUserId, location.getId(), relativePath)
                .orElse(null);
        try {
            long size = Files.size(file);
            FileTime modifiedTime = Files.getLastModifiedTime(file, LinkOption.NOFOLLOW_LINKS);
            String mimeType = resolveMimeType(file);
            if (existing != null) {
                existing.setSizeBytes(size);
                existing.setModifiedAt(modifiedTime.toInstant());
                existing.setProviderEtag(fingerprint(size, modifiedTime));
                existing.setAvailabilityStatus(AVAILABLE);
                existing.setLastSeenAt(Instant.now());
                existing.setMissingSince(null);
                existing.setMissingConfirmations(0);
                contentRefRepository.save(existing);
                fileNodeRepository.findById(existing.getFileNodeId()).ifPresent(node -> {
                    node.setSizeBytes(size);
                    node.setMimeType(mimeType);
                    fileNodeRepository.save(node);
                });
                return new Registration(existing.getFileNodeId(), false);
            }

            FileNode node = new FileNode();
            node.setOwnerUserId(ownerUserId);
            node.setNodeType("FILE");
            node.setName(file.getFileName().toString());
            node.setNormalizedPath("/.local-media/" + location.getId() + "/" + relativePath);
            node.setMimeType(mimeType);
            node.setSizeBytes(size);
            node.setCurrentObjectId(null);
            node.setSourceType(LOCAL_FILESYSTEM);
            node.setSpaceType(SpaceType.PERSONAL);
            node.setUploadedBy(ownerUserId);
            FileNode savedNode = fileNodeRepository.save(node);

            FileContentRef reference = new FileContentRef();
            reference.setOwnerUserId(ownerUserId);
            reference.setFileNodeId(savedNode.getId());
            reference.setStorageLocationId(location.getId());
            reference.setRelativePath(relativePath);
            reference.setProviderEtag(fingerprint(size, modifiedTime));
            reference.setSizeBytes(size);
            reference.setModifiedAt(modifiedTime.toInstant());
            reference.setAvailabilityStatus(AVAILABLE);
            reference.setLastSeenAt(Instant.now());
            contentRefRepository.save(reference);
            return new Registration(savedNode.getId(), true);
        } catch (IOException e) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体文件读取失败");
        }
    }

    private int markMissing(
            TransactionTemplate writeTx,
            UUID ownerUserId,
            UUID storageLocationId,
            String sourceRoot,
            Set<String> seenPaths
    ) {
        // 扫描目录名里的 _ 或 % 必须按字面量匹配，否则相邻目录会被当成本子树。
        String prefix = LikePatterns.escapeSpecials(
                ".".equals(sourceRoot) ? "" : sourceRoot + "/");
        List<UUID> missingIds = contentRefRepository
                .findByOwnerUserIdAndStorageLocationIdAndRelativePathStartingWith(
                        ownerUserId,
                        storageLocationId,
                        prefix
                )
                .stream()
                .filter(reference -> !seenPaths.contains(reference.getRelativePath()))
                .map(FileContentRef::getId)
                .toList();
        if (missingIds.isEmpty()) {
            return 0;
        }
        Integer updated = writeTx.execute(status -> contentRefRepository.updateAvailabilityStatus(missingIds, MISSING));
        return updated == null ? 0 : updated;
    }

    private String normalizeRelativePath(String value) {
        String raw = value == null || value.isBlank() ? "." : value.trim();
        if (raw.indexOf('\0') >= 0) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "影视库来源必须是安全的相对路径");
        }
        try {
            Path path = Path.of(raw).normalize();
            if (path.isAbsolute() || path.startsWith("..")) {
                throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "影视库来源必须是安全的相对路径");
            }
            return path.toString().replace('\\', '/');
        } catch (InvalidPathException e) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "影视库来源路径格式无效");
        }
    }

    private String toRelativePath(Path locationRoot, Path file) {
        try {
            Path realFile = file.toRealPath();
            if (!realFile.startsWith(locationRoot)) {
                throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "本地媒体文件超出存储位置目录");
            }
            return locationRoot.relativize(realFile).toString().replace('\\', '/');
        } catch (IOException e) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体文件路径解析失败");
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

    private String resolveMimeType(Path path) throws IOException {
        String detected = Files.probeContentType(path);
        if (detected != null && detected.toLowerCase(Locale.ROOT).startsWith("video/")) {
            return detected;
        }
        String name = path.getFileName().toString().toLowerCase(Locale.ROOT);
        if (name.endsWith(".mkv")) {
            return "video/x-matroska";
        }
        if (name.endsWith(".webm")) {
            return "video/webm";
        }
        return "video/mp4";
    }

    private String fingerprint(long size, FileTime modifiedTime) {
        return size + ":" + modifiedTime.toMillis();
    }

    private record Registration(UUID fileNodeId, boolean created) {
    }
}
