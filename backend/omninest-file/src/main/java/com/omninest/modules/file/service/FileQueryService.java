package com.omninest.modules.file.service;

import com.omninest.common.error.BusinessException;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.security.RequestPrincipal;
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
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.Page;
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
    private final FileShareRecipientAccessService shareRecipientAccessService;
    private final FileListQueryService listQueryService;
    private final FileDownloadContentService downloadContentService;
    private final FileRestoreSupport restoreSupport;
    private final FileSubtreeSoftDeleter subtreeSoftDeleter;

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

    /**
     * 按 ID 查询当前用户可见的文件节点，供搜索结果等精确跳转使用。
     *
     * @param ownerUserId 当前用户 ID
     * @param fileId 文件节点 ID
     * @return 文件节点 DTO
     */
    @Transactional(readOnly = true)
    public FileNodeDto getFileNode(UUID ownerUserId, UUID fileId) {
        FileNode node = fileNodeRepository.findByIdAndDeletedFalse(fileId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (!node.getOwnerUserId().equals(ownerUserId)) {
            // 共享空间成员按浏览权限；个人空间文件只允许定向分享接收者预览。
            boolean accessible = node.getSpaceType() == SpaceType.SHARED
                    ? sharedSpaceService.canBrowse(ownerUserId)
                    : shareRecipientAccessService.canAccessRecipientNode(ownerUserId, node);
            if (!accessible) {
                // 不可用时统一 NOT_FOUND，避免 403/404 差异成为存在性探测通道。
                throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在");
            }
        }
        return assembler.toDto(node);
    }

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrl(RequestPrincipal requester, UUID fileId) {
        return downloadContentService.createDownloadUrl(requester, fileId);
    }

    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrls(
            RequestPrincipal requester, Collection<UUID> fileIds) {
        return downloadContentService.createDownloadUrls(requester, fileIds);
    }

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createDownloadUrlAs(UUID actorUserId, UUID fileId) {
        return downloadContentService.createDownloadUrlAs(actorUserId, fileId);
    }

    @Transactional(readOnly = true)
    public Map<UUID, FileDownloadUrlDto> createDownloadUrlsAs(
            UUID actorUserId, Collection<UUID> fileIds) {
        return downloadContentService.createDownloadUrlsAs(actorUserId, fileIds);
    }

    @Transactional(readOnly = true)
    public FileDownloadUrlDto createReadableDownloadUrl(RequestPrincipal requester, UUID fileId) {
        return downloadContentService.createReadableDownloadUrl(requester, fileId);
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
    public FileDownloadUrlDto createDownloadUrlForShared(RequestPrincipal requester, UUID fileId) {
        return downloadContentService.createDownloadUrlForShared(requester, fileId);
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
        List<UUID> affectedFileIds = new ArrayList<>(
                filePathRewriter.rewriteDescendantPaths(ownerUserId, node.getSpaceType(), oldPath, newPath));
        FileNode saved = fileNodeRepository.save(node);
        if (NodeType.FILE.getValue().equals(saved.getNodeType())) {
            affectedFileIds.add(saved.getId());
        }
        if (!affectedFileIds.isEmpty()) {
            // 更新 Lucene 搜索索引中的文件名与路径，空间类型必须跟随节点本身，
            // 否则共享文件重命名后会在索引里被写成个人空间。索引写入由 Worker 单进程执行。
            fileIndexSyncService.scheduleAfterCommit(ownerUserId, affectedFileIds);
        }
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
        List<UUID> affectedFileIds = new ArrayList<>(
                filePathRewriter.rewriteDescendantPaths(ownerUserId, node.getSpaceType(), oldPath, newPath));
        FileNode saved = fileNodeRepository.save(node);
        if (NodeType.FILE.getValue().equals(saved.getNodeType())) {
            affectedFileIds.add(saved.getId());
        }
        if (!affectedFileIds.isEmpty()) {
            // 移动后全局搜索仍按旧路径返回，必须重建文件索引。
            fileIndexSyncService.scheduleAfterCommit(ownerUserId, affectedFileIds);
        }
        recordFileEvent(ownerUserId, saved.getId(), SyncAction.UPDATED);
        return assembler.toDto(saved);
    }

    @Transactional(rollbackFor = Exception.class)
    public void deleteNode(UUID actorUserId, UUID fileId) {
        // 共享节点可能由其他成员上传：先按操作者名下的个人节点查找，
        // 找不到再回退到共享空间并交由 deleteSharedFile 复核 CAN_DELETE_OWN/ANY。
        FileNode node = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, actorUserId)
                .or(() -> fileNodeRepository.findByIdAndSpaceTypeAndDeletedFalse(fileId, SpaceType.SHARED))
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (node.getSpaceType() == SpaceType.SHARED) {
            // 共享空间删除必须走 CAN_DELETE_OWN/CAN_DELETE_ANY 校验并扣减共享空间账本，
            // 个人删除路径既不知道权限矩阵也不维护 shared_space_usage。
            sharedSpaceService.deleteSharedFile(fileId, actorUserId);
            return;
        }
        requireManagedNode(node);
        Instant deletedAt = Instant.now();
        markDeleted(node, actorUserId, deletedAt);
        fileNodeRepository.save(node);
        fileIndexSyncService.scheduleAfterCommit(actorUserId, List.of(node.getId()));
        eventPublisher.publishEvent(new FileNodesSoftDeletedEvent(actorUserId, List.of(node.getId()), deletedAt));
        subtreeSoftDeleter.softDeleteDescendants(actorUserId, node, deletedAt, null);
        recordFileEvent(actorUserId, node.getId(), SyncAction.DELETED);
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
        List<FileNode> restoredAncestors = restoreSupport.collectDeletedAncestors(node);
        restoreSupport.ensureParentAvailable(restoredAncestors.isEmpty() ? node : restoredAncestors.getFirst());
        if (sameNameExists(nodeOwnerUserId, node.getSpaceType(), node.getParentId(), node.getName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件");
        }
        SharedSpaceService.SubtreeStats sharedStats = null;
        if (node.getSpaceType() == SpaceType.SHARED) {
            sharedStats = sharedSpaceService.calculateRestoreSubtreeStats(node);
            sharedSpaceQuotaService.checkQuota(sharedStats.totalBytes());
        }

        restoredAncestors.forEach(restoreSupport::markRestored);
        restoreSupport.markRestored(node);
        List<FileNode> descendants = restoreSupport.deletedSubtreeNodes(node);
        filePathRewriter.recomputeRestoredPaths(node, restoredAncestors, descendants);
        descendants.forEach(restoreSupport::markRestored);
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
        List<UUID> rootIds = new ArrayList<>();
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
            rootIds.add(node.getId());
            subtreeSoftDeleter.softDeleteDescendants(ownerUserId, node, deletedAt, allDeletedIds);
            results.add(BatchItemResult.success(fileId));
        }
        if (!allToSave.isEmpty()) {
            fileNodeRepository.saveAll(allToSave);
            // 后代已由 softDeleteDescendants 逐批投递过，这里只补根节点。
            fileIndexSyncService.scheduleAfterCommit(ownerUserId, rootIds);
            eventPublisher.publishEvent(new FileNodesSoftDeletedEvent(ownerUserId, rootIds, deletedAt));
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
        Set<UUID> savedNodeIds = new HashSet<>();
        Set<UUID> restoredAsAncestorOnly = new HashSet<>();
        List<SharedSpaceService.SubtreeStats> sharedCharges = new ArrayList<>();
        long sharedRestoreBytes = 0L;
        for (UUID fileId : fileIds) {
            FileNode node;
            try {
                node = requireTrashOperatorNode(operatorId, fileId);
            } catch (BusinessException exception) {
                results.add(BatchItemResult.failed(fileId, exception.errorCode().name(), exception.getMessage()));
                continue;
            }
            boolean restoredByAncestor = false;
            if (!node.isDeleted()) {
                if (restoredAsAncestorOnly.remove(fileId)) {
                    // 仅作为祖先空壳被同批恢复：仍要继续恢复它自己的其余子项。
                    restoredByAncestor = true;
                } else if (savedNodeIds.contains(fileId)) {
                    // 已随上级或更早列出的子树完整恢复，仍按成功返回。
                    results.add(BatchItemResult.success(fileId));
                    continue;
                } else {
                    results.add(BatchItemResult.skipped(fileId, "文件未删除"));
                    continue;
                }
            }
            UUID nodeOwnerUserId = node.getOwnerUserId();
            SharedSpaceService.SubtreeStats sharedStats = null;
            List<FileNode> restoredAncestors;
            try {
                requireManagedNode(node);
                if (!restoredByAncestor) {
                    fileLifecycleGuard.requireRestorable(nodeOwnerUserId, node.getId());
                }
                restoredAncestors = restoreSupport.collectDeletedAncestors(node);
                restoreSupport.ensureParentAvailable(restoredAncestors.isEmpty() ? node : restoredAncestors.getFirst());
                // 作为祖先空壳恢复过的节点已经占用自己的名字，再按同级同名检查会命中自身。
                if (!restoredByAncestor
                        && sameNameExists(nodeOwnerUserId, node.getSpaceType(), node.getParentId(), node.getName())) {
                    throw new BusinessException(ErrorCode.CONFLICT, "同级目录下已存在同名文件: " + node.getName());
                }
                if (node.getSpaceType() == SpaceType.SHARED) {
                    sharedStats = sharedSpaceService.calculateRestoreSubtreeStats(node);
                    // 同批前序项已占用的容量必须计入：逐项只比数据库当前用量时，
                    // 两个单独合法的大文件会一起通过预检，最后批量补记才失败并整批回滚。
                    long requestedSharedBytes = sharedRestoreBytes + sharedStats.totalBytes();
                    sharedSpaceQuotaService.checkQuota(requestedSharedBytes);
                    sharedRestoreBytes = requestedSharedBytes;
                }
            } catch (BusinessException exception) {
                results.add(BatchItemResult.failed(fileId, exception.errorCode().name(), exception.getMessage()));
                continue;
            }
            for (FileNode ancestor : restoredAncestors) {
                restoreSupport.markRestored(ancestor);
                allToSave.add(ancestor);
                savedNodeIds.add(ancestor.getId());
                restoredAsAncestorOnly.add(ancestor.getId());
                restoredIdsByOwner
                        .computeIfAbsent(ancestor.getOwnerUserId(), key -> new ArrayList<>())
                        .add(ancestor.getId());
            }
            if (!restoredByAncestor) {
                restoreSupport.markRestored(node);
                allToSave.add(node);
                savedNodeIds.add(node.getId());
                restoredIdsByOwner.computeIfAbsent(nodeOwnerUserId, key -> new ArrayList<>()).add(node.getId());
            }
            // 同一持久化上下文里前序项可能已把后代标记为恢复，只处理仍处于删除态的节点。
            List<FileNode> descendants = restoreSupport.deletedSubtreeNodes(node).stream()
                    .filter(FileNode::isDeleted)
                    .toList();
            filePathRewriter.recomputeRestoredPaths(node, restoredAncestors, descendants);
            for (FileNode descendant : descendants) {
                restoreSupport.markRestored(descendant);
                allToSave.add(descendant);
                savedNodeIds.add(descendant.getId());
                restoredAsAncestorOnly.remove(descendant.getId());
                restoredIdsByOwner
                        .computeIfAbsent(descendant.getOwnerUserId(), key -> new ArrayList<>())
                        .add(descendant.getId());
            }
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
        // 同一批次里父目录与其后代同时出现时，父目录的移动已经带着后代整体换路径。
        Set<UUID> carriedByAncestor = nodesById.values().stream()
                .filter(candidate -> nodesById.values().stream()
                        .anyMatch(other -> candidate.isPathInside(other)))
                .map(FileNode::getId).collect(Collectors.toSet());
        List<UUID> affectedFileIds = new ArrayList<>();
        int movedCount = 0;
        for (UUID fileId : fileIds) {
            FileNode node = nodesById.get(fileId);
            if (node == null) {
                results.add(BatchItemResult.skipped(fileId, "文件不存在或已删除"));
                continue;
            }
            if (carriedByAncestor.contains(fileId)) {
                results.add(BatchItemResult.failed(fileId, ErrorCode.PARAM_ERROR.name(), "父级目录已在本次批量移动中"));
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
                    affectedFileIds.addAll(
                            filePathRewriter.rewriteDescendantPaths(
                                    ownerUserId, node.getSpaceType(), oldPath, newPath));
                    fileNodeRepository.save(node);
                    if (NodeType.FILE.getValue().equals(node.getNodeType())) {
                        affectedFileIds.add(node.getId());
                    }
                    movedCount++;
                }
                results.add(BatchItemResult.success(fileId));
            } catch (BusinessException exception) {
                results.add(BatchItemResult.failed(fileId, exception.errorCode().name(), exception.getMessage()));
            }
        }
        if (!affectedFileIds.isEmpty()) {
            // 批量移动同样改变了文件路径，索引必须随事务提交重建。
            fileIndexSyncService.scheduleAfterCommit(ownerUserId, affectedFileIds);
        }
        if (movedCount > 0) {
            recordLibraryInvalidation(ownerUserId, SyncAction.UPDATED, movedCount);
        }
        return results;
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
        // 软删除会撤销分享与授权；恢复后不能留下“已分享”的假状态。
        node.setShared(false);
        node.setSharedAt(null);
        node.setUpdatedAt(deletedAt);
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
