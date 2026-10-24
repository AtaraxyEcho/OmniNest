package com.omninest.modules.file.service;

import com.omninest.common.error.BusinessException;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.BatchItemResult;
import com.omninest.modules.file.dto.CreateFolderRequest;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileMediaInfoDto;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.dto.FileProcessInput;
import com.omninest.modules.file.dto.MoveFileNodeRequest;
import com.omninest.modules.file.dto.RenameFileNodeRequest;
import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 文件节点查询与个人空间写操作服务。
 *
 * <p>只读列表、下载/内容读取与 DTO 装配已拆到协作服务，本类保留写操作与对外委托。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileQueryService {
    private static final int LIFECYCLE_BATCH_SIZE = 500;
    private final FileNodeRepository fileNodeRepository;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final ApplicationEventPublisher eventPublisher;
    private final FileIndexSyncService fileIndexSyncService;
    private final UserSyncEventRecorder syncEventRecorder;
    private final SharedSpaceService sharedSpaceService;
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
    private final TransactionTemplate transactionTemplate;
    private final FilePathRewriter filePathRewriter;
    private final FileNodeLookupSupport lookup;
    private final FileNodeDtoAssembler assembler;
    private final FileListQueryService listQueryService;
    private final FileDownloadContentService downloadContentService;

    @Transactional(readOnly = true)
    public List<FileNodeDto> listFiles(UUID ownerUserId, UUID parentId) {
        return listQueryService.listFiles(ownerUserId, parentId);
    }

    @Transactional(readOnly = true)
    public List<FileNodeDto> listFiles(UUID ownerUserId, UUID parentId, String category) {
        return listQueryService.listFiles(ownerUserId, parentId, category);
    }

    @Transactional(readOnly = true)
    public Page<FileNodeDto> listFilesPage(
            UUID ownerUserId, UUID parentId, String category, int page, int size) {
        return listQueryService.listFilesPage(ownerUserId, parentId, category, page, size);
    }

    @Transactional(readOnly = true)
    public Page<FileNodeDto> listRecycleBinPage(
            UUID ownerUserId, SpaceType spaceType, int page, int size) {
        return listQueryService.listRecycleBinPage(ownerUserId, spaceType, page, size);
    }

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrl(UUID ownerUserId, UUID fileId) {
        return downloadContentService.createDownloadUrl(ownerUserId, fileId);
    }

    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrls(UUID ownerUserId, Collection<UUID> fileIds) {
        return downloadContentService.createDownloadUrls(ownerUserId, fileIds);
    }

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createReadableDownloadUrl(UUID userId, UUID fileId) {
        return downloadContentService.createReadableDownloadUrl(userId, fileId);
    }

    @Transactional(readOnly = true)
    public FileProcessInput createOwnedProcessInput(UUID ownerUserId, UUID fileId) {
        return downloadContentService.createOwnedProcessInput(ownerUserId, fileId);
    }

    public FileProcessInput createOwnedContainerProcessInput(UUID ownerUserId, UUID fileId) {
        return downloadContentService.createOwnedContainerProcessInput(ownerUserId, fileId);
    }

    @Transactional(readOnly = true)
    public FileContentStream openOwnedFileContent(UUID ownerUserId, UUID fileId) {
        return downloadContentService.openOwnedFileContent(ownerUserId, fileId);
    }

    @Transactional(readOnly = true)
    public FileContentStream openReadableFileContent(UUID userId, UUID fileId) {
        return downloadContentService.openReadableFileContent(userId, fileId);
    }

    @Transactional(readOnly = true)
    public void validateOwnedImage(UUID ownerUserId, UUID fileId) {
        downloadContentService.validateOwnedImage(ownerUserId, fileId);
    }

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrlForShared(UUID userId, UUID fileId) {
        return downloadContentService.createDownloadUrlForShared(userId, fileId);
    }

    public FileMediaInfoDto mediaInfo(UUID ownerUserId, UUID fileId) {
        return downloadContentService.mediaInfo(ownerUserId, fileId);
    }



    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto createFolder(UUID ownerUserId, CreateFolderRequest request) {
        String folderName = normalizeNodeName(request.name(), "文件夹名称不合法");
        FileNode parent = lookup.resolveParent(ownerUserId, request.parentId());
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
        return assembler.toDto(saved);
    }

    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto renameNode(UUID ownerUserId, UUID fileId, RenameFileNodeRequest request) {
        String newName = normalizeNodeName(request.name(), "文件名称不合法");
        FileNode node = lookup.findActiveNode(ownerUserId, fileId);
        requireManagedNode(node);
        requirePersonalNode(node);
        if (node.getName().equals(newName)) {
            return assembler.toDto(node);
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
        return assembler.toDto(saved);
    }

    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto moveNode(UUID ownerUserId, UUID fileId, MoveFileNodeRequest request) {
        FileNode node = lookup.findActiveNode(ownerUserId, fileId);
        requireManagedNode(node);
        requirePersonalNode(node);
        UUID targetParentId = request.parentId();
        if (Objects.equals(node.getParentId(), targetParentId)) {
            return assembler.toDto(node);
        }

        FileNode targetParent = lookup.resolveParent(ownerUserId, targetParentId);
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
        return assembler.toDto(saved);
    }

    @Transactional(rollbackFor = Exception.class)
    public void deleteNode(UUID ownerUserId, UUID fileId) {
        FileNode node = lookup.findActiveNode(ownerUserId, fileId);
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
                            lookup.subtreePrefix(node),
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
            return assembler.toDto(node);
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

        return assembler.toDto(saved);
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
                            ownerUserId, node.getSpaceType(), lookup.subtreePrefix(node));
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
        FileNode targetParent = lookup.resolveParent(ownerUserId, targetParentId);
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
                requirePersonalNode(node);
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
    /**
     * 取子树内待恢复的软删除节点。
     *
     * <p>共享空间按空间取（不限所有者），个人空间按所有者取：前者若仍按单个所有者过滤，
     * 别人上传的子文件不会随父目录恢复，而共享配额按整棵子树补记，账实不符。</p>
     */
    private List<FileNode> deletedSubtreeNodes(FileNode node) {
        if (node.getSpaceType() == SpaceType.SHARED) {
            return fileNodeRepository.findDeletedBySpaceTypeAndNormalizedPathStartingWith(
                    SpaceType.SHARED, lookup.subtreePrefix(node));
        }
        return fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                node.getOwnerUserId(), node.getSpaceType(), lookup.subtreePrefix(node));
    }

    private void requireManagedNode(FileNode node) {
        if (SourceType.LOCAL_FILESYSTEM.getValue().equals(node.getSourceType())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "本地只读影视库文件不能通过文件管理器修改");
        }
    }

    private void requirePersonalNode(FileNode node) {
        if (node.getSpaceType() == SpaceType.SHARED) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "共享空间文件请使用共享空间接口操作");
        }
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
