package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.repository.FileAccessRecordRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.Semaphore;
import java.util.stream.Collectors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件核心操作服务。
 * 负责最近访问、访问记录、节点复制与 ZIP 打包下载。
 * 收藏、分享、版本、外部存储与上传队列由对应的专项服务负责。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileManagerService {

    /**
     * {@code file_nodes.name} 列宽；副本追加序号时按它截短词干。
     */
    private static final int MAX_NAME_LENGTH = 255;

    private final FileNodeRepository fileNodeRepository;
    private final FileAccessRecordRepository accessRecordRepository;
    private final FileObjectRepository fileObjectRepository;
    private final ObjectStorageClient objectStorageClient;
    private final FileNodeSupport fileNodeSupport;
    private final StorageQuotaService storageQuotaService;
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
    private final SharedSpaceService sharedSpaceService;
    private final UserSyncEventRecorder syncEventRecorder;
    private final FileIndexSyncService fileIndexSyncService;

    /** 单次打包总字节上限；默认 5GB，超限让客户端分批下载。 */
    private long maxBatchDownloadTotalBytes = 5L * 1024 * 1024 * 1024;

    /**
     * 同实例并发打包上限：防止多个同步流同时占满 Servlet 线程与对象存储带宽。
     *
     * <p>跨 API 副本的全局上限由生产入口 Nginx 的 {@code limit_conn} 按凭据计数；
     * 后端端口只绑定回环地址，外部请求不会绕过该入口。两层上限必须同时存在。</p>
     */
    private final Semaphore batchDownloadSlots = new Semaphore(2);

    @Value("${file.batch-download.max-total-bytes:5368709120}")
    void setMaxBatchDownloadTotalBytes(long maxBatchDownloadTotalBytes) {
        this.maxBatchDownloadTotalBytes = maxBatchDownloadTotalBytes;
    }

    /**
     * 查询用户最近访问的文件。
     *
     * @param ownerUserId 用户 ID
     * @return 最近访问文件列表
     */
    @Transactional(readOnly = true)
    public List<FileNodeDto> listRecentFiles(UUID ownerUserId) {
        List<FileNode> nodes = accessRecordRepository.findRecentNodes(
                ownerUserId,
                SpaceType.PERSONAL,
                PageRequest.of(0, 50));
        return fileNodeSupport.toNodeDtos(nodes);
    }

    /**
     * 记录文件访问。
     *
     * @param ownerUserId 用户 ID
     * @param fileId      文件节点 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void recordAccess(UUID ownerUserId, UUID fileId) {
        fileNodeSupport.findVisibleNode(ownerUserId, fileId);
        accessRecordRepository.upsertAccess(ownerUserId, fileId, Instant.now());
    }

    /**
     * 复制文件或文件夹到目标位置。
     * 文件夹按整棵子树递归复制，节点、层级与配额口径与源子树一致。
     *
     * @param userId         用户 ID
     * @param sourceId       源文件/文件夹 ID
     * @param targetParentId 目标父文件夹 ID，null 表示复制到根目录
     * @return 新创建的文件节点
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto copyNode(UUID userId, UUID sourceId, UUID targetParentId) {
        // 共享空间内的文件可能由其他成员上传：复制按共享可见性判定，不能只认所有者。
        FileNode source = fileNodeSupport.findVisibleNode(userId, sourceId);
        fileNodeSupport.requireShareable(source);
        FileNode targetParent = fileNodeSupport.resolveCopyTargetParent(userId, targetParentId);
        UUID resolvedParentId = targetParent != null ? targetParent.getId() : null;

        // 共享空间节点的所有者仍是上传者本人：复制必须重新校验共享空间开关与
        // CAN_UPLOAD 权限矩阵。targetParent 为 null 表示复制到源空间根目录，
        // copyNodeShape 保持源空间不变，因此这里就是共享空间根目录。
        if (source.getSpaceType() == SpaceType.SHARED) {
            sharedSpaceService.requireSharedWrite(userId);
            // 复制他人上传的共享内容会生成自己名下的副本；没有下载权限时
            // 该路径等同于绕过 CAN_DOWNLOAD 获取原始内容。
            if (!userId.equals(source.getOwnerUserId()) && !sharedSpaceService.canDownload(userId)) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "无权限下载该共享文件");
            }
        }

        // 校验源文件和目标在同一空间
        if (targetParent != null && source.getSpaceType() != targetParent.getSpaceType()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "不能在不同空间之间复制文件");
        }
        String copyName = resolveAvailableName(userId, source.getSpaceType(), resolvedParentId, source.getName());
        boolean isFolder = NodeType.FOLDER.getValue().equals(source.getNodeType());
        if (isFolder && targetParent != null && isInsideSubtree(source, targetParent)) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "不能把文件夹复制到自身内部");
        }

        // 文件夹必须整棵子树一起复制，否则副本是一个空壳，用户按「复制文件夹」预期丢失全部内容；
        // 后代路径前缀已带尾斜杠，不会把同名前缀的兄弟目录卷进来。
        List<FileNode> subtree = new ArrayList<>();
        subtree.add(source);
        if (isFolder) {
            String prefix = LikePatterns.escapeSpecials(source.getNormalizedPath() + "/");
            List<FileNode> descendants = source.getSpaceType() == SpaceType.SHARED
                    ? fileNodeRepository.findBySpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                            SpaceType.SHARED, prefix)
                    : fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                            source.getOwnerUserId(), SpaceType.PERSONAL, prefix);
            subtree.addAll(descendants.stream()
                    // 父节点必须先于子节点建副本，才能按父子映射推导新路径
                    .sorted(Comparator.comparingInt(node -> node.getNormalizedPath().length()))
                    .toList());
        }

        long fileCount = subtree.stream()
                .filter(node -> NodeType.FILE.getValue().equals(node.getNodeType()))
                .count();
        long totalBytes = subtree.stream()
                .filter(node -> NodeType.FILE.getValue().equals(node.getNodeType()))
                .mapToLong(FileNode::getSizeBytes)
                .sum();
        chargeQuotaForCopy(userId, source.getSpaceType(), totalBytes, fileCount);

        Map<UUID, FileNode> parentById = new HashMap<>();
        parentById.put(source.getId(), null);
        List<UUID> copiedIds = new ArrayList<>(subtree.size());
        FileNode copiedRoot = null;
        for (FileNode node : subtree) {
            FileNode newParent = node == source ? targetParent : parentById.get(node.getParentId());
            if (node != source && newParent == null) {
                // 祖先被回收站或跨空间过滤掉时整条分支一并跳过，避免生成挂空父级的孤儿节点
                continue;
            }
            FileNode copy = copyNodeShape(node, userId, newParent, source.getSpaceType(),
                    node == source ? copyName : node.getName());
            FileNode saved = fileNodeRepository.save(copy);
            if (node == source) {
                copiedRoot = saved;
            }
            parentById.put(node.getId(), saved);
            copiedIds.add(saved.getId());
        }
        fileIndexSyncService.scheduleAfterCommit(userId, copiedIds);
        recordFileEvent(userId, copiedRoot.getId(), SyncAction.CREATED);
        log.info("文件复制完成: sourceId={}, copyId={}, ownerUserId={}, 复制节点数={}",
                sourceId, copiedRoot.getId(), userId, copiedIds.size());
        return fileNodeSupport.toNodeDto(copiedRoot);
    }

    /**
     * 复制节点的形态字段到新的目标父级下，内容对象沿用同一 {@code currentObjectId}。
     *
     * @param source 被复制的源节点
     * @param userId 复制执行者
     * @param targetParent 目标父节点，null 表示根目录
     * @param spaceType 目标空间类型
     * @param name 副本名称；顶层副本可能带 {@code (n)} 序号，子节点沿用自身名称
     */
    private FileNode copyNodeShape(FileNode source, UUID userId, FileNode targetParent, SpaceType spaceType,
            String name) {
        FileNode copy = new FileNode();
        copy.setOwnerUserId(userId);
        copy.setParentId(targetParent != null ? targetParent.getId() : null);
        copy.setNodeType(source.getNodeType());
        copy.setName(name);
        copy.setNormalizedPath(fileNodeSupport.resolveChildPath(targetParent, name));
        copy.setMimeType(source.getMimeType());
        copy.setSizeBytes(source.getSizeBytes());
        copy.setCurrentObjectId(source.getCurrentObjectId());
        copy.setSpaceType(spaceType);
        if (spaceType == SpaceType.SHARED) {
            copy.setUploadedBy(userId);
        }
        return copy;
    }

    /**
     * 为目标目录选一个未被占用的副本名称：首个保持原名，后续追加 {@code (n)} 序号。
     *
     * <p>复制是"再要一份"的动作，目标目录已有同名项是常态而不是错误，所以不返回冲突；
     * 改名与移动仍然拒绝同名，因为那是用户在指定一个确定的名字。</p>
     *
     * @param userId 副本所有者
     * @param spaceType 目标空间类型
     * @param parentId 目标父目录 ID，null 表示根目录
     * @param preferredName 期望名称，通常为源节点名称
     * @return 目标目录内唯一的名称
     */
    private String resolveAvailableName(UUID userId, SpaceType spaceType, UUID parentId, String preferredName) {
        if (!copyTargetNameExists(userId, spaceType, parentId, preferredName)) {
            return preferredName;
        }
        int suffix = 1;
        String candidate = appendCopySuffix(preferredName, suffix);
        while (copyTargetNameExists(userId, spaceType, parentId, candidate)) {
            candidate = appendCopySuffix(preferredName, ++suffix);
        }
        return candidate;
    }

    /**
     * 共享空间的同级节点可能属于不同上传者，同名冲突必须按空间而不是按所有者查询。
     */
    private boolean copyTargetNameExists(UUID userId, SpaceType spaceType, UUID parentId, String name) {
        if (spaceType == SpaceType.SHARED) {
            return parentId == null
                    ? fileNodeRepository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                            spaceType, name)
                    : fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                            spaceType, parentId, name);
        }
        return fileNodeSupport.sameNameExists(userId, spaceType, parentId, name);
    }

    /**
     * 把序号插在扩展名之前，并按 {@code file_nodes.name} 列宽截短词干。
     */
    private String appendCopySuffix(String name, int suffix) {
        String suffixText = " (" + suffix + ")";
        int dot = name.lastIndexOf('.');
        String stem = dot <= 0 ? name : name.substring(0, dot);
        String extension = dot <= 0 ? "" : name.substring(dot);
        int stemLimit = Math.max(1, MAX_NAME_LENGTH - suffixText.length() - extension.length());
        if (stem.length() > stemLimit) {
            stem = stem.substring(0, stemLimit);
        }
        return stem + suffixText + extension;
    }

    /**
     * 判断目标父目录是否位于源文件夹子树内（含指向自身）。
     */
    private boolean isInsideSubtree(FileNode source, FileNode targetParent) {
        String sourcePath = source.getNormalizedPath();
        String targetPath = targetParent.getNormalizedPath();
        if (sourcePath == null || targetPath == null) {
            return false;
        }
        return targetPath.equals(sourcePath) || targetPath.startsWith(sourcePath + "/");
    }

    /**
     * 复制产生的新节点按所属空间结算配额，个人空间按用户、共享空间按全空间单行账本。
     *
     * <p>副本按新节点计入配额：账本口径是节点数而非物理对象数，同一对象被两个节点引用
     * 时对账也计两次。不加计会让「复制后彻底删除副本」反向扣减，把已用空间刷空。</p>
     */
    private void chargeQuotaForCopy(UUID userId, SpaceType spaceType, long bytes, long fileCount) {
        if (spaceType == SpaceType.SHARED) {
            sharedSpaceQuotaService.checkQuota(bytes);
            sharedSpaceQuotaService.increaseUsage(bytes, fileCount);
            return;
        }
        storageQuotaService.checkQuota(userId, bytes);
        storageQuotaService.incrementUsage(userId, bytes);
    }

    private void recordFileEvent(UUID ownerUserId, UUID fileId, SyncAction action) {
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId,
                SyncScope.FILES,
                "FILE_NODE",
                fileId.toString(),
                action,
                null,
                Map.of()
        ));
    }

    /**
     * 将多个文件打包为 ZIP 流式下载。
     * 跳过文件夹、回收站节点和无对象数据的文件；不同目录下的同名文件自动追加序号，
     * 因为 ZipOutputStream 遇到重名条目会直接抛错并截断已经在传输的响应流。
     *
     * @param userId  用户 ID
     * @param fileIds 要打包的文件 ID 列表
     * @param out     输出流
     */
    public void packAsZip(UUID userId, List<String> fileIds, OutputStream out) {
        try (BatchDownloadLease ignored = acquireBatchDownloadLease()) {
            packZipEntries(planZipEntries(userId, fileIds), out);
        }
    }

    /**
     * 获取一个批量打包槽位；拿不到时快速失败，而不是再拉起一条同步压缩流。
     *
     * @return 需要关闭的槽位租约
     */
    public BatchDownloadLease acquireBatchDownloadLease() {
        if (!batchDownloadSlots.tryAcquire()) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "批量下载任务过多，请稍后重试");
        }
        return new BatchDownloadLease(batchDownloadSlots);
    }

    /**
     * 批量打包并发槽位租约。
     */
    public record BatchDownloadLease(Semaphore slots) implements AutoCloseable {
        @Override
        public void close() {
            slots.release();
        }
    }

    /**
     * 打包条目的数据来源：已校验归属、已定名并指向一个对象存储条目。
     *
     * @param entryName ZIP 内条目名，同名条目已追加序号
     * @param bucketName 对象桶名
     * @param objectKey 对象键
     */
    public record ZipPackEntry(String entryName, String bucketName, String objectKey) {
    }

    /**
     * 在写出任何响应字节之前完成 ID 解析、归属校验、对象定位与同名去重。
     *
     * <p>ZIP 是流式响应：响应头一旦发出就无法回滚成 JSON 错误体，客户端只会收到 HTTP 200
     * 的半截损坏压缩包。非法 ID、越权节点与缺失对象必须在这里抛出，让上层返回常规错误响应。</p>
     *
     * @param userId 请求用户 ID
     * @param fileIds 待打包文件 ID 列表
     * @return 打包条目，文件夹与回收站节点不产出条目
     */
    @Transactional(readOnly = true)
    public List<ZipPackEntry> planZipEntries(UUID userId, List<String> fileIds) {
        List<UUID> nodeIds = fileIds.stream().map(this::parseFileId).distinct().toList();
        Map<UUID, FileNode> nodesById = fileNodeRepository.findAllById(nodeIds).stream()
                .collect(Collectors.toMap(FileNode::getId, node -> node));
        List<UUID> objectIds = nodesById.values().stream()
                .filter(node -> !node.isDeleted())
                .filter(node -> NodeType.FILE.getValue().equals(node.getNodeType()))
                .map(FileNode::getCurrentObjectId)
                .filter(Objects::nonNull)
                .toList();
        Map<UUID, FileObject> objectsById = fileObjectRepository.findAllById(objectIds).stream()
                .collect(Collectors.toMap(FileObject::getId, object -> object));

        Set<String> usedEntryNames = new HashSet<>();
        List<ZipPackEntry> entries = new ArrayList<>(nodeIds.size());
        long totalBytes = 0L;
        boolean sharedChecked = false;
        boolean sharedDownloadAllowed = false;
        for (UUID nodeId : nodeIds) {
            FileNode node = nodesById.get(nodeId);
            if (node == null) {
                throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在: " + nodeId);
            }
            if (!Objects.equals(node.getOwnerUserId(), userId)) {
                if (node.getSpaceType() != SpaceType.SHARED) {
                    throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在: " + nodeId);
                }
                if (!sharedChecked) {
                    sharedDownloadAllowed = sharedSpaceService.canDownload(userId);
                    sharedChecked = true;
                }
                if (!sharedDownloadAllowed) {
                    throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在: " + nodeId);
                }
            }
            // 回收站节点与文件夹不产出条目，但请求本身合法，沿用既有跳过口径
            if (node.isDeleted() || !NodeType.FILE.getValue().equals(node.getNodeType())) {
                continue;
            }
            if (node.getCurrentObjectId() == null) {
                continue;
            }
            FileObject obj = objectsById.get(node.getCurrentObjectId());
            if (obj == null) {
                // 对象行缺失沿用既有跳过口径：这不是请求方的错，不该让整批打包失败
                continue;
            }
            entries.add(new ZipPackEntry(
                    uniqueEntryName(node.getName(), usedEntryNames),
                    obj.getBucketName(),
                    obj.getObjectKey()
            ));
            totalBytes += Math.max(0, obj.getSizeBytes());
            if (totalBytes > maxBatchDownloadTotalBytes) {
                throw new BusinessException(ErrorCode.PARAM_ERROR,
                        "打包总大小超过限制，请分批下载或单独下载大文件");
            }
        }
        return entries;
    }

    /**
     * 按已规划好的条目写出 ZIP 流。
     *
     * @param entries 打包条目
     * @param out 输出流
     */
    public void packZipEntries(List<ZipPackEntry> entries, OutputStream out) {
        try (ZipOutputStream zip = new ZipOutputStream(out)) {
            for (ZipPackEntry entry : entries) {
                zip.putNextEntry(new ZipEntry(entry.entryName()));
                try (InputStream in = objectStorageClient.getObject(
                        new ObjectStorageKey(entry.bucketName(), entry.objectKey()))) {
                    byte[] buffer = new byte[8192];
                    int len;
                    while ((len = in.read(buffer)) > 0) {
                        zip.write(buffer, 0, len);
                    }
                }
                zip.closeEntry();
            }
        } catch (IOException e) {
            log.error("ZIP 打包失败", e);
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "文件打包失败");
        }
    }

    private UUID parseFileId(String fileId) {
        try {
            return UUID.fromString(fileId);
        } catch (IllegalArgumentException e) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "文件 ID 不合法: " + fileId);
        }
    }

    /**
     * 生成 ZIP 内唯一的条目名：首个同名条目保持原名，后续追加 {@code (n)} 序号。
     *
     * <p>序号插在扩展名之前，保证解压后的文件仍能按原扩展名识别。</p>
     */
    private String uniqueEntryName(String proposedName, Set<String> usedNames) {
        String candidate = proposedName;
        int suffix = 1;
        while (!usedNames.add(candidate)) {
            candidate = appendSuffix(proposedName, suffix++);
        }
        return candidate;
    }

    private String appendSuffix(String name, int suffix) {
        int dot = name.lastIndexOf('.');
        if (dot <= 0) {
            return name + " (" + suffix + ")";
        }
        return name.substring(0, dot) + " (" + suffix + ")" + name.substring(dot);
    }
}
