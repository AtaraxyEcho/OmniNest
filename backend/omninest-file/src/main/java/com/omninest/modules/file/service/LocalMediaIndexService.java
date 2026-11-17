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
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
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
 * <p>扫描路径可能挂在 SMB/NFS/WebDAV 上，文件属性读取与 MIME 探测都是慢速网络往返，
 * 必须在数据库事务之外完成；登记阶段按批共用一个短事务，避免每个文件各开一次事务
 * 长期占用 Hikari 连接。</p>
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

    /** 单个登记事务覆盖的文件数：过小会放大提交次数，过大则长时间持有连接。 */
    private static final int REGISTER_BATCH_SIZE = 200;

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
        ProbedVideoFile probed = probe(locationRoot, file);
        TransactionTemplate writeTx = new TransactionTemplate(transactionManager);
        List<Registration> registrations = writeTx.execute(status ->
                registerBatch(ownerUserId, location, List.of(probed)));
        if (registrations == null || registrations.isEmpty()) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "本地媒体引用登记失败");
        }
        return new LocalMediaScanEntry(
                registrations.getFirst().fileNodeId(),
                probed.relativePath(),
                probed.fileName()
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
        // 文件属性在事务外一次性读取：SMB/NFS 上的 size/mtime/mime 探测都是网络往返。
        List<ProbedVideoFile> probedFiles = discoverVideoFiles(locationRoot, scanRoot);
        List<LocalMediaScanEntry> entries = new ArrayList<>();
        Set<String> seenPaths = new HashSet<>();
        int created = 0;
        int updated = 0;

        TransactionTemplate writeTx = new TransactionTemplate(transactionManager);
        for (int start = 0; start < probedFiles.size(); start += REGISTER_BATCH_SIZE) {
            List<ProbedVideoFile> batch = probedFiles.subList(
                    start, Math.min(start + REGISTER_BATCH_SIZE, probedFiles.size()));
            batch.forEach(probed -> seenPaths.add(probed.relativePath()));
            List<Registration> registrations = writeTx.execute(status ->
                    registerBatch(ownerUserId, location, batch));
            if (registrations == null) {
                continue;
            }
            for (int index = 0; index < registrations.size(); index++) {
                Registration registration = registrations.get(index);
                ProbedVideoFile probed = batch.get(index);
                entries.add(new LocalMediaScanEntry(
                        registration.fileNodeId(),
                        probed.relativePath(),
                        probed.fileName()
                ));
                if (registration.created()) {
                    created++;
                } else {
                    updated++;
                }
            }
        }
        int missing = markMissing(writeTx, ownerUserId, location.getId(), sourceRoot, seenPaths);
        log.info("本地媒体扫描完成: locationId={}, scanned={}, videos={}, created={}, updated={}, missing={}",
                location.getId(), probedFiles.size(), entries.size(), created, updated, missing);
        return new LocalMediaScanResult(
                probedFiles.size(),
                entries.size(),
                created,
                updated,
                missing,
                List.copyOf(entries)
        );
    }

    /**
     * 遍历目录并在事务外读取每个视频的大小、修改时间与 MIME。
     *
     * <p>一次 {@link Files#readAttributes} 同时取回大小与修改时间，避免两次系统调用；
     * MIME 由扩展名推导，网络盘上的 {@code probeContentType} 会产生额外往返。</p>
     */
    private List<ProbedVideoFile> discoverVideoFiles(Path locationRoot, Path scanRoot) {
        List<ProbedVideoFile> result = new ArrayList<>();
        int maxScanDepth = runtimeConfigService.maxScanDepth();
        int maxFilesPerScan = runtimeConfigService.maxFilesPerScan();
        try (Stream<Path> paths = Files.walk(scanRoot, maxScanDepth)) {
            Iterator<Path> iterator = paths.iterator();
            int scanned = 0;
            while (iterator.hasNext()) {
                Path path = iterator.next();
                BasicFileAttributes attributes;
                try {
                    attributes = Files.readAttributes(
                            path, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
                } catch (IOException exception) {
                    // 遍历途中被删除或权限变化：跳过该条目，不让整次扫描失败。
                    continue;
                }
                if (!attributes.isRegularFile()) {
                    continue;
                }
                scanned++;
                if (scanned > maxFilesPerScan) {
                    throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "本地媒体扫描文件数量超过扫描限制");
                }
                if (!isVideoFile(path)) {
                    continue;
                }
                result.add(new ProbedVideoFile(
                        toRelativePath(locationRoot, path),
                        path.getFileName().toString(),
                        attributes.size(),
                        attributes.lastModifiedTime().toInstant(),
                        mimeTypeFromName(path)
                ));
            }
            return result;
        } catch (BusinessException e) {
            throw e;
        } catch (IOException | UncheckedIOException e) {
            // Files.walk 是惰性遍历：目录被移除或权限变化时在迭代阶段抛 UncheckedIOException。
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体目录扫描失败");
        }
    }

    private ProbedVideoFile probe(Path locationRoot, Path file) {
        try {
            BasicFileAttributes attributes = Files.readAttributes(
                    file, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
            if (!attributes.isRegularFile()) {
                throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "本地媒体文件不存在");
            }
            return new ProbedVideoFile(
                    toRelativePath(locationRoot, file),
                    file.getFileName().toString(),
                    attributes.size(),
                    attributes.lastModifiedTime().toInstant(),
                    mimeTypeFromName(file)
            );
        } catch (IOException e) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "本地媒体文件读取失败");
        }
    }

    /**
     * 在一个短事务内登记一批文件，返回结果顺序与输入一致。
     *
     * <p>批量查询已存在引用、批量载入对应 FileNode、批量写入，避免逐文件 2 次查询 +
     * 1 次事务提交。</p>
     */
    private List<Registration> registerBatch(
            UUID ownerUserId,
            StorageLocation location,
            List<ProbedVideoFile> batch
    ) {
        if (batch.isEmpty()) {
            return List.of();
        }
        List<String> relativePaths = batch.stream().map(ProbedVideoFile::relativePath).toList();
        Map<String, FileContentRef> existingByPath = new HashMap<>();
        for (FileContentRef reference : contentRefRepository
                .findByOwnerUserIdAndStorageLocationIdAndRelativePathIn(
                        ownerUserId, location.getId(), relativePaths)) {
            existingByPath.put(reference.getRelativePath(), reference);
        }
        Set<UUID> existingNodeIds = new HashSet<>();
        existingByPath.values().forEach(reference -> {
            if (reference.getFileNodeId() != null) {
                existingNodeIds.add(reference.getFileNodeId());
            }
        });
        Map<UUID, FileNode> nodesById = new HashMap<>();
        if (!existingNodeIds.isEmpty()) {
            fileNodeRepository.findAllById(existingNodeIds)
                    .forEach(node -> nodesById.put(node.getId(), node));
        }

        Instant now = Instant.now();
        List<FileContentRef> dirtyRefs = new ArrayList<>(batch.size());
        List<FileNode> dirtyNodes = new ArrayList<>(batch.size());
        Map<String, Registration> registrations = new LinkedHashMap<>();
        for (ProbedVideoFile probed : batch) {
            FileContentRef existing = existingByPath.get(probed.relativePath());
            if (existing != null) {
                existing.setSizeBytes(probed.sizeBytes());
                existing.setModifiedAt(probed.modifiedAt());
                existing.setProviderEtag(probed.etag());
                existing.setAvailabilityStatus(AVAILABLE);
                existing.setLastSeenAt(now);
                existing.setMissingSince(null);
                existing.setMissingConfirmations(0);
                dirtyRefs.add(existing);
                FileNode node = nodesById.get(existing.getFileNodeId());
                if (node != null) {
                    node.setSizeBytes(probed.sizeBytes());
                    node.setMimeType(probed.mimeType());
                    dirtyNodes.add(node);
                }
                registrations.put(
                        probed.relativePath(),
                        new Registration(existing.getFileNodeId(), false));
                continue;
            }
            FileNode node = new FileNode();
            node.setId(UUID.randomUUID());
            node.setOwnerUserId(ownerUserId);
            node.setNodeType("FILE");
            node.setName(probed.fileName());
            node.setNormalizedPath("/.local-media/" + location.getId() + "/" + probed.relativePath());
            node.setMimeType(probed.mimeType());
            node.setSizeBytes(probed.sizeBytes());
            node.setCurrentObjectId(null);
            node.setSourceType(LOCAL_FILESYSTEM);
            node.setSpaceType(SpaceType.PERSONAL);
            node.setUploadedBy(ownerUserId);
            dirtyNodes.add(node);

            FileContentRef reference = new FileContentRef();
            reference.setOwnerUserId(ownerUserId);
            reference.setFileNodeId(node.getId());
            reference.setStorageLocationId(location.getId());
            reference.setRelativePath(probed.relativePath());
            reference.setProviderEtag(probed.etag());
            reference.setSizeBytes(probed.sizeBytes());
            reference.setModifiedAt(probed.modifiedAt());
            reference.setAvailabilityStatus(AVAILABLE);
            reference.setLastSeenAt(now);
            dirtyRefs.add(reference);
            registrations.put(
                    probed.relativePath(),
                    new Registration(node.getId(), true));
        }
        if (!dirtyNodes.isEmpty()) {
            fileNodeRepository.saveAll(dirtyNodes);
        }
        contentRefRepository.saveAll(dirtyRefs);
        return batch.stream().map(probed -> registrations.get(probed.relativePath())).toList();
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

    /**
     * 按扩展名推导视频 MIME。
     *
     * <p>不使用 {@code Files.probeContentType}：网络盘上它会读取文件头或查询系统 MIME 库，
     * 单个文件就可能产生数百毫秒延迟，而入库只需要一个稳定的视频类型。</p>
     */
    private String mimeTypeFromName(Path path) {
        String name = path.getFileName().toString().toLowerCase(Locale.ROOT);
        int dot = name.lastIndexOf('.');
        String extension = dot < 0 ? "" : name.substring(dot + 1);
        return switch (extension) {
            case "mkv" -> "video/x-matroska";
            case "webm" -> "video/webm";
            case "mov" -> "video/quicktime";
            case "avi" -> "video/x-msvideo";
            case "wmv" -> "video/x-ms-wmv";
            case "flv" -> "video/x-flv";
            case "ts", "m2ts" -> "video/mp2t";
            case "3gp" -> "video/3gpp";
            default -> "video/mp4";
        };
    }

    private record Registration(UUID fileNodeId, boolean created) {
    }

    /**
     * 事务外读取到的文件属性快照。
     *
     * @param relativePath 相对存储根目录的安全路径
     * @param fileName 文件名
     * @param sizeBytes 文件大小
     * @param modifiedAt 最后修改时间
     * @param mimeType 由扩展名推导的视频 MIME
     */
    private record ProbedVideoFile(
            String relativePath,
            String fileName,
            long sizeBytes,
            Instant modifiedAt,
            String mimeType
    ) {
        private String etag() {
            return sizeBytes + ":" + modifiedAt.toEpochMilli();
        }
    }
}
