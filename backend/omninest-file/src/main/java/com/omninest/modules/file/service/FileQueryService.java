package com.omninest.modules.file.service;

import com.omninest.common.error.BusinessException;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.FilePermission;
import com.omninest.modules.file.domain.FileTypeCategories;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.CreateFolderRequest;
import com.omninest.modules.file.dto.BatchItemResult;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileMediaInfoDto;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.port.MediaCoverDirectory;
import com.omninest.modules.user.port.UserNameDirectory;
import com.omninest.modules.file.dto.FileProcessInput;
import com.omninest.modules.file.dto.MoveFileNodeRequest;
import com.omninest.modules.file.dto.RenameFileNodeRequest;
import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.HashMap;
import java.util.LinkedHashMap;

import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
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
import org.springframework.transaction.support.TransactionTemplate;

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
    private final FileIndexSyncService fileIndexSyncService;
    private final UserSyncEventRecorder syncEventRecorder;
    private final UserNameDirectory userNameDirectory;
    private final MediaProbeService mediaProbeService;
    private final MediaProbeSourceStager mediaProbeSourceStager;
    private final MediaCoverDirectory mediaCoverDirectory;
    private final SharedSpaceService sharedSpaceService;
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
    private final TransactionTemplate transactionTemplate;
    private final FileDownloadService fileDownloadService;
    private final FilePathRewriter filePathRewriter;

    @Transactional(readOnly = true)
    public List<FileNodeDto> listFiles(UUID ownerUserId, UUID parentId) {
        return listFiles(ownerUserId, parentId, null);
    }

    @Transactional(readOnly = true)
    public List<FileNodeDto> listFiles(UUID ownerUserId, UUID parentId, String category) {
        String normalizedCategory = normalizeCategory(category);
        List<FileNode> nodes = listNodesForView(ownerUserId, parentId, normalizedCategory);
        List<FileNode> sorted = nodes.stream()
                .filter(node -> matchesCategory(node, normalizedCategory))
                .sorted(Comparator.comparing(FileNode::getNodeType).reversed()
                        .thenComparing(FileNode::getName, String.CASE_INSENSITIVE_ORDER))
                .toList();
        Map<UUID, String> uploaderNames = resolveUploaderNames(sorted);
        Map<UUID, UUID> coverMap = resolveAliveCovers(sorted);
        return sorted.stream()
                .map(node -> toDto(node, uploaderNames, coverMap.get(node.getId())))
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
        Map<UUID, String> uploaderNames = resolveUploaderNames(nodes.getContent());
        Map<UUID, UUID> covers = resolveAliveCovers(nodes.getContent());
        return nodes.map(node -> toDto(node, uploaderNames, covers.get(node.getId())));
    }

    /**
     * 节点子树前缀的 LIKE 字面量。
     *
     * <p>这两个调用点（软删与还原后代）都是"读出来再写回去"：目录名里的 {@code _} 或 {@code %}
     * 若按通配符解释，兄弟目录的节点会被一起软删或还原。</p>
     */
    private String subtreePrefix(FileNode node) {
        return subtreePrefix(node.getNormalizedPath());
    }

    /**
     * 取子树内待恢复的软删除节点。
     *
     * <p>共享空间按空间取（不限所有者），个人空间按所有者取：前者若仍按单个所有者过滤，
     * 别人上传的子文件不会随父目录恢复，而共享配额按整棵子树补记，账实不符。</p>
     */
    private List<FileNode> deletedSubtreeNodes(FileNode node) {
        if (node.getSpaceType() == SpaceType.SHARED) {
            return fileNodeRepository.findDeletedBySpaceTypeAndNormalizedPathStartingWith(
                    SpaceType.SHARED, subtreePrefix(node));
        }
        return fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                node.getOwnerUserId(), node.getSpaceType(), subtreePrefix(node));
    }

    /**
     * 路径前缀的 LIKE 字面量。
     *
     * <p>这几个调用点都是"按子树读出来再写回去"：批量软删、批量还原、改名时的子树路径重写，
     * 以及共享标记。目录名里的下划线或百分号若按通配符解释，兄弟目录的节点会被一起改写。</p>
     */
    private String subtreePrefix(String path) {
        return LikePatterns.escapeSpecials(path + "/");
    }

    private String resolveSubtreePrefix(UUID ownerUserId, UUID parentId) {
        FileNode parent = resolveParent(ownerUserId, parentId);
        // 前缀来自目录名，进 LIKE 前必须按字面量转义（配套查询声明 escape '\'）。
        return LikePatterns.escapeSpecials(parent.getNormalizedPath() + "/");
    }

    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto createFolder(UUID ownerUserId, CreateFolderRequest request) {
        String folderName = normalizeNodeName(request.name(), "文件夹名称不合法");
        FileNode parent = resolveParent(ownerUserId, request.parentId());
        if (sameNameExists(ownerUserId, SpaceType.PERSONAL, request.parentId(), folderName)) {
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
        if (sameNameExists(ownerUserId, node.getSpaceType(), node.getParentId(), newName)) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }

        String oldPath = node.getNormalizedPath();
        String newPath = resolveSiblingPath(node, newName);
        node.setName(newName);
        node.setNormalizedPath(newPath);
        filePathRewriter.rewriteDescendantPaths(ownerUserId, node.getSpaceType(), oldPath, newPath);
        FileNode saved = fileNodeRepository.save(node);
        // 更新 Lucene 搜索索引中的文件名，空间类型必须跟随节点本身，
        // 否则共享文件重命名后会在索引里被写成个人空间。索引写入由 Worker 单进程执行。
        fileIndexSyncService.scheduleAfterCommit(ownerUserId, List.of(saved.getId()));
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
        if (sameNameExists(ownerUserId, node.getSpaceType(), targetParentId, node.getName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "目标目录下已存在同名文件");
        }

        String oldPath = node.getNormalizedPath();
        String newPath = resolveChildPath(targetParent, node.getName());
        node.setParentId(targetParentId);
        node.setNormalizedPath(newPath);
        filePathRewriter.rewriteDescendantPaths(ownerUserId, node.getSpaceType(), oldPath, newPath);
        FileNode saved = fileNodeRepository.save(node);
        recordFileEvent(ownerUserId, saved.getId(), SyncAction.UPDATED);
        return toDto(saved);
    }

    @Transactional(rollbackFor = Exception.class)
    public void deleteNode(UUID ownerUserId, UUID fileId) {
        FileNode node = findActiveNode(ownerUserId, fileId);
        if (node.getSpaceType() == SpaceType.SHARED) {
            // 共享空间删除必须走 CAN_DELETE_OWN/CAN_DELETE_ANY 校验并扣减共享空间账本，
            // 个人删除路径既不知道权限矩阵也不维护 shared_space_usage。
            sharedSpaceService.deleteSharedFile(fileId, ownerUserId);
            return;
        }
        requireManagedNode(node);
        Instant deletedAt = Instant.now();
        markDeleted(node, ownerUserId, deletedAt);
        fileNodeRepository.save(node);
        fileIndexSyncService.scheduleAfterCommit(ownerUserId, List.of(node.getId()));
        eventPublisher.publishEvent(new FileNodesSoftDeletedEvent(ownerUserId, List.of(node.getId()), deletedAt));

        while (true) {
            List<UUID> descendantIds = fileNodeRepository.findActiveIdsByPathPrefix(
                            ownerUserId,
                            node.getSpaceType(),
                            subtreePrefix(node),
                            PageRequest.of(0, LIFECYCLE_BATCH_SIZE)
                    )
                    .getContent();
            if (descendantIds.isEmpty()) {
                break;
            }
            fileNodeRepository.softDeleteIds(ownerUserId, descendantIds, deletedAt);
            fileIndexSyncService.scheduleAfterCommit(ownerUserId, descendantIds);
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
        Map<UUID, String> uploaderNames = resolveUploaderNames(nodes.getContent());
        Map<UUID, UUID> covers = resolveAliveCovers(nodes.getContent());
        return nodes.map(node -> toDto(node, uploaderNames, covers.get(node.getId())));
    }

    /**
     * 恢复回收站节点。
     *
     * <p>个人空间仍只允许所有者；共享空间允许上传者或实际删除者恢复。子树、父目录、
     * 同名检查与事件统一使用节点所有者（共享空间为上传者），恢复成功后按删除时的口径
     * 补记共享空间用量。</p>
     *
     * @param operatorId 操作用户 ID
     * @param fileId 文件节点 ID
     * @return 恢复后的文件节点
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto restoreNode(UUID operatorId, UUID fileId) {
        FileNode node = requireTrashOperatorNode(operatorId, fileId);
        requireManagedNode(node);
        if (!node.isDeleted()) {
            return toDto(node);
        }
        // 子树、父目录、同名检查与事件都按节点所有者（共享空间为上传者）执行；
        // 共享空间删除者可能不是上传者，不能把操作者当成所有者使用。
        UUID nodeOwnerUserId = node.getOwnerUserId();
        fileLifecycleGuard.requireRestorable(nodeOwnerUserId, fileId);
        List<FileNode> restoredAncestors = collectDeletedAncestors(node);
        ensureParentAvailable(restoredAncestors.isEmpty() ? node : restoredAncestors.getFirst());
        if (sameNameExists(nodeOwnerUserId, node.getSpaceType(), node.getParentId(), node.getName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }
        SharedSpaceService.SubtreeStats sharedStats = null;
        if (node.getSpaceType() == SpaceType.SHARED) {
            sharedStats = sharedSpaceService.calculateRestoreSubtreeStats(node);
            sharedSpaceQuotaService.checkQuota(sharedStats.totalBytes());
        }

        restoredAncestors.forEach(this::markRestored);
        markRestored(node);
        List<FileNode> descendants = deletedSubtreeNodes(node);
        filePathRewriter.recomputeRestoredPaths(node, restoredAncestors, descendants);
        descendants.forEach(this::markRestored);
        if (!restoredAncestors.isEmpty()) {
            fileNodeRepository.saveAll(restoredAncestors);
        }
        fileNodeRepository.saveAll(descendants);
        FileNode saved = fileNodeRepository.save(node);
        if (sharedStats != null) {
            sharedSpaceQuotaService.increaseUsage(sharedStats.totalBytes(), sharedStats.fileCount());
        }

        // 发布恢复事件，触发 Lucene 重新索引：按节点真实所有者分组投递，
        // 共享子树里别人上传的子文件不能挂到操作者名下重建索引。
        Map<UUID, List<UUID>> restoredIdsByOwner = new LinkedHashMap<>();
        restoredAncestors.forEach(ancestor -> restoredIdsByOwner
                .computeIfAbsent(ancestor.getOwnerUserId(), key -> new ArrayList<>())
                .add(ancestor.getId()));
        restoredIdsByOwner
                .computeIfAbsent(saved.getOwnerUserId(), key -> new ArrayList<>())
                .add(saved.getId());
        descendants.forEach(descendant -> restoredIdsByOwner
                .computeIfAbsent(descendant.getOwnerUserId(), key -> new ArrayList<>())
                .add(descendant.getId()));
        Instant restoredAt = Instant.now();
        restoredIdsByOwner.forEach((ownerId, ids) -> {
            eventPublisher.publishEvent(new FileNodesRestoredEvent(ownerId, List.copyOf(ids), restoredAt));
            fileIndexSyncService.scheduleAfterCommit(ownerId, ids);
        });
        recordFileEvent(nodeOwnerUserId, saved.getId(), SyncAction.RESTORED);

        return toDto(saved);
    }

    /**
     * 批量软删除文件节点及其后代。
     *
     * <p>共享空间节点逐项委托 {@link SharedSpaceService#deleteSharedFile}：它负责权限矩阵与
     * 共享空间账本。该方法本身不包事务，否则某一项权限失败会把整批个人删除标记为
     * rollback-only；个人节点在独立事务里成批处理。</p>
     *
     * @param ownerUserId 操作用户 ID
     * @param fileIds 文件节点 ID 列表
     * @return 与输入顺序一致的逐项结果
     */
    public List<BatchItemResult> batchDeleteNodes(UUID ownerUserId, List<UUID> fileIds) {
        Map<UUID, FileNode> ownedNodes = fileNodeRepository
                .findByOwnerUserIdAndIdInAndDeletedFalse(ownerUserId, fileIds).stream()
                .collect(Collectors.toMap(FileNode::getId, node -> node, (left, right) -> left));
        // 共享空间文件可能由其他成员上传：按 ID 全量读取后交给共享权限矩阵判定。
        Map<UUID, FileNode> sharedCandidates = fileNodeRepository.findAllById(fileIds).stream()
                .filter(node -> !node.isDeleted() && node.getSpaceType() == SpaceType.SHARED)
                .collect(Collectors.toMap(FileNode::getId, node -> node, (left, right) -> left));
        Map<UUID, BatchItemResult> resultsById = new LinkedHashMap<>();
        List<UUID> personalIds = new ArrayList<>();
        List<UUID> sharedIds = new ArrayList<>();
        for (UUID fileId : fileIds) {
            FileNode owned = ownedNodes.get(fileId);
            if (owned != null && owned.getSpaceType() == SpaceType.SHARED) {
                sharedIds.add(fileId);
                continue;
            }
            if (owned != null) {
                personalIds.add(fileId);
                continue;
            }
            FileNode shared = sharedCandidates.get(fileId);
            if (shared != null) {
                sharedIds.add(fileId);
                continue;
            }
            resultsById.put(fileId, BatchItemResult.skipped(fileId, "文件不存在或已删除"));
        }
        if (!personalIds.isEmpty()) {
            List<BatchItemResult> personalResults = transactionTemplate.execute(
                    status -> deletePersonalBatch(ownerUserId, ownedNodes, personalIds));
            if (personalResults != null) {
                personalResults.forEach(result -> resultsById.put(result.id(), result));
            }
        }
        for (UUID fileId : sharedIds) {
            try {
                sharedSpaceService.deleteSharedFile(fileId, ownerUserId);
                resultsById.put(fileId, BatchItemResult.success(fileId));
            } catch (BusinessException exception) {
                resultsById.put(fileId, BatchItemResult.failed(
                        fileId, exception.errorCode().name(), exception.getMessage()));
            }
        }
        return fileIds.stream()
                .map(resultsById::get)
                .filter(Objects::nonNull)
                .toList();
    }

    private List<BatchItemResult> deletePersonalBatch(
            UUID ownerUserId, Map<UUID, FileNode> nodesById, List<UUID> fileIds) {
        List<BatchItemResult> results = new ArrayList<>();
        Instant deletedAt = Instant.now();
        List<UUID> allDeletedIds = new ArrayList<>();
        List<FileNode> allToSave = new ArrayList<>();
        for (UUID fileId : fileIds) {
            FileNode node = nodesById.get(fileId);
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
                    .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                            ownerUserId, node.getSpaceType(), subtreePrefix(node));
            descendants.forEach(d -> markDeleted(d, ownerUserId, deletedAt));
            allToSave.addAll(descendants);
            descendants.stream().map(FileNode::getId).forEach(allDeletedIds::add);
            results.add(BatchItemResult.success(fileId));
        }
        if (!allToSave.isEmpty()) {
            fileNodeRepository.saveAll(allToSave);
            fileIndexSyncService.scheduleAfterCommit(ownerUserId, allDeletedIds);
            eventPublisher.publishEvent(new FileNodesSoftDeletedEvent(ownerUserId, allDeletedIds, deletedAt));
            recordLibraryInvalidation(ownerUserId, SyncAction.DELETED, allDeletedIds.size());
        }
        return results;
    }

    /**
     * 解析当前用户可操作的回收站节点并复核共享空间权限。
     *
     * <p>个人空间只接受节点所有者；共享空间节点的 {@code owner_user_id} 是上传者，而回收站
     * 按 {@code deleted_by} 展示，因此上传者和实际删除者都必须能定位到同一节点。共享空间
     * 权限与删除共用同一判定（上传者 CAN_DELETE_OWN，其他成员 CAN_DELETE_ANY），
     * 非删除者、非上传者一律按文件不存在处理。</p>
     *
     * @param operatorId 操作用户 ID
     * @param fileId 文件节点 ID
     * @return 目标节点
     */
    public FileNode requireTrashOperatorNode(UUID operatorId, UUID fileId) {
        FileNode node = fileNodeRepository.findByIdAndOwnerUserId(fileId, operatorId)
                .or(() -> fileNodeRepository.findById(fileId)
                        .filter(candidate -> candidate.getSpaceType() == SpaceType.SHARED
                                && candidate.isDeleted()
                                && Objects.equals(candidate.getDeletedBy(), operatorId)))
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        requireSharedLifecycleOperator(operatorId, node);
        return node;
    }

    /**
     * 按共享空间删除规则复核生命周期权限；个人空间节点不设共享权限。
     *
     * @param operatorId 操作用户 ID
     * @param node 文件节点
     */
    public void requireSharedLifecycleOperator(UUID operatorId, FileNode node) {
        if (node.getSpaceType() == SpaceType.SHARED) {
            sharedSpaceService.validateSharedLifecycleOperator(operatorId, node);
        }
    }

    /**
     * 批量恢复已删除的文件节点及其后代。
     *
     * <p>逐项沿用单节点恢复的解析、权限与共享空间补记账规则；事件按节点所有者分组发布，
     * 避免把共享空间文件的重建索引通知发给删除者而不是上传者。</p>
     *
     * @param operatorId 操作用户 ID
     * @param fileIds 文件节点 ID 列表
     * @return 逐项恢复结果
     */
    @Transactional(rollbackFor = Exception.class)
    public List<BatchItemResult> batchRestoreNodes(UUID operatorId, List<UUID> fileIds) {
        List<BatchItemResult> results = new ArrayList<>();
        Instant restoredAt = Instant.now();
        Map<UUID, List<UUID>> restoredIdsByOwner = new LinkedHashMap<>();
        List<FileNode> allToSave = new ArrayList<>();
        List<SharedSpaceService.SubtreeStats> sharedCharges = new ArrayList<>();
        for (UUID fileId : fileIds) {
            FileNode node;
            try {
                node = requireTrashOperatorNode(operatorId, fileId);
            } catch (BusinessException exception) {
                results.add(BatchItemResult.failed(fileId, exception.errorCode().name(), exception.getMessage()));
                continue;
            }
            if (!node.isDeleted()) {
                results.add(BatchItemResult.skipped(fileId, "文件未删除"));
                continue;
            }
            UUID nodeOwnerUserId = node.getOwnerUserId();
            SharedSpaceService.SubtreeStats sharedStats = null;
            List<FileNode> restoredAncestors;
            try {
                requireManagedNode(node);
                fileLifecycleGuard.requireRestorable(nodeOwnerUserId, node.getId());
                restoredAncestors = collectDeletedAncestors(node);
                ensureParentAvailable(restoredAncestors.isEmpty() ? node : restoredAncestors.getFirst());
                if (sameNameExists(nodeOwnerUserId, node.getSpaceType(), node.getParentId(), node.getName())) {
                    throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件: " + node.getName());
                }
                if (node.getSpaceType() == SpaceType.SHARED) {
                    sharedStats = sharedSpaceService.calculateRestoreSubtreeStats(node);
                    sharedSpaceQuotaService.checkQuota(sharedStats.totalBytes());
                }
            } catch (BusinessException exception) {
                results.add(BatchItemResult.failed(fileId, exception.errorCode().name(), exception.getMessage()));
                continue;
            }
            restoredAncestors.forEach(this::markRestored);
            allToSave.addAll(restoredAncestors);
            restoredAncestors.forEach(ancestor -> restoredIdsByOwner
                    .computeIfAbsent(ancestor.getOwnerUserId(), key -> new ArrayList<>())
                    .add(ancestor.getId()));
            markRestored(node);
            allToSave.add(node);
            restoredIdsByOwner.computeIfAbsent(nodeOwnerUserId, key -> new ArrayList<>()).add(node.getId());
            List<FileNode> descendants = deletedSubtreeNodes(node);
            filePathRewriter.recomputeRestoredPaths(node, restoredAncestors, descendants);
            descendants.forEach(this::markRestored);
            allToSave.addAll(descendants);
            // 共享子树的子孙可能属于其他上传者，索引事件按真实所有者分组投递。
            descendants.forEach(descendant -> restoredIdsByOwner
                    .computeIfAbsent(descendant.getOwnerUserId(), key -> new ArrayList<>())
                    .add(descendant.getId()));
            if (sharedStats != null) {
                sharedCharges.add(sharedStats);
            }
            results.add(BatchItemResult.success(fileId));
        }
        if (!allToSave.isEmpty()) {
            fileNodeRepository.saveAll(allToSave);
            // 共享账本在恢复写入成功后再补记，异常时整个批次回滚，避免只恢复节点不记账。
            sharedCharges.forEach(stats ->
                    sharedSpaceQuotaService.increaseUsage(stats.totalBytes(), stats.fileCount()));
            restoredIdsByOwner.forEach((ownerId, ids) -> {
                eventPublisher.publishEvent(new FileNodesRestoredEvent(ownerId, List.copyOf(ids), restoredAt));
                fileIndexSyncService.scheduleAfterCommit(ownerId, ids);
                recordLibraryInvalidation(ownerId, SyncAction.RESTORED, ids.size());
            });
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
                    if (sameNameExists(ownerUserId, node.getSpaceType(), targetParentId, node.getName())) {
                        throw new BusinessException(ErrorCode.CONFLICT, "目标目录下已存在同名文件: " + node.getName());
                    }
                    String oldPath = node.getNormalizedPath();
                    String newPath = resolveChildPath(targetParent, node.getName());
                    node.setParentId(targetParentId);
                    node.setNormalizedPath(newPath);
                    filePathRewriter.rewriteDescendantPaths(ownerUserId, node.getSpaceType(), oldPath, newPath);
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
        return fileDownloadService.createDownloadUrl(ownerUserId, fileId);
    }

    /**
     * 批量为当前用户可下载的文件创建短期下载地址。
     *
     * @param ownerUserId 所有者用户 ID
     * @param fileIds 文件节点 ID 集合
     * @return 文件节点 ID 到下载地址的映射
     */
    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrls(UUID ownerUserId, Collection<UUID> fileIds) {
        return fileDownloadService.createDownloadUrls(ownerUserId, fileIds);
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
     * 创建当前用户拥有的、容器网络视角可读取的进程输入。
     * 供转码/探测等容器化进程使用；归属校验与 {@link #createOwnedProcessInput} 一致。
     *
     * @param ownerUserId 当前用户 ID
     * @param fileId 文件节点 ID
     * @return 进程输入
     */
    public FileProcessInput createOwnedContainerProcessInput(UUID ownerUserId, UUID fileId) {
        FileNode node = findActiveNode(ownerUserId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件节点没有可读取内容");
        }
        return fileContentAccessService.createContainerProcessInput(node);
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
        if (node.getSpaceType() == SpaceType.SHARED) {
            // 共享空间成员凭角色权限读取，不依赖 personal share 的 shared 标记。
            sharedSpaceService.validateBrowsePermission(userId);
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
        return fileDownloadService.createDownloadUrlForShared(userId, fileId);
    }

    /**
     * 探测文件媒体元数据（时长/分辨率）：仅 FILE 且 video/* 或 image/*，
     * 结果按内容对象缓存；探测失败返回空对象而非报错。
     *
     * <p>探测输入先取成本地稀疏文件再交给 ffprobe，不吃预签名地址——输入形态决定的安全性质
     * 见 {@link MediaProbeSourceStager}。暂存失败不写缓存，避免一次读取抖动把空结果钉两小时。
     *
     * <p>容器索引可能落在默认尾窗之外（非 faststart 的 MP4 把 {@code moov} 放文件末尾），
     * 这种对象的探测只会得到空结果，此时用放大尾窗再试一次；两次窗口用不同缓存键，
     * 否则第二次会直接读回第一次缓存的空结果。
     *
     * <p>本方法不加事务：暂存最坏是 2 MiB + 32 MiB 的网络读与磁盘写，事务包着它会长时间占住
     * 连接池名额，而节点查询与对象元数据查询各自只需要一条标量读。
     */
    public FileMediaInfoDto mediaInfo(UUID ownerUserId, UUID fileId) {
        FileNode node = findActiveNode(ownerUserId, fileId);
        if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "文件夹没有媒体元数据");
        }
        String mime = node.getMimeType() == null ? "" : node.getMimeType();
        if (!mime.startsWith("video/") && !mime.startsWith("image/")) {
            return new FileMediaInfoDto(null, null, null);
        }
        if (node.getCurrentObjectId() == null) {
            return new FileMediaInfoDto(null, null, null);
        }
        return probeMediaInfo(node);
    }

    private FileMediaInfoDto probeMediaInfo(FileNode node) {
        FileMediaInfoDto empty = new FileMediaInfoDto(null, null, null);
        Optional<MediaProbeSourceStager.StagedSource> staged = mediaProbeSourceStager.stage(node);
        if (staged.isEmpty()) {
            return empty;
        }
        FileMediaInfoDto first;
        boolean escalate;
        try (MediaProbeSourceStager.StagedSource source = staged.get()) {
            first = mediaProbeService.probe(
                    probeCacheKey(node, MediaProbeSourceStager.DEFAULT_TAIL_BYTES), source.path());
            escalate = first.isEmpty() && source.widerTailCouldHelp();
        }
        if (!escalate) {
            return first;
        }
        Optional<MediaProbeSourceStager.StagedSource> wide = mediaProbeSourceStager
                .stage(node, MediaProbeSourceStager.ESCALATED_TAIL_BYTES);
        if (wide.isEmpty()) {
            return first;
        }
        try (MediaProbeSourceStager.StagedSource source = wide.get()) {
            return mediaProbeService.probe(
                    probeCacheKey(node, MediaProbeSourceStager.ESCALATED_TAIL_BYTES), source.path());
        }
    }

    private static String probeCacheKey(FileNode node, long tailBytes) {
        return node.getCurrentObjectId() + ":tail=" + tailBytes;
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

    /**
     * 收集目标节点上方仍处于回收站的祖先链，供恢复时一并还原。
     *
     * <p>只做校验与收集，不修改实体：批量恢复里任一检查失败都不能把祖先提前标记为已恢复。</p>
     */
    private List<FileNode> collectDeletedAncestors(FileNode node) {
        List<FileNode> ancestors = new ArrayList<>();
        UUID parentId = node.getParentId();
        while (parentId != null) {
            FileNode parent = fileNodeRepository.findById(parentId).orElse(null);
            if (parent == null || !parent.isDeleted()) {
                break;
            }
            if (parent.getSpaceType() != node.getSpaceType()) {
                throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "上级文件夹与当前文件空间不一致");
            }
            if (parent.getSpaceType() == SpaceType.PERSONAL
                    && !Objects.equals(parent.getOwnerUserId(), node.getOwnerUserId())) {
                throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在");
            }
            if (parent.getPurgeState() != FilePurgeState.NONE) {
                throw new BusinessException(ErrorCode.CONFLICT, "上级文件夹正在永久删除");
            }
            ancestors.add(parent);
            parentId = parent.getParentId();
        }
        Collections.reverse(ancestors);
        for (FileNode ancestor : ancestors) {
            if (sameNameExists(ancestor.getOwnerUserId(), ancestor.getSpaceType(),
                    ancestor.getParentId(), ancestor.getName())) {
                throw new BusinessException(ErrorCode.CONFLICT, "上级文件夹同名冲突: " + ancestor.getName());
            }
        }
        return ancestors;
    }

    private void ensureParentAvailable(FileNode node) {
        if (node.getParentId() == null) {
            return;
        }
        // 共享空间的父目录可能由其他成员上传，不能按节点所有者查父级。
        FileNode parent = node.getSpaceType() == SpaceType.SHARED
                ? fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(node.getParentId(), SpaceType.SHARED)
                        .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在"))
                : fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(node.getParentId(), node.getOwnerUserId())
                        .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在"));
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "父级节点不是文件夹");
        }
    }

    /**
     * 判断节点自身空间内的同级同名冲突。
     *
     * <p>检查必须限定空间：共享空间节点保留 owner_user_id，若只按 owner 查询，共享空间
     * 同名根节点会误判为个人空间冲突（个人空间导入会在建目录时被 409 拦下）。</p>
     */
    private boolean sameNameExists(UUID ownerUserId, SpaceType spaceType, UUID parentId, String name) {
        if (spaceType == SpaceType.SHARED) {
            if (parentId == null) {
                return fileNodeRepository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(spaceType, name);
            }
            return fileNodeRepository.existsBySpaceTypeAndParentIdAndNameAndDeletedFalse(spaceType, parentId, name);
        }
        if (parentId == null) {
            return fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                    ownerUserId, spaceType, name);
        }
        return fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                ownerUserId, spaceType, parentId, name);
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
        return visibleNodes(fileNodeRepository
                .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        ownerUserId,
                        SpaceType.PERSONAL,
                        subtreePrefix(parent)
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
        Map<UUID, UUID> covers = resolveAliveCovers(List.of(node));
        return toDto(node, resolveUploaderNames(List.of(node)), covers.get(node.getId()));
    }

    /**
     * 上传者显示名：共享空间取实际上传者，其余取所有者；
     * 未知用户不填充，由前端按缺省呈现。
     */
    private FileNodeDto toDto(
            FileNode node,
            Map<UUID, String> uploaderNames,
            UUID coverFileId
    ) {
        UUID uploaderId = node.getUploadedBy() != null ? node.getUploadedBy() : node.getOwnerUserId();
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
                node.getUploadedBy(),
                uploaderNames.get(uploaderId),
                coverFileId
        );
    }

    /**
     * 批量解析本组节点的存活媒体封面（媒体类 FILE 节点才发起反查）。
     */
    private Map<UUID, UUID> resolveAliveCovers(List<FileNode> nodes) {
        Map<UUID, Set<UUID>> mediaIdsByOwner = new HashMap<>();
        for (FileNode node : nodes) {
            if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
                continue;
            }
            String category = FileTypeCategories.resolve(
                    node.getName(), node.getMimeType(), node.getNodeType());
            boolean mediaCategory = FileTypeCategories.VIDEO.equals(category)
                    || FileTypeCategories.AUDIO.equals(category)
                    || FileTypeCategories.NOVEL.equals(category)
                    || FileTypeCategories.COMIC.equals(category);
            if (!mediaCategory) {
                continue;
            }
            mediaIdsByOwner
                    .computeIfAbsent(node.getOwnerUserId(), key -> new HashSet<>())
                    .add(node.getId());
        }
        if (mediaIdsByOwner.isEmpty()) {
            return Map.of();
        }
        Map<UUID, UUID> covers = new HashMap<>();
        mediaIdsByOwner.forEach((ownerUserId, mediaFileIds) ->
                covers.putAll(mediaCoverDirectory.resolveCoverFileIds(ownerUserId, mediaFileIds)));
        if (covers.isEmpty()) {
            return Map.of();
        }
        Set<UUID> aliveIds = new HashSet<>();
        for (FileNode coverNode : fileNodeRepository.findAllById(covers.values())) {
            if (!coverNode.isDeleted() && NodeType.FILE.getValue().equals(coverNode.getNodeType())) {
                aliveIds.add(coverNode.getId());
            }
        }
        Map<UUID, UUID> alive = new HashMap<>();
        for (Map.Entry<UUID, UUID> entry : covers.entrySet()) {
            if (aliveIds.contains(entry.getValue())) {
                alive.put(entry.getKey(), entry.getValue());
            }
        }
        return alive;
    }

    /**
     * 批量解析一批节点的上传者显示名，供列表接口一次查询填充。
     */
    private Map<UUID, String> resolveUploaderNames(List<FileNode> nodes) {
        Set<UUID> uploaderIds = new HashSet<>();
        for (FileNode node : nodes) {
            UUID uploaderId = node.getUploadedBy() != null ? node.getUploadedBy() : node.getOwnerUserId();
            if (uploaderId != null) {
                uploaderIds.add(uploaderId);
            }
        }
        return userNameDirectory.resolveDisplayNames(uploaderIds);
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
