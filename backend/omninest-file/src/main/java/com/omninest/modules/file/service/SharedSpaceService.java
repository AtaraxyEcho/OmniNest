package com.omninest.modules.file.service;

import com.omninest.common.config.ConfigValueProvider;
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
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.dto.RenameFileNodeRequest;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import com.omninest.modules.file.repository.SharedSpacePermissionRepository;
import com.omninest.modules.file.repository.ShareLinkRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
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
public class SharedSpaceService {

    private final FileNodeRepository fileNodeRepository;
    private final SharedSpacePermissionRepository permissionRepository;
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
    private final StorageQuotaService storageQuotaService;
    private final UserAccountQuery userAccountQuery;
    private final ShareLinkRepository shareLinkRepository;
    private final FileNodePermissionRepository fileNodePermissionRepository;
    private final ConfigValueProvider configValueProvider;
    private final ApplicationEventPublisher applicationEventPublisher;

    /**
     * 检查共享空间是否启用。
     */
    private void ensureSharedSpaceEnabled() {
        boolean enabled = configValueProvider.findByKey("share.enabled")
                .or(() -> configValueProvider.findByKey("shared_space.enabled"))
                .map(value -> "true".equalsIgnoreCase(value))
                .orElse(true);
        if (!enabled) {
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
        String parentPath = oldPath.substring(0, Math.max(oldPath.lastIndexOf('/'), 0));
        String newPath = parentPath.isEmpty() ? "/" + newName : parentPath + "/" + newName;
        node.setName(newName);
        node.setNormalizedPath(newPath);
        rewriteSubtreePaths(oldPath, newPath, SpaceType.SHARED);
        return fileNodeRepository.save(node);
    }

    /**
     * 分页重写子树规范化路径。
     *
     * <p>驱动两类写入：共享空间改名，以及跨空间移动到根目录。只给 LIKE 用转义形式，
     * 路径改写仍按原始 oldPath 长度定位，不能让反斜杠进 substring。分页收集后代，
     * 避免大目录一次加载到内存。</p>
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
        int pageNumber = 0;
        final int batchSize = 500;
        Page<FileNode> page;
        do {
            page = fileNodeRepository.findBySpaceTypeAndNormalizedPathStartingWithOrderById(
                    spaceType,
                    prefix,
                    PageRequest.of(pageNumber, batchSize, Sort.by("id"))
            );
            for (FileNode descendant : page.getContent()) {
                descendant.setNormalizedPath(
                        newPath + descendant.getNormalizedPath().substring(oldPath.length())
                );
            }
            fileNodeRepository.saveAll(page.getContent());
            pageNumber++;
        } while (page.hasNext());
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
        // 移入共享空间根目录，检查共享空间根目录下的同名冲突
        checkSharedSpaceNameConflict(node.getName(), null);
        revokeShareLinks(fileNodeId);
        revokeFilePermissions(fileNodeId);
        SubtreeStats stats = calculateSubtreeStats(node);
        // 检查共享空间配额
        sharedSpaceQuotaService.checkQuota(stats.totalBytes());
        node.setSpaceType(SpaceType.SHARED);
        node.setUploadedBy(operatorId);
        // 移入共享空间根目录：规范化路径必须跟着父级重算，否则节点会以旧父级前缀
        // 落进目标空间的另一棵子树，被那棵子树的批量软删/永久删除按前缀认领。
        String previousPath = node.getNormalizedPath();
        node.setParentId(null);
        node.setNormalizedPath("/" + node.getName());
        fileNodeRepository.save(node);
        if (NodeType.FOLDER.getValue().equals(node.getNodeType())) {
            batchMoveChildrenToShared(node.getId(), operatorId);
            rewriteSubtreePaths(previousPath, node.getNormalizedPath(), SpaceType.SHARED);
        }
        storageQuotaService.decrementUsage(operatorId, stats.totalBytes());
        sharedSpaceQuotaService.increaseUsage(stats.totalBytes(), stats.fileCount());
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
        String previousPath = node.getNormalizedPath();
        node.setSpaceType(SpaceType.PERSONAL);
        node.setOwnerUserId(targetUserId);
        // 个人空间文件不需要 uploaded_by
        node.setUploadedBy(null);
        // 移入个人空间根目录，规范化路径按新父级重算，口径与移入共享空间一致。
        node.setParentId(null);
        node.setNormalizedPath("/" + node.getName());
        fileNodeRepository.save(node);
        if (NodeType.FOLDER.getValue().equals(node.getNodeType())) {
            batchMoveChildrenToPersonal(node.getId(), targetUserId);
            rewriteSubtreePaths(previousPath, node.getNormalizedPath(), SpaceType.PERSONAL);
        }
        sharedSpaceQuotaService.decreaseUsage(stats.totalBytes(), stats.fileCount());
        storageQuotaService.incrementUsage(targetUserId, stats.totalBytes());
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
        List<UUID> allIds = new ArrayList<>(collectAllDescendantIds(node.getId()));
        allIds.add(node.getId());

        SubtreeStats stats = calculateSubtreeStats(node);

        // 批量软删除
        node.setDeleted(true);
        node.setDeletedAt(Instant.now());
        node.setDeletedBy(operatorId);
        fileNodeRepository.save(node);
        if (NodeType.FOLDER.getValue().equals(node.getNodeType())) {
            batchSoftDeleteChildren(node.getId(), operatorId);
        }

        sharedSpaceQuotaService.decreaseUsage(stats.totalBytes(), stats.fileCount());

        // 进程内事件，ownerUserId 用上传者（非操作者），确保 MediaFileSyncService 查询正确
        UUID fileOwnerUserId = node.getUploadedBy() != null ? node.getUploadedBy() : node.getOwnerUserId();
        applicationEventPublisher.publishEvent(new FileNodesSoftDeletedEvent(fileOwnerUserId, allIds, Instant.now()));
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
        if (NodeType.FILE.getValue().equals(node.getNodeType())) {
            return new SubtreeStats(node.getSizeBytes(), 1L);
        }
        String prefix = LikePatterns.escapeSpecials(node.getNormalizedPath() + "/");
        List<Object[]> rows = node.getSpaceType() == SpaceType.SHARED
                ? fileNodeRepository.sumActiveFilesUnderPathInSpace(node.getSpaceType(), prefix)
                : fileNodeRepository.sumActiveFilesUnderPathByOwner(
                        node.getOwnerUserId(), node.getSpaceType(), prefix);
        if (rows.isEmpty()) {
            return new SubtreeStats(0L, 0L);
        }
        Object[] row = rows.getFirst();
        return new SubtreeStats(toLong(row[0]), toLong(row[1]));
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
        if (NodeType.FILE.getValue().equals(node.getNodeType())) {
            return new SubtreeStats(node.getSizeBytes(), 1L);
        }
        String prefix = LikePatterns.escapeSpecials(node.getNormalizedPath() + "/");
        List<Object[]> rows = fileNodeRepository.sumDeletedFilesUnderPathInSpace(SpaceType.SHARED, prefix);
        if (rows.isEmpty()) {
            return new SubtreeStats(0L, 0L);
        }
        Object[] row = rows.getFirst();
        return new SubtreeStats(toLong(row[0]), toLong(row[1]));
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
     * 批量移动子文件到共享空间。
     * 保留文件夹层级：子文件的 parentId 指向其在共享空间中的父文件夹（同一个 node，只是 spaceType 变了）。
     */
    private void batchMoveChildrenToShared(UUID folderId, UUID previousOwner) {
        List<FileNode> children = fileNodeRepository.findByOwnerUserIdAndParentIdAndDeletedFalse(previousOwner, folderId);
        for (FileNode child : children) {
            child.setSpaceType(SpaceType.SHARED);
            child.setUploadedBy(previousOwner);
            // parentId 保持不变，指向已移动的父文件夹
        }
        fileNodeRepository.saveAll(children);
        for (FileNode child : children) {
            if (NodeType.FOLDER.getValue().equals(child.getNodeType())) {
                batchMoveChildrenToShared(child.getId(), previousOwner);
            }
        }
    }

    /**
     * 批量移动子文件到个人空间。
     * 保留文件夹层级：子文件的 parentId 指向其在个人空间中的父文件夹。
     */
    private void batchMoveChildrenToPersonal(UUID folderId, UUID targetUserId) {
        List<FileNode> children = fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, folderId);
        for (FileNode child : children) {
            child.setSpaceType(SpaceType.PERSONAL);
            child.setOwnerUserId(targetUserId);
            child.setUploadedBy(null);
            // parentId 保持不变，指向已移动的父文件夹
        }
        fileNodeRepository.saveAll(children);
        for (FileNode child : children) {
            if (NodeType.FOLDER.getValue().equals(child.getNodeType())) {
                batchMoveChildrenToPersonal(child.getId(), targetUserId);
            }
        }
    }

    /**
     * 批量软删除子文件。
     */
    private void batchSoftDeleteChildren(UUID folderId, UUID operatorId) {
        List<FileNode> children = fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, folderId);
        for (FileNode child : children) {
            child.setDeleted(true);
            child.setDeletedAt(Instant.now());
            child.setDeletedBy(operatorId);
        }
        fileNodeRepository.saveAll(children);
        for (FileNode child : children) {
            if (NodeType.FOLDER.getValue().equals(child.getNodeType())) {
                batchSoftDeleteChildren(child.getId(), operatorId);
            }
        }
    }

    /**
     * 收集所有后代文件 ID。
     */
    private List<UUID> collectAllDescendantIds(UUID folderId) {
        List<UUID> ids = new ArrayList<>();
        List<FileNode> children = fileNodeRepository.findBySpaceTypeAndParentIdAndDeletedFalse(SpaceType.SHARED, folderId);
        for (FileNode child : children) {
            ids.add(child.getId());
            if (NodeType.FOLDER.getValue().equals(child.getNodeType())) {
                ids.addAll(collectAllDescendantIds(child.getId()));
            }
        }
        return ids;
    }

    /**
     * 撤销文件关联的所有分享链接（移入共享空间时）。
     */
    private void revokeShareLinks(UUID fileNodeId) {
        shareLinkRepository.disableByResourceId(fileNodeId, Instant.now());
    }

    /**
     * 撤销文件关联的所有权限（移入共享空间时）。
     */
    private void revokeFilePermissions(UUID fileNodeId) {
        fileNodePermissionRepository.deleteByFileNodeId(fileNodeId);
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
