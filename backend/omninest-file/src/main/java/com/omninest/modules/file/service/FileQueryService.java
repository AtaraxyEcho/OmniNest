package com.omninest.modules.file.service;

import com.omninest.common.error.BusinessException;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePermission;
import com.omninest.modules.file.domain.FileTypeCategories;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.CreateFolderRequest;
import com.omninest.modules.file.dto.BatchItemResult;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.dto.FileProcessInput;
import com.omninest.modules.file.dto.MoveFileNodeRequest;
import com.omninest.modules.file.dto.RenameFileNodeRequest;
import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.search.service.FileSearchIndexService;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件节点查询与个人空间写操作服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileQueryService {
    private static final int LIFECYCLE_BATCH_SIZE = 500;
    private final FileNodeRepository fileNodeRepository;
    private final FileContentAccessService fileContentAccessService;
    private final FilePermissionService filePermissionService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final ApplicationEventPublisher eventPublisher;
    private final FileSearchIndexService fileSearchIndexService;
    private final UserSyncEventRecorder syncEventRecorder;

    @Transactional(readOnly = true)
    public List<FileNodeDto> listFiles(UUID ownerUserId, UUID parentId) {
        return listFiles(ownerUserId, parentId, null);
    }

    @Transactional(readOnly = true)
    public List<FileNodeDto> listFiles(UUID ownerUserId, UUID parentId, String category) {
        String normalizedCategory = normalizeCategory(category);
        List<FileNode> nodes = listNodesForView(ownerUserId, parentId, normalizedCategory);
        return nodes.stream()
                .filter(node -> matchesCategory(node, normalizedCategory))
                .sorted(Comparator.comparing(FileNode::getNodeType).reversed()
                        .thenComparing(FileNode::getName, String.CASE_INSENSITIVE_ORDER))
                .map(this::toDto)
                .toList();
    }

    /**
     * 分页列出个人空间文件节点。
     *
     * @param ownerUserId 当前用户 ID
     * @param parentId 父目录 ID
     * @param category 文件分类
     * @param page 页码
     * @param size 每页数量
     * @return 文件节点分页结果
     */
    @Transactional(readOnly = true)
    public Page<FileNodeDto> listFilesPage(
            UUID ownerUserId,
            UUID parentId,
            String category,
            int page,
            int size) {
        String normalizedCategory = normalizeCategory(category);
        Pageable pageable = filePageable(page, size);
        Page<FileNode> nodes;
        if (normalizedCategory == null) {
            nodes = parentId == null
                    ? fileNodeRepository.findVisiblePersonalRoot(ownerUserId, SpaceType.PERSONAL, pageable)
                    : fileNodeRepository.findVisiblePersonalChildren(ownerUserId, parentId, pageable);
        } else if (parentId == null) {
            nodes = fileNodeRepository.findVisiblePersonalCategoryPage(
                    ownerUserId, SpaceType.PERSONAL, normalizedCategory, pageable);
        } else {
            nodes = fileNodeRepository.findVisibleSubtreeCategoryPage(
                    ownerUserId,
                    resolveSubtreePrefix(ownerUserId, parentId),
                    normalizedCategory,
                    pageable);
        }
        return nodes.map(this::toDto);
    }

    private String resolveSubtreePrefix(UUID ownerUserId, UUID parentId) {
        FileNode parent = resolveParent(ownerUserId, parentId);
        return parent.getNormalizedPath() + "/";
    }

    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto createFolder(UUID ownerUserId, CreateFolderRequest request) {
        String folderName = normalizeNodeName(request.name(), "文件夹名称不合法");
        FileNode parent = resolveParent(ownerUserId, request.parentId());
        if (sameNameExists(ownerUserId, request.parentId(), folderName)) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件夹");
        }
        FileNode folder = new FileNode();
        folder.setOwnerUserId(ownerUserId);
        folder.setParentId(request.parentId());
        folder.setNodeType("FOLDER");
        folder.setName(folderName);
        folder.setNormalizedPath(resolveChildPath(parent, folderName));
        folder.setSizeBytes(0L);
        folder.setSpaceType(SpaceType.PERSONAL);
        FileNode saved = fileNodeRepository.save(folder);
        recordFileEvent(ownerUserId, saved.getId(), SyncAction.CREATED);
        return toDto(saved);
    }

    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto renameNode(UUID ownerUserId, UUID fileId, RenameFileNodeRequest request) {
        String newName = normalizeNodeName(request.name(), "文件名称不合法");
        FileNode node = findActiveNode(ownerUserId, fileId);
        requireManagedNode(node);
        if (node.getName().equals(newName)) {
            return toDto(node);
        }
        if (sameNameExists(ownerUserId, node.getParentId(), newName)) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }

        String oldPath = node.getNormalizedPath();
        String newPath = resolveSiblingPath(node, newName);
        node.setName(newName);
        node.setNormalizedPath(newPath);
        updateActiveDescendantPaths(ownerUserId, oldPath, newPath);
        FileNode saved = fileNodeRepository.save(node);
        // 更新 Lucene 搜索索引中的文件名
        fileSearchIndexService.indexFile(saved.getId(), ownerUserId, saved.getName(), null);
        recordFileEvent(ownerUserId, saved.getId(), SyncAction.UPDATED);
        return toDto(saved);
    }

    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto moveNode(UUID ownerUserId, UUID fileId, MoveFileNodeRequest request) {
        FileNode node = findActiveNode(ownerUserId, fileId);
        requireManagedNode(node);
        UUID targetParentId = request.parentId();
        if (Objects.equals(node.getParentId(), targetParentId)) {
            return toDto(node);
        }

        FileNode targetParent = resolveParent(ownerUserId, targetParentId);
        // 校验空间类型一致：不能通过普通 move 跨空间移动
        validateSameSpace(node, targetParent);
        if (targetParent != null && isSelfOrDescendant(node, targetParent)) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "不能移动到自身子目录");
        }
        if (sameNameExists(ownerUserId, targetParentId, node.getName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "目标目录下已存在同名文件");
        }

        String oldPath = node.getNormalizedPath();
        String newPath = resolveChildPath(targetParent, node.getName());
        node.setParentId(targetParentId);
        node.setNormalizedPath(newPath);
        updateActiveDescendantPaths(ownerUserId, oldPath, newPath);
        FileNode saved = fileNodeRepository.save(node);
        recordFileEvent(ownerUserId, saved.getId(), SyncAction.UPDATED);
        return toDto(saved);
    }

    @Transactional(rollbackFor = Exception.class)
    public void deleteNode(UUID ownerUserId, UUID fileId) {
        FileNode node = findActiveNode(ownerUserId, fileId);
        requireManagedNode(node);
        Instant deletedAt = Instant.now();
        markDeleted(node, ownerUserId, deletedAt);
        fileNodeRepository.save(node);
        fileSearchIndexService.deleteFile(node.getId(), ownerUserId);
        eventPublisher.publishEvent(new FileNodesSoftDeletedEvent(ownerUserId, List.of(node.getId()), deletedAt));

        while (true) {
            List<UUID> descendantIds = fileNodeRepository.findActiveIdsByPathPrefix(
                            ownerUserId,
                            node.getNormalizedPath() + "/",
                            PageRequest.of(0, LIFECYCLE_BATCH_SIZE)
                    )
                    .getContent();
            if (descendantIds.isEmpty()) {
                break;
            }
            fileNodeRepository.softDeleteIds(ownerUserId, descendantIds, deletedAt);
            fileSearchIndexService.deleteFiles(descendantIds, ownerUserId);
            eventPublisher.publishEvent(new FileNodesSoftDeletedEvent(
                    ownerUserId,
                    List.copyOf(descendantIds),
                    deletedAt
            ));
        }
        recordFileEvent(ownerUserId, node.getId(), SyncAction.DELETED);
    }

    @Transactional(readOnly = true)
    public Page<FileNodeDto> listRecycleBinPage(UUID ownerUserId, SpaceType spaceType, int page, int size) {
        Pageable pageable = FilePageRequests.of(
                page,
                size,
                Sort.by(Sort.Order.desc("deletedAt"), Sort.Order.desc("id")));
        // 个人空间按 ownerUserId 查询，共享空间按 deletedBy 查询（上传者 ≠ 删除者）
        Page<FileNode> nodes = spaceType == SpaceType.SHARED
                ? fileNodeRepository.findSharedRecyclePage(ownerUserId, spaceType, pageable)
                : fileNodeRepository.findPersonalRecyclePage(ownerUserId, spaceType, pageable);
        return nodes.map(this::toDto);
    }

    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto restoreNode(UUID ownerUserId, UUID fileId) {
        FileNode node = fileNodeRepository.findByIdAndOwnerUserId(fileId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        requireManagedNode(node);
        if (!node.isDeleted()) {
            return toDto(node);
        }
        fileLifecycleGuard.requireRestorable(ownerUserId, fileId);
        ensureParentAvailable(ownerUserId, node);
        if (sameNameExists(ownerUserId, node.getParentId(), node.getName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }

        markRestored(node);
        List<FileNode> descendants = fileNodeRepository.findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedTrue(
                ownerUserId,
                node.getNormalizedPath() + "/"
        );
        descendants.forEach(this::markRestored);
        fileNodeRepository.saveAll(descendants);
        FileNode saved = fileNodeRepository.save(node);

        // 发布恢复事件，触发 Lucene 重新索引
        List<UUID> restoredIds = new ArrayList<>();
        restoredIds.add(saved.getId());
        descendants.stream().map(FileNode::getId).forEach(restoredIds::add);
        eventPublisher.publishEvent(new FileNodesRestoredEvent(ownerUserId, List.copyOf(restoredIds), Instant.now()));
        recordFileEvent(ownerUserId, saved.getId(), SyncAction.RESTORED);

        return toDto(saved);
    }

    /**
     * 批量软删除文件节点及其后代
     */
    @Transactional(rollbackFor = Exception.class)
    public List<BatchItemResult> batchDeleteNodes(UUID ownerUserId, List<UUID> fileIds) {
        List<BatchItemResult> results = new ArrayList<>();
        Map<UUID, FileNode> nodesById = fileNodeRepository
                .findByOwnerUserIdAndIdInAndDeletedFalse(ownerUserId, fileIds).stream()
                .collect(Collectors.toMap(FileNode::getId, node -> node, (left, right) -> left));
        Instant deletedAt = Instant.now();
        List<UUID> allDeletedIds = new ArrayList<>();
        List<FileNode> allToSave = new ArrayList<>();
        for (UUID fileId : fileIds) {
            FileNode node = nodesById.get(fileId);
            if (node == null) {
                results.add(BatchItemResult.skipped(fileId, "文件不存在或已删除"));
                continue;
            }
            try {
                requireManagedNode(node);
            } catch (BusinessException exception) {
                results.add(BatchItemResult.failed(fileId, exception.errorCode().name(), exception.getMessage()));
                continue;
            }
            markDeleted(node, ownerUserId, deletedAt);
            allToSave.add(node);
            allDeletedIds.add(node.getId());
            List<FileNode> descendants = fileNodeRepository
                    .findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedFalse(
                            ownerUserId, node.getNormalizedPath() + "/");
            descendants.forEach(d -> markDeleted(d, ownerUserId, deletedAt));
            allToSave.addAll(descendants);
            descendants.stream().map(FileNode::getId).forEach(allDeletedIds::add);
            results.add(BatchItemResult.success(fileId));
        }
        if (!allToSave.isEmpty()) {
            fileNodeRepository.saveAll(allToSave);
            fileSearchIndexService.deleteFiles(allDeletedIds, ownerUserId);
            eventPublisher.publishEvent(new FileNodesSoftDeletedEvent(ownerUserId, allDeletedIds, deletedAt));
            recordLibraryInvalidation(ownerUserId, SyncAction.DELETED, allDeletedIds.size());
        }
        return results;
    }

    /**
     * 批量恢复已删除的文件节点及其后代
     */
    @Transactional(rollbackFor = Exception.class)
    public List<BatchItemResult> batchRestoreNodes(UUID ownerUserId, List<UUID> fileIds) {
        List<BatchItemResult> results = new ArrayList<>();
        Instant restoredAt = Instant.now();
        List<UUID> restoredIds = new ArrayList<>();
        List<FileNode> allToSave = new ArrayList<>();
        for (UUID fileId : fileIds) {
            FileNode node = fileNodeRepository.findByIdAndOwnerUserId(fileId, ownerUserId).orElse(null);
            if (node == null) {
                results.add(BatchItemResult.failed(fileId, "FILE_NOT_FOUND", "文件不存在"));
                continue;
            }
            if (!node.isDeleted()) {
                results.add(BatchItemResult.skipped(fileId, "文件未删除"));
                continue;
            }
            try {
                requireManagedNode(node);
                fileLifecycleGuard.requireRestorable(ownerUserId, node.getId());
                ensureParentAvailable(ownerUserId, node);
                if (sameNameExists(ownerUserId, node.getParentId(), node.getName())) {
                    throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件: " + node.getName());
                }
            } catch (BusinessException exception) {
                results.add(BatchItemResult.failed(fileId, exception.errorCode().name(), exception.getMessage()));
                continue;
            }
            markRestored(node);
            allToSave.add(node);
            restoredIds.add(node.getId());
            List<FileNode> descendants = fileNodeRepository
                    .findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedTrue(
                            ownerUserId, node.getNormalizedPath() + "/");
            descendants.forEach(this::markRestored);
            allToSave.addAll(descendants);
            descendants.stream().map(FileNode::getId).forEach(restoredIds::add);
            results.add(BatchItemResult.success(fileId));
        }
        if (!allToSave.isEmpty()) {
            fileNodeRepository.saveAll(allToSave);
            eventPublisher.publishEvent(new FileNodesRestoredEvent(ownerUserId, List.copyOf(restoredIds), restoredAt));
            recordLibraryInvalidation(ownerUserId, SyncAction.RESTORED, restoredIds.size());
        }
        return results;
    }

    /**
     * 批量移动文件节点到目标文件夹
     */
    @Transactional(rollbackFor = Exception.class)
    public List<BatchItemResult> batchMoveNodes(UUID ownerUserId, List<UUID> fileIds, UUID targetParentId) {
        FileNode targetParent = resolveParent(ownerUserId, targetParentId);
        List<BatchItemResult> results = new ArrayList<>();
        Map<UUID, FileNode> nodesById = fileNodeRepository
                .findByOwnerUserIdAndIdInAndDeletedFalse(ownerUserId, fileIds).stream()
                .collect(Collectors.toMap(FileNode::getId, node -> node, (left, right) -> left));
        int movedCount = 0;
        for (UUID fileId : fileIds) {
            FileNode node = nodesById.get(fileId);
            if (node == null) {
                results.add(BatchItemResult.skipped(fileId, "文件不存在或已删除"));
                continue;
            }
            try {
                requireManagedNode(node);
                if (!Objects.equals(node.getParentId(), targetParentId)) {
                    validateSameSpace(node, targetParent);
                    if (targetParent != null && isSelfOrDescendant(node, targetParent)) {
                        throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "不能移动到自身子目录: " + node.getName());
                    }
                    if (sameNameExists(ownerUserId, targetParentId, node.getName())) {
                        throw new BusinessException(ErrorCode.CONFLICT, "目标目录下已存在同名文件: " + node.getName());
                    }
                    String oldPath = node.getNormalizedPath();
                    String newPath = resolveChildPath(targetParent, node.getName());
                    node.setParentId(targetParentId);
                    node.setNormalizedPath(newPath);
                    updateActiveDescendantPaths(ownerUserId, oldPath, newPath);
                    fileNodeRepository.save(node);
                    movedCount++;
                }
                results.add(BatchItemResult.success(fileId));
            } catch (BusinessException exception) {
                results.add(BatchItemResult.failed(fileId, exception.errorCode().name(), exception.getMessage()));
            }
        }
        if (movedCount > 0) {
            recordLibraryInvalidation(ownerUserId, SyncAction.UPDATED, movedCount);
        }
        return results;
    }
    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrl(UUID ownerUserId, UUID fileId) {
        FileNode node = findActiveNode(ownerUserId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件夹不能直接下载");
        }
        return fileContentAccessService.createDownloadUrl(node);
    }

    /**
     * 批量为当前用户拥有的文件创建短期下载地址。
     *
     * <p>缺失、已删除、非 FILE 节点或解析失败的文件不会出现在结果中。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileIds 文件节点 ID 集合
     * @return 文件节点 ID 到下载地址的映射
     */
    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrls(UUID ownerUserId, Collection<UUID> fileIds) {
        if (fileIds == null || fileIds.isEmpty()) {
            return Map.of();
        }
        List<FileNode> nodes = fileNodeRepository.findAllById(fileIds).stream()
                .filter(node -> !node.isDeleted()
                        && NodeType.FILE.getValue().equals(node.getNodeType())
                        && ownerUserId.equals(node.getOwnerUserId()))
                .toList();
        return fileContentAccessService.createDownloadUrls(nodes);
    }

    /**
     * 为当前用户拥有或被授予查看权限的文件创建短期下载地址。
     *
     * @param userId 当前用户 ID
     * @param fileId 文件节点 ID
     * @return 下载地址
     */
    @Transactional(readOnly = true)
    public FileDownloadUrlDto createReadableDownloadUrl(UUID userId, UUID fileId) {
        FileNode node = findReadableFileNode(userId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件夹不能直接下载");
        }
        return fileContentAccessService.createDownloadUrl(node);
    }

    /**
     * 创建受信任媒体进程可读取的输入。
     *
     * @param ownerUserId 当前用户 ID
     * @param fileId 文件节点 ID
     * @return 媒体进程输入
     */
    @Transactional(readOnly = true)
    public FileProcessInput createOwnedProcessInput(UUID ownerUserId, UUID fileId) {
        FileNode node = findActiveNode(ownerUserId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件节点没有可读取内容");
        }
        return fileContentAccessService.createProcessInput(node);
    }

    /**
     * 打开当前用户拥有的文件内容流。
     *
     * <p>调用方必须关闭返回句柄。该接口用于进程内模块协作，避免业务模块直接访问文件 Repository。
     *
     * @param ownerUserId 当前用户 ID
     * @param fileId 文件节点 ID
     * @return 文件内容流句柄
     */
    @Transactional(readOnly = true)
    public FileContentStream openOwnedFileContent(UUID ownerUserId, UUID fileId) {
        FileNode node = findActiveNode(ownerUserId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件节点没有可读取内容");
        }
        return fileContentAccessService.open(node);
    }

    /**
     * 打开当前用户拥有或被授予查看权限的文件内容流。
     *
     * <p>调用方必须关闭返回句柄。共享文件仅在用户具备查看权限时允许读取。
     *
     * @param userId 当前用户 ID
     * @param fileId 文件节点 ID
     * @return 文件内容流句柄
     */
    @Transactional(readOnly = true)
    public FileContentStream openReadableFileContent(UUID userId, UUID fileId) {
        FileNode node = findReadableFileNode(userId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件节点没有可读取内容");
        }
        return fileContentAccessService.open(node);
    }

    private FileNode findReadableFileNode(UUID userId, UUID fileId) {
        FileNode node = fileNodeRepository.findByIdAndDeletedFalse(fileId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (node.getOwnerUserId().equals(userId)) {
            return node;
        }
        FilePermission permission = filePermissionService.resolvePermission(fileId, userId);
        if (!node.isShared() || !permission.allowView()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权查看文件");
        }
        return node;
    }

    /**
     * 校验文件属于指定用户且内容类型为图片。
     *
     * @param ownerUserId 所属用户标识
     * @param fileId 文件节点标识
     */
    @Transactional(readOnly = true)
    public void validateOwnedImage(UUID ownerUserId, UUID fileId) {
        FileNode node = findActiveNode(ownerUserId, fileId);
        String mimeType = node.getMimeType();
        if (!NodeType.FILE.getValue().equals(node.getNodeType())
                || mimeType == null
                || !mimeType.toLowerCase(Locale.ROOT).startsWith("image/")) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面文件必须是有效图片");
        }
    }

    /**
     * 生成共享文件的下载 URL。
     * 如果是拥有者直接返回，否则检查共享权限。
     */
    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrlForShared(UUID userId, UUID fileId) {
        FileNode node = fileNodeRepository.findByIdAndDeletedFalse(fileId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (node.getOwnerUserId().equals(userId)) {
            return createDownloadUrl(userId, fileId);
        }
        if (!node.isShared()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "文件未共享");
        }
        FilePermission perm = filePermissionService.resolvePermission(fileId, userId);
        if (!perm.allowDownload()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无下载权限");
        }
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件夹不能直接下载");
        }
        return fileContentAccessService.createDownloadUrl(node);
    }

    private FileNode findActiveNode(UUID ownerUserId, UUID fileId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
    }

    private FileNode resolveParent(UUID ownerUserId, UUID parentId) {
        if (parentId == null) {
            return null;
        }
        FileNode parent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(parentId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在"));
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "父级节点不是文件夹");
        }
        return parent;
    }

    /**
     * 校验源文件和目标父文件夹属于同一空间。
     * 跨空间移动必须通过 SharedSpaceService.moveToSharedSpace/moveToPersonalSpace。
     */
    private void validateSameSpace(FileNode source, FileNode targetParent) {
        if (targetParent == null) {
            // 移动到根目录：个人空间文件只能移到个人根目录
            if (source.getSpaceType() != SpaceType.PERSONAL) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "共享空间文件不能移动到个人空间根目录，请使用「移回个人空间」功能");
            }
            return;
        }
        if (source.getSpaceType() != targetParent.getSpaceType()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "不能在不同空间之间移动文件，请使用「移到共享空间」或「移回个人空间」功能");
        }
    }

    private void ensureParentAvailable(UUID ownerUserId, FileNode node) {
        if (node.getParentId() == null) {
            return;
        }
        resolveParent(ownerUserId, node.getParentId());
    }

    private boolean sameNameExists(UUID ownerUserId, UUID parentId, String name) {
        if (parentId == null) {
            return fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(ownerUserId, name);
        }
        return fileNodeRepository.existsByOwnerUserIdAndParentIdAndNameAndDeletedFalse(ownerUserId, parentId, name);
    }

    private String normalizeNodeName(String rawName, String errorMessage) {
        String name = rawName == null ? "" : rawName.trim();
        if (name.isEmpty()
                || ".".equals(name)
                || "..".equals(name)
                || name.contains("/")
                || name.contains("\\")
                || name.contains("\u0000")) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, errorMessage);
        }
        return name;
    }

    private String resolveSiblingPath(FileNode node, String newName) {
        int lastSlashIndex = node.getNormalizedPath().lastIndexOf('/');
        if (lastSlashIndex <= 0) {
            return "/" + newName;
        }
        return node.getNormalizedPath().substring(0, lastSlashIndex + 1) + newName;
    }

    private String resolveChildPath(FileNode parent, String childName) {
        if (parent == null) {
            return "/" + childName;
        }
        return parent.getNormalizedPath() + "/" + childName;
    }

    private boolean isSelfOrDescendant(FileNode node, FileNode targetParent) {
        return targetParent.getId().equals(node.getId())
                || targetParent.getNormalizedPath().startsWith(node.getNormalizedPath() + "/");
    }

    private void updateActiveDescendantPaths(UUID ownerUserId, String oldPath, String newPath) {
        List<FileNode> descendants = fileNodeRepository.findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedFalse(
                ownerUserId,
                oldPath + "/"
        );
        for (FileNode descendant : descendants) {
            descendant.setNormalizedPath(newPath + descendant.getNormalizedPath().substring(oldPath.length()));
        }
        fileNodeRepository.saveAll(descendants);
    }

    private void markDeleted(FileNode node, UUID deletedBy, Instant deletedAt) {
        node.setDeleted(true);
        node.setDeletedBy(deletedBy);
        node.setDeletedAt(deletedAt);
    }

    private void markRestored(FileNode node) {
        node.setDeleted(false);
        node.setDeletedAt(null);
        node.setDeletedBy(null);
    }

    private String normalizeCategory(String category) {
        if (category == null || category.isBlank() || "all".equalsIgnoreCase(category)) {
            return null;
        }
        String normalizedCategory = category.trim().toLowerCase(Locale.ROOT);
        Set<String> allowedCategories = Set.of(
                "image",
                "video",
                "audio",
                "document",
                "novel",
                "comic",
                "archive",
                "other"
        );
        if (!allowedCategories.contains(normalizedCategory)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "文件分类不支持");
        }
        return normalizedCategory;
    }

    private Pageable filePageable(int page, int size) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 1), 200);
        Sort sort = Sort.by(
                Sort.Order.desc("nodeType"),
                Sort.Order.asc("name").ignoreCase());
        return PageRequest.of(safePage, safeSize, sort);
    }

    private List<FileNode> listNodesForView(UUID ownerUserId, UUID parentId, String category) {
        if (category == null) {
            List<FileNode> nodes = parentId == null
                    ? fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndDeletedFalse(
                            ownerUserId, SpaceType.PERSONAL)
                    : fileNodeRepository.findByOwnerUserIdAndParentIdAndDeletedFalse(ownerUserId, parentId);
            return visibleNodes(nodes);
        }
        if (parentId == null) {
            return visibleNodes(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndDeletedFalse(
                    ownerUserId, SpaceType.PERSONAL));
        }
        FileNode parent = resolveParent(ownerUserId, parentId);
        return visibleNodes(fileNodeRepository.findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedFalse(
                ownerUserId,
                parent.getNormalizedPath() + "/"
        ));
    }

    private List<FileNode> visibleNodes(List<FileNode> nodes) {
        return nodes.stream()
                .filter(node -> !"DERIVED".equals(node.getSourceType()))
                .filter(node -> !SourceType.LOCAL_FILESYSTEM.getValue().equals(node.getSourceType()))
                .toList();
    }

    private void requireManagedNode(FileNode node) {
        if (SourceType.LOCAL_FILESYSTEM.getValue().equals(node.getSourceType())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "本地只读影视库文件不能通过文件管理器修改");
        }
    }

    private boolean matchesCategory(FileNode node, String category) {
        if (category == null) {
            return true;
        }
        return category.equals(FileTypeCategories.resolve(
                node.getName(), node.getMimeType(), node.getNodeType()));
    }

    private FileNodeDto toDto(FileNode node) {
        return new FileNodeDto(
                node.getId(),
                node.getParentId(),
                node.getNodeType(),
                node.getName(),
                node.getNormalizedPath(),
                node.getMimeType(),
                node.getSizeBytes(),
                node.isShared(),
                node.getSharedAt(),
                node.getUpdatedAt(),
                node.getSpaceType() != null ? node.getSpaceType().getValue() : "PERSONAL",
                node.getUploadedBy()
        );
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

    private void recordLibraryInvalidation(UUID ownerUserId, SyncAction action, int count) {
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId,
                SyncScope.FILES,
                "FILE_LIBRARY",
                null,
                action,
                null,
                Map.of("count", count)
        ));
    }
}
