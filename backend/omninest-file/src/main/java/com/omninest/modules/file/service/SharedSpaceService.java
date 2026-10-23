package com.omninest.modules.file.service;

import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.error.BusinessException;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileNodePermission;
import com.omninest.modules.file.domain.SharedSpacePermission;
import com.omninest.modules.file.domain.SharedSpacePermission.Action;
import com.omninest.modules.file.domain.ShareLink;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.dto.RenameFileNodeRequest;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileMetricsRepository;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import com.omninest.modules.file.repository.SharedSpacePermissionRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 共享空间服务，处理共享空间的文件浏览、创建、删除和跨空间移动。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class SharedSpaceService implements SharedSpaceAccessQuery {

    /** 子树路径重写的单批条目数。 */
    private static final int SUBTREE_REWRITE_BATCH_SIZE = 500;

    private final FileNodeRepository fileNodeRepository;
    private final FileMetricsRepository fileMetricsRepository;
    private final SharedSpacePermissionRepository permissionRepository;
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
    private final StorageQuotaService storageQuotaService;
    private final UserAccountQuery userAccountQuery;
    private final ShareLinkRepository shareLinkRepository;
    private final FileNodePermissionRepository fileNodePermissionRepository;
    private final ConfigValueProvider configValueProvider;
    private final ApplicationEventPublisher applicationEventPublisher;
    private final FileIndexSyncService fileIndexSyncService;
    private final UserSyncEventRecorder syncEventRecorder;
    private final ReadThroughCache readThroughCache;

    /**
     * 检查共享空间是否启用。
     */
    private void ensureSharedSpaceEnabled() {
        if (!isSharedSpaceEnabled()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "共享空间已禁用");
        }
    }

    /**
     * 浏览共享空间目录。
     */
    @Transactional(readOnly = true)
    public List<FileNode> listSharedSpaceFiles(UUID parentId, UUID operatorId) {
        ensureSharedSpaceEnabled();
        validatePermission(operatorId, Action.CAN_BROWSE);
        if (parentId == null) {
            return fileNodeRepository.findBySpaceTypeAndParentIdIsNullAndDeletedFalse(SpaceType.SHARED);
        }
        return fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, parentId);
    }

    /**
     * 分页浏览共享空间目录。
     *
     * @param parentId 父目录 ID
     * @param operatorId 操作用户 ID
     * @param page 页码
     * @param size 每页数量
     * @return 共享空间文件分页结果
     */
    @Transactional(readOnly = true)
    public Page<FileNode> listSharedSpaceFilesPage(UUID parentId, UUID operatorId, int page, int size) {
        ensureSharedSpaceEnabled();
        validatePermission(operatorId, Action.CAN_BROWSE);
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 1), 200);
        Pageable pageable = PageRequest.of(
                safePage,
                safeSize,
                Sort.by(Sort.Order.desc("nodeType"), Sort.Order.asc("name").ignoreCase()));
        if (parentId == null) {
            return fileNodeRepository.findVisibleSharedRoot(SpaceType.SHARED, pageable);
        }
        return fileNodeRepository.findVisibleSharedChildren(SpaceType.SHARED, parentId, pageable);
    }

    /**
     * 在共享空间创建文件夹。
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNode createFolder(UUID parentFolderId, String folderName, UUID operatorId) {
        ensureSharedSpaceEnabled();
        validatePermission(operatorId, Action.CAN_CREATE_FOLDER);
        String normalizedName = normalizeNodeName(folderName);
        boolean exists = fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                SpaceType.SHARED, parentFolderId, normalizedName);
        if (exists) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件夹");
        }
        FileNode folder = new FileNode();
        folder.setSpaceType(SpaceType.SHARED);
        folder.setOwnerUserId(operatorId);
        folder.setUploadedBy(operatorId);
        folder.setParentId(parentFolderId);
        folder.setName(normalizedName);
        folder.setNodeType(NodeType.FOLDER.getValue());
        folder.setNormalizedPath(buildSharedSpacePath(parentFolderId, normalizedName));
        folder.setSizeBytes(0L);
        return fileNodeRepository.save(folder);
    }

    /**
     * 重命名共享空间文件或文件夹。
     *
     * @param fileNodeId 文件节点 ID
     * @param request 重命名请求
     * @param operatorId 操作用户 ID
     * @return 重命名后的文件节点
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNode renameSharedFile(UUID fileNodeId, RenameFileNodeRequest request, UUID operatorId) {
        ensureSharedSpaceEnabled();
        validatePermission(operatorId, Action.CAN_BROWSE);
        FileNode node = fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(fileNodeId, SpaceType.SHARED)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        boolean isUploader = Objects.equals(node.getUploadedBy(), operatorId);
        validatePermission(operatorId, isUploader ? Action.CAN_DELETE_OWN : Action.CAN_DELETE_ANY);

        String newName = normalizeNodeName(request.name());
        if (node.getName().equals(newName)) {
            return node;
        }
        if (fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(
                SpaceType.SHARED, node.getParentId(), newName)) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }

        String oldPath = node.getNormalizedPath();
        Map<UUID, List<UUID>> idsByOwner = new LinkedHashMap<>();
        idsByOwner.computeIfAbsent(node.getOwnerUserId(), key -> new ArrayList<>()).add(node.getId());
        for (Object[] row : fileNodeRepository.findActiveIdOwnerPairsUnderPathInSpace(
                SpaceType.SHARED, LikePatterns.escapeSpecials(oldPath + "/"))) {
            UUID ownerId = (UUID) row[0];
            UUID nodeId = (UUID) row[1];
            idsByOwner.computeIfAbsent(ownerId, key -> new ArrayList<>()).add(nodeId);
        }
        String parentPath = oldPath.substring(0, Math.max(oldPath.lastIndexOf('/'), 0));
        String newPath = parentPath.isEmpty() ? "/" + newName : parentPath + "/" + newName;
        node.setName(newName);
        node.setNormalizedPath(newPath);
        rewriteSubtreePaths(oldPath, newPath, SpaceType.SHARED);
        fileNodeRepository.save(node);
        // 共享文件夹里可能有其他成员上传的子项，索引重建必须落到各自所有者名下。
        idsByOwner.forEach((ownerId, ids) ->
                scheduleIndexAndEvent(ownerId, ids, node.getId(), SyncAction.UPDATED));
        return node;
    }

    /**
     * 按主键游标分页重写子树规范化路径。
     *
     * <p>驱动共享空间改名时的后代路径级联更新。只给 LIKE 用转义形式，路径改写仍按原始
     * oldPath 长度定位，不能让反斜杠进 substring。</p>
     *
     * <p>翻页必须按 ID 游标而不是 OFFSET：改写掉的 normalizedPath 就是过滤条件列，
     * 第一批记录改写后已不再匹配 oldPath 前缀，剩余记录整体前移，OFFSET 会让一半节点漏改，
     * 表现为改名后子树路径与实际层级不一致。</p>
     *
     * @param oldPath 移动前的节点路径
     * @param newPath 移动后的节点路径
     * @param spaceType 后代所在空间
     */
    private void rewriteSubtreePaths(String oldPath, String newPath, SpaceType spaceType) {
        if (oldPath == null || oldPath.equals(newPath)) {
            return;
        }
        String prefix = LikePatterns.escapeSpecials(oldPath + "/");
        UUID afterId = new UUID(0L, 0L);
        while (true) {
            List<FileNode> batch = fileNodeRepository.findSubtreeBySpaceTypeAfterId(
                    spaceType, prefix, afterId, PageRequest.of(0, SUBTREE_REWRITE_BATCH_SIZE));
            if (batch.isEmpty()) {
                return;
            }
            for (FileNode descendant : batch) {
                descendant.setNormalizedPath(
                        newPath + descendant.getNormalizedPath().substring(oldPath.length())
                );
                afterId = descendant.getId();
            }
            fileNodeRepository.saveAll(batch);
        }
    }

    /**
     * 跨空间移动：个人 → 共享。
     */
    @Transactional(rollbackFor = Exception.class)
    public void moveToSharedSpace(UUID fileNodeId, UUID operatorId) {
        ensureSharedSpaceEnabled();
        validatePermission(operatorId, Action.CAN_BROWSE);
        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileNodeId, operatorId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        validatePermission(operatorId, Action.CAN_MOVE_TO);
        // 已经在共享空间里的节点再次移入会重复扣减个人配额并让共享配额虚增
        if (node.getSpaceType() == SpaceType.SHARED) {
            throw new BusinessException(ErrorCode.CONFLICT, "文件已在共享空间中");
        }
        List<FileNode> subtree = collectPersonalSubtreeNodes(node);
        requireMovableSources(subtree);
        // 移入共享空间根目录，检查共享空间根目录下的同名冲突
        checkSharedSpaceNameConflict(node.getName(), null);
        List<UUID> subtreeIds = subtree.stream().map(FileNode::getId).toList();
        revokeShareLinksForNodes(subtreeIds);
        revokeFilePermissionsForNodes(subtreeIds);
        SubtreeStats stats = calculateSubtreeStats(node);
        // 检查共享空间配额
        sharedSpaceQuotaService.checkQuota(stats.totalBytes());
        String oldPath = node.getNormalizedPath();
        node.setSpaceType(SpaceType.SHARED);
        node.setUploadedBy(operatorId);
        // 移入共享空间根目录：规范化路径必须跟着父级重算，否则节点会以旧父级前缀
        // 落进目标空间的另一棵子树，被那棵子树的批量软删/永久删除按前缀认领。
        node.setParentId(null);
        node.setNormalizedPath("/" + node.getName());
        fileNodeRepository.save(node);
        if (NodeType.FOLDER.getValue().equals(node.getNodeType())) {
            moveDescendants(subtree, node, oldPath, SpaceType.SHARED, operatorId, operatorId);
        }
        storageQuotaService.decrementUsage(operatorId, stats.totalBytes());
        sharedSpaceQuotaService.increaseUsage(stats.totalBytes(), stats.fileCount());
        scheduleIndexAndEvent(operatorId, subtreeIds, node.getId(), SyncAction.UPDATED);
        log.info("文件从个人空间移入共享空间: fileId={}, operatorId={}, totalSize={}, fileCount={}",
                fileNodeId, operatorId, stats.totalBytes(), stats.fileCount());
    }

    /**
     * 跨空间移动：共享 → 个人。
     * 仅上传者本人或具有 CAN_DELETE_ANY 权限的管理员可操作。
     */
    @Transactional(rollbackFor = Exception.class)
    public void moveToPersonalSpace(UUID fileNodeId, UUID targetUserId) {
        ensureSharedSpaceEnabled();
        validatePermission(targetUserId, Action.CAN_BROWSE);
        FileNode node = fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(fileNodeId, SpaceType.SHARED)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        // 权限检查：上传者可移回自己的，管理员可移回任何人的
        boolean isUploader = Objects.equals(node.getUploadedBy(), targetUserId);
        Action action = isUploader ? Action.CAN_MOVE_FROM : Action.CAN_DELETE_ANY;
        validatePermission(targetUserId, action);
        SubtreeStats stats = calculateSubtreeStats(node);
        // 检查个人配额是否足够
        storageQuotaService.checkQuota(targetUserId, stats.totalBytes());
        // 个人空间根目录同名会复用同一规范化路径前缀，先拦冲突再改空间与路径。
        if (fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                targetUserId, SpaceType.PERSONAL, node.getName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "个人空间根目录已存在同名节点");
        }
        // 子孙节点在改空间后会退出 SHARED 查询条件，必须在变更前收集索引同步范围。
        String oldPath = node.getNormalizedPath();
        String descendantPrefix = oldPath + "/";
        List<UUID> subtreeIds = new ArrayList<>(
                fileNodeRepository.findActiveIdsUnderPathInSpace(
                        SpaceType.SHARED, LikePatterns.escapeSpecials(descendantPrefix)));
        subtreeIds.add(node.getId());
        node.setSpaceType(SpaceType.PERSONAL);
        node.setOwnerUserId(targetUserId);
        // 个人空间文件不需要 uploaded_by
        node.setUploadedBy(null);
        // 移入个人空间根目录，规范化路径按新父级重算，口径与移入共享空间一致。
        node.setParentId(null);
        node.setNormalizedPath("/" + node.getName());
        fileNodeRepository.save(node);
        if (NodeType.FOLDER.getValue().equals(node.getNodeType())) {
            List<FileNode> descendants = fileNodeRepository.findAllById(subtreeIds).stream()
                    .filter(candidate -> !candidate.getId().equals(node.getId()))
                    .toList();
            moveDescendants(descendants, node, oldPath, SpaceType.PERSONAL, targetUserId, null);
        }
        sharedSpaceQuotaService.decreaseUsage(stats.totalBytes(), stats.fileCount());
        storageQuotaService.incrementUsage(targetUserId, stats.totalBytes());
        // 按变更前收集的完整子树投递索引同步：此刻子孙已变为 PERSONAL，
        // 再按 SHARED 条件查询会返回空列表，导致整棵子树搜索索引漏更新。
        scheduleIndexAndEvent(targetUserId, subtreeIds, node.getId(), SyncAction.UPDATED);
        log.info("文件从共享空间移入个人空间: fileId={}, targetUserId={}, totalSize={}, fileCount={}",
                fileNodeId, targetUserId, stats.totalBytes(), stats.fileCount());
    }

    /**
     * 删除共享空间文件。
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteSharedFile(UUID fileNodeId, UUID operatorId) {
        ensureSharedSpaceEnabled();
        validatePermission(operatorId, Action.CAN_BROWSE);
        FileNode node = fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(fileNodeId, SpaceType.SHARED)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        validateSharedLifecycleOperator(operatorId, node);

        // 先收集所有后代 ID（软删除后查询会返回空）
        String descendantPrefix = node.getNormalizedPath() + "/";
        List<UUID> allIds = new ArrayList<>(fileNodeRepository.findActiveIdsUnderPathInSpace(
                SpaceType.SHARED, LikePatterns.escapeSpecials(descendantPrefix)));
        allIds.add(node.getId());

        SubtreeStats stats = calculateSubtreeStats(node);

        // 批量软删除：按空间与路径前缀一次更新，避免逐层递归逐行保存。
        Instant deletedAt = Instant.now();
        node.setDeleted(true);
        node.setDeletedAt(deletedAt);
        node.setDeletedBy(operatorId);
        fileNodeRepository.save(node);
        if (NodeType.FOLDER.getValue().equals(node.getNodeType())) {
            fileNodeRepository.softDeleteSubtreeInSpace(
                    SpaceType.SHARED,
                    LikePatterns.escapeSpecials(descendantPrefix),
                    deletedAt,
                    operatorId
            );
        }

        sharedSpaceQuotaService.decreaseUsage(stats.totalBytes(), stats.fileCount());

        // 按实际归属人分组：共享文件夹里可能有多个成员上传的媒体，漏掉任何一组都会让
        // 对应成员的媒体库继续显示已删除内容。
        Map<UUID, List<UUID>> idsByOwner = new HashMap<>();
        Set<UUID> groupedIds = new HashSet<>();
        for (FileNode deletedNode : fileNodeRepository.findAllById(allIds)) {
            UUID owner = deletedNode.getUploadedBy() != null
                    ? deletedNode.getUploadedBy() : deletedNode.getOwnerUserId();
            idsByOwner.computeIfAbsent(owner, key -> new ArrayList<>()).add(deletedNode.getId());
            groupedIds.add(deletedNode.getId());
        }
        // 查询未命中（并发清理或仓储未回表）时仍要保证根节点与后代能收到失效事件。
        UUID fallbackOwner = node.getUploadedBy() != null ? node.getUploadedBy() : node.getOwnerUserId();
        for (UUID id : allIds) {
            if (groupedIds.add(id)) {
                idsByOwner.computeIfAbsent(fallbackOwner, key -> new ArrayList<>()).add(id);
            }
        }
        idsByOwner.forEach((owner, ids) -> {
            applicationEventPublisher.publishEvent(new FileNodesSoftDeletedEvent(owner, ids, deletedAt));
            fileIndexSyncService.scheduleAfterCommit(owner, ids);
            syncEventRecorder.record(new SyncEventCommand(
                    owner, SyncScope.FILES, "FILE_NODE", ids.getFirst().toString(),
                    SyncAction.DELETED, null, Map.of()));
        });
        log.info("共享空间文件删除: fileId={}, operatorId={}, totalSize={}, fileCount={}",
                fileNodeId, operatorId, stats.totalBytes(), stats.fileCount());
    }

    /**
     * 校验共享空间操作权限。
     * 角色信息通过用户查询端口一次性加载。
     */
    @Transactional(readOnly = true)
    /**
     * 校验共享空间是否可写入（导入/上传前置）。
     *
     * @param operatorId 操作用户
     */
    public void requireSharedWrite(UUID operatorId) {
        ensureSharedSpaceEnabled();
        validatePermission(operatorId, Action.CAN_UPLOAD);
    }

    public void validatePermission(UUID userId, Action action) {
        UserAccountSummary user = userAccountQuery.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        if (user.roleIds().isEmpty()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "用户未分配角色");
        }
        boolean allowed = permissionRepository.findByRoleIdIn(user.roleIds()).stream()
                .anyMatch(perm -> perm.isAllowed(action));
        if (!allowed) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权限执行此操作");
        }
    }

    /**
     * 判断用户能否浏览共享空间，供跨模块的列表可见性使用。
     *
     * <p>{@link #validatePermission} 用异常表达"不允许"，而列表查询只需要一个布尔量：
     * 把共享空间开关与角色矩阵一并折算成可见性，避免调用方靠捕获异常控制流程。
     * 判定顺序与 {@code listSharedSpaceFiles} 一致（先开关、再 CAN_BROWSE）。</p>
     *
     * @param userId 用户 ID
     * @return 共享空间启用且角色授予 CAN_BROWSE 时返回 true
     */
    @Override
    @Transactional(readOnly = true)
    public boolean canBrowse(UUID userId) {
        return canAccess(userId, Action.CAN_BROWSE);
    }

    /**
     * 判断用户能否下载共享空间内容，用于批量下载的逐项过滤。
     *
     * <p>下载同时要求浏览与下载两个权限位；任一未授予都返回 false，不抛出异常。</p>
     *
     * @param userId 用户 ID
     * @return 可下载时返回 true
     */
    @Override
    @Transactional(readOnly = true)
    public boolean canDownload(UUID userId) {
        return canAccess(userId, Action.CAN_BROWSE) && canAccess(userId, Action.CAN_DOWNLOAD);
    }

    /**
     * 校验共享空间浏览权限（含共享空间开关）。
     *
     * @param userId 用户 ID
     */
    public void validateBrowsePermission(UUID userId) {
        ensureSharedSpaceEnabled();
        validatePermission(userId, Action.CAN_BROWSE);
    }

    /**
     * 校验共享空间下载权限（含浏览权限与共享空间开关）。
     *
     * <p>{@code CAN_DOWNLOAD} 是独立权限位，只校验 CAN_BROWSE 会让关闭下载的角色
     * 仍能通过下载地址接口取到内容。</p>
     *
     * @param userId 用户 ID
     */
    @Override
    public void validateDownloadPermission(UUID userId) {
        ensureSharedSpaceEnabled();
        validatePermission(userId, Action.CAN_BROWSE);
        validatePermission(userId, Action.CAN_DOWNLOAD);
    }

    private boolean canAccess(UUID userId, Action action) {
        if (!isSharedSpaceEnabled()) {
            return false;
        }
        UserAccountSummary user = userAccountQuery.findById(userId).orElse(null);
        if (user == null || user.roleIds().isEmpty()) {
            return false;
        }
        return permissionRepository.findByRoleIdIn(user.roleIds()).stream()
                .anyMatch(permission -> permission.isAllowed(action));
    }

    /**
     * 共享空间开关当前是否开启。
     */
    private boolean isSharedSpaceEnabled() {
        return configValueProvider.findByKey("share.enabled")
                .or(() -> configValueProvider.findByKey("shared_space.enabled"))
                .map(value -> "true".equalsIgnoreCase(value))
                .orElse(true);
    }

    /**
     * 校验共享空间节点的删除或恢复权限：上传者要求 CAN_DELETE_OWN，其他成员要求 CAN_DELETE_ANY。
     *
     * <p>恢复与删除共用同一判定，否则管理员删除的文件会出现在其回收站中却无法恢复；
     * 回收站列表按 deleted_by 展示，而节点 owner_user_id 仍指向上传者，两处必须对齐。</p>
     *
     * @param operatorId 操作用户 ID
     * @param node 共享空间节点
     */
    public void validateSharedLifecycleOperator(UUID operatorId, FileNode node) {
        boolean isUploader = Objects.equals(node.getUploadedBy(), operatorId);
        validatePermission(operatorId, isUploader ? Action.CAN_DELETE_OWN : Action.CAN_DELETE_ANY);
    }

    /**
     * 子树结算结果：字节数与文件数必须成对记账，删除或恢复整个文件夹时不能只记一个文件。
     *
     * @param totalBytes 子树内文件总字节数
     * @param fileCount 子树内文件数
     */
    public record SubtreeStats(long totalBytes, long fileCount) {
    }

    /**
     * 汇总文件或文件夹子树的字节数与文件数。
     *
     * <p>共享空间目录内混有各成员上传的文件，按文件夹创建者的 ownerUserId 过滤会漏算
     * 其他人上传的字节与文件，因此共享空间按空间类型加路径前缀统计，个人空间按所有者统计。</p>
     */
    private SubtreeStats calculateSubtreeStats(FileNode node) {
        String prefix = LikePatterns.escapeSpecials(node.getNormalizedPath() + "/");
        if (NodeType.FILE.getValue().equals(node.getNodeType())) {
            long versionBytes = fileMetricsRepository.sumVersionBytesForNode(
                    node.getId(), node.getSpaceType().getValue(), false);
            return new SubtreeStats(node.getSizeBytes() + versionBytes, 1L);
        }
        List<Object[]> rows = node.getSpaceType() == SpaceType.SHARED
                ? fileNodeRepository.sumActiveFilesUnderPathInSpace(node.getSpaceType(), prefix)
                : fileNodeRepository.sumActiveFilesUnderPathByOwner(
                        node.getOwnerUserId(), node.getSpaceType(), prefix);
        long totalBytes = 0L;
        long fileCount = 0L;
        if (!rows.isEmpty()) {
            Object[] row = rows.getFirst();
            totalBytes = toLong(row[0]);
            fileCount = toLong(row[1]);
        }
        // 账本与夜间重算都把历史版本对象计入字节，删除/移动同口径释放。
        totalBytes += node.getSpaceType() == SpaceType.SHARED
                ? fileMetricsRepository.sumVersionBytesUnderPathInSpace(
                        node.getSpaceType().getValue(), prefix, false)
                : fileMetricsRepository.sumVersionBytesUnderPathByOwner(
                        node.getOwnerUserId(), prefix, false);
        return new SubtreeStats(totalBytes, fileCount);
    }

    /**
     * 汇总共享空间回收站子树恢复后应补记的用量。
     *
     * <p>口径与删除时一致：文件节点按自身字节计一个文件，目录按路径前缀汇总子树文件；
     * 共享空间按空间类型加前缀统计，不按目录创建者过滤，否则会漏记其他成员上传的内容。
     * 恢复前子树仍处于软删除状态，活跃口径的汇总只能得到零，因此这里读取已删除文件。</p>
     *
     * @param node 回收站中的共享空间节点
     * @return 恢复后应补记的字节数与文件数
     */
    public SubtreeStats calculateRestoreSubtreeStats(FileNode node) {
        String prefix = LikePatterns.escapeSpecials(node.getNormalizedPath() + "/");
        if (NodeType.FILE.getValue().equals(node.getNodeType())) {
            long versionBytes = fileMetricsRepository.sumVersionBytesForNode(
                    node.getId(), SpaceType.SHARED.getValue(), true);
            return new SubtreeStats(node.getSizeBytes() + versionBytes, 1L);
        }
        List<Object[]> rows = fileNodeRepository.sumDeletedFilesUnderPathInSpace(SpaceType.SHARED, prefix);
        long totalBytes = 0L;
        long fileCount = 0L;
        if (!rows.isEmpty()) {
            Object[] row = rows.getFirst();
            totalBytes = toLong(row[0]);
            fileCount = toLong(row[1]);
        }
        totalBytes += fileMetricsRepository.sumVersionBytesUnderPathInSpace(
                SpaceType.SHARED.getValue(), prefix, true);
        return new SubtreeStats(totalBytes, fileCount);
    }

    /**
     * 把子树后代迁入目标空间并按新根路径重写规范化路径。
     *
     * <p>路径在 Java 侧按旧根路径长度精确截取，避免数据库 {@code substring} 的
     * 1-based 偏移与根路径斜杠拼接出错；后代实体已由一次子树查询载入，不产生逐层 N+1。</p>
     */
    private void moveDescendants(
            List<FileNode> descendants,
            FileNode root,
            String oldRootPath,
            SpaceType targetSpace,
            UUID targetOwner,
            UUID uploadedBy
    ) {
        List<FileNode> changed = new ArrayList<>();
        for (FileNode descendant : descendants) {
            if (descendant.getId().equals(root.getId())) {
                continue;
            }
            String oldPath = descendant.getNormalizedPath();
            if (oldPath == null || oldPath.length() <= oldRootPath.length()
                    || !oldPath.startsWith(oldRootPath + "/")) {
                continue;
            }
            descendant.setSpaceType(targetSpace);
            descendant.setOwnerUserId(targetOwner);
            descendant.setUploadedBy(uploadedBy);
            descendant.setNormalizedPath(root.getNormalizedPath()
                    + oldPath.substring(oldRootPath.length()));
            changed.add(descendant);
        }
        if (!changed.isEmpty()) {
            fileNodeRepository.saveAll(changed);
        }
    }

    private long toLong(Object value) {
        return value instanceof Number number ? number.longValue() : 0L;
    }

    private String normalizeNodeName(String name) {
        String normalized = name == null ? "" : name.trim();
        if (normalized.isEmpty() || ".".equals(normalized) || "..".equals(normalized)
                || normalized.contains("/") || normalized.contains("\\")
                || normalized.indexOf('\0') >= 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "文件名称不合法");
        }
        return normalized;
    }

    /**
     * 撤销整棵子树的公开分享链接，并同步清掉读穿透缓存。
     *
     * <p>按资源集合一次查询、一次批量停用，避免对子树每个节点各跑一轮全表扫描。</p>
     */
    private void revokeShareLinksForNodes(List<UUID> fileNodeIds) {
        if (fileNodeIds.isEmpty()) {
            return;
        }
        List<ShareLink> active = shareLinkRepository.findByResourceIdInAndDisabledAtIsNull(fileNodeIds);
        shareLinkRepository.disableByResourceIdIn(fileNodeIds, Instant.now());
        for (ShareLink link : active) {
            readThroughCache.invalidate("omninest:share:link:" + link.getTokenHash());
        }
    }

    /**
     * 撤销整棵子树的细粒度权限（移入共享空间时）。
     */
    private void revokeFilePermissionsForNodes(List<UUID> fileNodeIds) {
        if (!fileNodeIds.isEmpty()) {
            fileNodePermissionRepository.deleteByFileNodeIdIn(fileNodeIds);
        }
    }

    /**
     * 本地只读与系统派生节点不参与个人/共享配额结算，禁止跨空间移动。
     */
    private void requireMovableSources(List<FileNode> nodes) {
        for (FileNode node : nodes) {
            if ("DERIVED".equals(node.getSourceType())
                    || SourceType.LOCAL_FILESYSTEM.getValue().equals(node.getSourceType())) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "只读或派生文件不能移入共享空间");
            }
        }
    }

    private List<FileNode> collectPersonalSubtreeNodes(FileNode root) {
        List<FileNode> nodes = new ArrayList<>();
        nodes.add(root);
        if (!NodeType.FOLDER.getValue().equals(root.getNodeType())) {
            return nodes;
        }
        List<FileNode> descendants = fileNodeRepository
                .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        root.getOwnerUserId(),
                        SpaceType.PERSONAL,
                        LikePatterns.escapeSpecials(root.getNormalizedPath() + "/"));
        nodes.addAll(descendants);
        return nodes;
    }

    private void scheduleIndexAndEvent(
            UUID ownerUserId, List<UUID> ids, UUID rootId, SyncAction action) {
        if (ids.isEmpty()) {
            return;
        }
        fileIndexSyncService.scheduleAfterCommit(ownerUserId, ids);
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId, SyncScope.FILES, "FILE_NODE", rootId.toString(), action, null, Map.of()));
    }

    /**
     * 检查共享空间同名冲突。
     */
    private void checkSharedSpaceNameConflict(String name, UUID parentId) {
        if (fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(SpaceType.SHARED, parentId, name)) {
            throw new BusinessException(ErrorCode.CONFLICT, "共享空间已存在同名文件");
        }
    }

    /**
     * 构建共享空间的 normalized_path。
     */
    private String buildSharedSpacePath(UUID parentFolderId, String name) {
        if (parentFolderId == null) {
            return "/" + name;
        }
        FileNode parent = fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(parentFolderId, SpaceType.SHARED)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在"));
        return parent.getNormalizedPath() + "/" + name;
    }

    /**
     * 设置角色的共享空间权限。
     */
    @Transactional(rollbackFor = Exception.class)
    public void setRolePermission(UUID roleId, Boolean canBrowse, Boolean canUpload,
            Boolean canDownload, Boolean canDeleteOwn, Boolean canDeleteAny,
            Boolean canMoveTo, Boolean canMoveFrom, Boolean canCreateFolder) {
        SharedSpacePermission perm = permissionRepository.findByRoleId(roleId)
                .orElseGet(() -> {
                    SharedSpacePermission p = new SharedSpacePermission();
                    p.setRoleId(roleId);
                    return p;
                });
        if (canBrowse != null) perm.setCanBrowse(canBrowse);
        if (canUpload != null) perm.setCanUpload(canUpload);
        if (canDownload != null) perm.setCanDownload(canDownload);
        if (canDeleteOwn != null) perm.setCanDeleteOwn(canDeleteOwn);
        if (canDeleteAny != null) perm.setCanDeleteAny(canDeleteAny);
        if (canMoveTo != null) perm.setCanMoveTo(canMoveTo);
        if (canMoveFrom != null) perm.setCanMoveFrom(canMoveFrom);
        if (canCreateFolder != null) perm.setCanCreateFolder(canCreateFolder);
        permissionRepository.save(perm);
        log.info("共享空间权限更新: roleId={}", roleId);
    }
}
