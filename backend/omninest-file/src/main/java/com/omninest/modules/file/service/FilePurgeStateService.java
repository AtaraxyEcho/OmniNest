package com.omninest.modules.file.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FilePurgeEntry;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.FileVersion;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.event.FileNodesDeletedEvent;
import com.omninest.modules.file.event.FilePurgeRequestedEvent;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.FilePurgeEntryRepository;
import com.omninest.modules.file.repository.FileVersionRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.search.service.FileSearchIndexService;
import com.omninest.modules.task.service.TaskRecordService;
import jakarta.persistence.EntityManager;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
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
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件永久删除状态、清单和最终数据库清理服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FilePurgeStateService {
    private static final List<String> RETRYABLE_ENTRY_STATUSES = List.of("PENDING");
    private static final List<String> INCOMPLETE_ENTRY_STATUSES = List.of("PENDING", "FAILED");
    private static final int ENTRY_BATCH_SIZE = 100;
    private static final int PLANNING_BATCH_SIZE = 500;
    private static final String SOURCE_TYPE_DERIVED = "DERIVED";

    private final FileNodeRepository fileNodeRepository;
    private final FileObjectRepository fileObjectRepository;
    private final FileVersionRepository fileVersionRepository;
    private final FilePurgeEntryRepository purgeEntryRepository;
    private final FileNodePermissionRepository permissionRepository;
    private final List<FilePurgeParticipant> participants;
    private final StorageQuotaService storageQuotaService;
    private final FileSearchIndexService fileSearchIndexService;
    private final ApplicationEventPublisher eventPublisher;
    private final ReadThroughCache readThroughCache;
    private final TaskRecordService taskRecordService;
    private final EntityManager entityManager;

    /**
     * 标记任务目标为运行中。
     *
     * @param event 永久删除任务消息
     * @return 成功取得任务执行权时返回 true
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean markRunning(FilePurgeRequestedEvent event) {
        if (!taskRecordService.claimForExecution(event.taskId(), "PLANNING")) {
            return false;
        }
        long nodeCount = fileNodeRepository.countByPurgeTaskId(event.taskId());
        if (nodeCount == 0) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "永久删除任务没有关联文件");
        }
        fileNodeRepository.updatePurgeStateByTaskId(event.taskId(), FilePurgeState.RUNNING);
        int resetCount = purgeEntryRepository.resetFailedEntries(event.taskId());
        if (resetCount > 0) {
            log.info("文件永久删除失败条目已进入新一轮重试: taskId={}, entryCount={}",
                    event.taskId(), resetCount);
        }
        return true;
    }

    /**
     * 规划源文件、历史版本和业务派生对象。
     *
     * @param event 永久删除任务消息
     * @return 删除上下文
     */
    @Transactional(rollbackFor = Exception.class)
    public PurgeContext plan(FilePurgeRequestedEvent event) {
        boolean firstPlanningPass = !purgeEntryRepository.existsByTaskId(event.taskId());
        long previousNodeCount;
        long currentNodeCount = fileNodeRepository.countByPurgeTaskId(event.taskId());
        do {
            previousNodeCount = currentNodeCount;
            planAllTaskNodeBatches(event);
            currentNodeCount = fileNodeRepository.countByPurgeTaskId(event.taskId());
        } while (currentNodeCount > previousNodeCount);
        if (firstPlanningPass) {
            taskRecordService.updateExecution(event.taskId(), "PLANNING", 20);
        }
        return new PurgeContext(
                event.taskId(),
                event.ownerUserId(),
                event.rootFileNodeId(),
                List.of(event.rootFileNodeId())
        );
    }

    private void planAllTaskNodeBatches(FilePurgeRequestedEvent event) {
        int pageNumber = 0;
        Page<FileNode> page;
        do {
            page = fileNodeRepository.findByPurgeTaskIdOrderById(
                    event.taskId(),
                    PageRequest.of(pageNumber, PLANNING_BATCH_SIZE)
            );
            if (!page.isEmpty()) {
                planNodeBatch(event, page.getContent());
            }
            pageNumber++;
        } while (page.hasNext());
    }

    private void planNodeBatch(FilePurgeRequestedEvent event, List<FileNode> nodes) {
        validateTaskNodes(event, nodes);
        List<UUID> nodeIds = nodes.stream().map(FileNode::getId).toList();
        PurgeContext context = new PurgeContext(
                event.taskId(),
                event.ownerUserId(),
                event.rootFileNodeId(),
                nodeIds
        );
        LinkedHashSet<UUID> contributedNodeIds = new LinkedHashSet<>();
        List<LegacyObjectReference> legacyObjects = new ArrayList<>();
        PurgeContributionWriter writer = new PurgeContributionWriter() {
            @Override
            public void addFileNodeIds(Collection<UUID> fileNodeIds) {
                if (fileNodeIds != null) {
                    fileNodeIds.stream().filter(Objects::nonNull).forEach(contributedNodeIds::add);
                }
            }

            @Override
            public void addLegacyObjects(Collection<LegacyObjectReference> references) {
                if (references != null) {
                    references.stream().filter(Objects::nonNull).forEach(legacyObjects::add);
                }
            }
        };
        participants.forEach(participant -> participant.contribute(context, writer));
        if (!contributedNodeIds.isEmpty()) {
            fileNodeRepository.assignIdsToPurge(
                    event.ownerUserId(),
                    contributedNodeIds,
                    event.taskId(),
                    FilePurgeState.RUNNING,
                    Instant.now()
            );
        }

        List<FileVersion> versions = fileVersionRepository.findByFileNodeIdIn(nodeIds);
        Map<UUID, FileObject> objects = loadObjects(nodes, versions);
        Set<UUID> externallyReferencedObjectIds = findExternallyReferencedObjectIds(objects.keySet());
        Map<EntryKey, FilePurgeEntry> entries = new LinkedHashMap<>();
        if (!objects.isEmpty()) {
            purgeEntryRepository.findByTaskIdAndObjectIdIn(event.taskId(), objects.keySet())
                    .forEach(entry -> entries.put(entryKey(entry), entry));
        }
        purgeEntryRepository.findByTaskIdAndEntryType(event.taskId(), "LEGACY")
                .forEach(entry -> entries.put(entryKey(entry), entry));
        Set<EntryKey> existingKeys = Set.copyOf(entries.keySet());
        nodes.forEach(node -> addCurrentObjectEntry(
                event,
                objects,
                externallyReferencedObjectIds,
                entries,
                node
        ));
        versions.forEach(version -> addVersionEntry(
                event,
                objects,
                externallyReferencedObjectIds,
                entries,
                version
        ));
        legacyObjects.forEach(reference -> addLegacyEntry(entries, event, reference));
        List<FilePurgeEntry> newEntries = entries.entrySet().stream()
                .filter(entry -> !existingKeys.contains(entry.getKey()))
                .map(Map.Entry::getValue)
                .toList();
        if (!newEntries.isEmpty()) {
            purgeEntryRepository.saveAll(newEntries);
        }
        entityManager.flush();
        entityManager.clear();
    }

    /**
     * 查询下一批待删除对象。
     *
     * @param taskId 任务 ID
     * @return 待处理条目
     */
    @Transactional(readOnly = true)
    public List<FilePurgeEntry> nextEntries(UUID taskId) {
        return purgeEntryRepository.findByTaskIdAndStatusInOrderByCreatedAtAsc(
                taskId,
                RETRYABLE_ENTRY_STATUSES,
                PageRequest.of(0, ENTRY_BATCH_SIZE)
        );
    }

    /**
     * 将对象条目标记为成功终态。
     *
     * @param entryId 条目 ID
     * @param status DELETED 或 NOT_FOUND
     */
    @Transactional(rollbackFor = Exception.class)
    public void markEntryCompleted(UUID entryId, String status) {
        FilePurgeEntry entry = requireEntry(entryId);
        entry.setStatus(status);
        entry.setAttemptCount(entry.getAttemptCount() + 1);
        entry.setLastErrorCode(null);
        purgeEntryRepository.save(entry);
    }

    /**
     * 将对象条目标记为失败。
     *
     * @param entryId 条目 ID
     * @param errorCode 稳定错误码
     */
    @Transactional(rollbackFor = Exception.class)
    public void markEntryFailed(UUID entryId, String errorCode) {
        FilePurgeEntry entry = requireEntry(entryId);
        entry.setStatus("FAILED");
        entry.setAttemptCount(entry.getAttemptCount() + 1);
        entry.setLastErrorCode(errorCode);
        purgeEntryRepository.save(entry);
    }

    /**
     * 更新删除阶段进度。
     *
     * @param taskId 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateDeletingProgress(UUID taskId) {
        long total = purgeEntryRepository.countByTaskId(taskId);
        if (total == 0) {
            taskRecordService.updateExecution(taskId, "DELETING_OBJECTS", 70);
            return;
        }
        long incomplete = purgeEntryRepository.countByTaskIdAndStatusIn(
                taskId,
                INCOMPLETE_ENTRY_STATUSES
        );
        long completed = total - incomplete;
        int progress = 20 + (int) Math.floor(completed * 50.0 / total);
        taskRecordService.updateExecution(taskId, "DELETING_OBJECTS", progress);
    }

    /**
     * 校验删除清单已全部完成。
     *
     * @param taskId 任务 ID
     */
    @Transactional(readOnly = true)
    public void verifyCompleted(UUID taskId) {
        if (purgeEntryRepository.countByTaskIdAndStatusIn(taskId, INCOMPLETE_ENTRY_STATUSES) > 0) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "永久删除清单仍有失败对象");
        }
    }

    /**
     * 将任务推进到引用验证阶段。
     *
     * @param taskId 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void markVerifying(UUID taskId) {
        taskRecordService.updateExecution(taskId, "VERIFYING_REFERENCES", 75);
    }

    /**
     * 将任务推进到数据库最终清理阶段。
     *
     * @param taskId 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void markFinalizing(UUID taskId) {
        taskRecordService.updateExecution(taskId, "FINALIZING_DATABASE", 90);
    }

    /**
     * 在对象删除完成后清理业务关系和文件元数据。
     *
     * @param event 永久删除任务消息
     */
    @Transactional(rollbackFor = Exception.class)
    public void finalizePurge(FilePurgeRequestedEvent event) {
        long releasedBytes = 0L;
        long deletedNodeCount = 0L;
        Set<UUID> candidateObjectIds = new HashSet<>();
        while (true) {
            Page<FileNode> page = fileNodeRepository.findByPurgeTaskIdOrderById(
                    event.taskId(),
                    PageRequest.of(0, PLANNING_BATCH_SIZE)
            );
            if (page.isEmpty()) {
                break;
            }
            FinalizationResult result = finalizeNodeBatch(event, page.getContent());
            releasedBytes += result.releasedBytes();
            deletedNodeCount += result.nodeCount();
            candidateObjectIds.addAll(result.objectIds());
            entityManager.flush();
            entityManager.clear();
        }
        // file_objects 行必须等整任务所有批次处理完再删：首批删行会让后续批次
        // 取不到版本对象大小，把已用配额永久留在高位；同时这里按全表引用复核，
        // 并发任务的节点或版本尚未删除时不能提前删行。
        int deletedObjectCount = deleteUnreferencedObjects(candidateObjectIds);
        if (releasedBytes > 0L) {
            storageQuotaService.decrementUsage(event.ownerUserId(), releasedBytes);
        }
        readThroughCache.invalidate("omninest:storage:stats:" + event.ownerUserId());
        taskRecordService.markCompleted(event.taskId(), Map.of(
                "fileNodeCount", deletedNodeCount,
                "objectCount", purgeEntryRepository.countByTaskId(event.taskId()),
                "deletedObjectRowCount", deletedObjectCount,
                "releasedBytes", releasedBytes
        ));
        log.info("文件永久删除完成: taskId={}, ownerUserId={}, nodeCount={}, releasedBytes={}",
                event.taskId(), event.ownerUserId(), deletedNodeCount, releasedBytes);
    }

    private int deleteUnreferencedObjects(Collection<UUID> objectIds) {
        if (objectIds.isEmpty()) {
            return 0;
        }
        List<UUID> ids = List.copyOf(objectIds);
        int deleted = 0;
        for (int start = 0; start < ids.size(); start += PLANNING_BATCH_SIZE) {
            List<UUID> batch = ids.subList(start, Math.min(start + PLANNING_BATCH_SIZE, ids.size()));
            Set<UUID> referenced = new HashSet<>(fileNodeRepository.findCurrentObjectIdsInUse(batch));
            referenced.addAll(fileVersionRepository.findObjectIdsInUse(batch));
            List<FileObject> orphans = fileObjectRepository.findAllById(batch).stream()
                    .filter(object -> !referenced.contains(object.getId()))
                    .toList();
            if (!orphans.isEmpty()) {
                fileObjectRepository.deleteAllInBatch(orphans);
                deleted += orphans.size();
            }
        }
        return deleted;
    }

    private FinalizationResult finalizeNodeBatch(FilePurgeRequestedEvent event, List<FileNode> nodes) {
        validateTaskNodes(event, nodes);
        List<UUID> nodeIds = nodes.stream().map(FileNode::getId).toList();
        PurgeContext context = new PurgeContext(
                event.taskId(),
                event.ownerUserId(),
                event.rootFileNodeId(),
                nodeIds
        );
        participants.forEach(participant -> participant.finalizePurge(context));
        List<FileVersion> versions = fileVersionRepository.findByFileNodeIdIn(nodeIds);
        Set<UUID> objectIds = new HashSet<>();
        nodes.stream().map(FileNode::getCurrentObjectId).filter(Objects::nonNull).forEach(objectIds::add);
        versions.stream().map(FileVersion::getObjectId).forEach(objectIds::add);
        List<FileObject> batchObjects = fileObjectRepository.findAllById(objectIds);

        // 共享空间一个目录可能混有多个成员上传的文件，失效事件必须按真实归属人分组：
        // 只按任务发起者投递会漏清其他人名下的分享链接与客户端缓存。
        Map<UUID, List<UUID>> idsByOwner = groupNodeIdsByOwner(nodes);
        Instant deletedAt = Instant.now();
        idsByOwner.forEach((owner, ids) -> eventPublisher.publishEvent(
                new FileNodesDeletedEvent(owner, List.copyOf(ids), deletedAt)));
        permissionRepository.deleteByFileNodeIdIn(nodeIds);
        fileVersionRepository.deleteByFileNodeIdIn(nodeIds);
        long releasedBytes = quotaReleaseBytes(nodes, versions, sizeByObjectId(batchObjects));
        // 索引删除覆盖个人与共享两个索引目录，节点归属人不影响清理结果。
        fileSearchIndexService.deleteFiles(nodeIds, event.ownerUserId());
        fileNodeRepository.deleteAllInBatch(nodes);
        fileNodeRepository.flush();
        return new FinalizationResult(nodes.size(), releasedBytes, Set.copyOf(objectIds));
    }

    /**
     * 计算彻底删除应释放的字节数，口径与配额记账一致。
     * 每个记账的个人文件节点的占用＝节点自身大小（上传或转存时全额加计），
     * 加上该节点历史版本对象的占用：新版本上传按新对象加计、恢复只在当前对象与版本行之间换位，
     * 两者都不改变账本总量，所以删除必须一并释放，否则版本字节会永久留在 used_bytes 上。
     * 与所在节点当前对象同引用的版本行不重复计，同一节点内重复出现的对象标识也只计一次。
     *
     * <p>只释放 PERSONAL 空间且计入配额的节点：共享空间文件在软删除时已由
     * {@code SharedSpaceService} 退还共享用量，个人账本从未计入它们；系统可重建的派生资产
     * 与只读本地影视库索引节点写入时从未加计，删除时同样不能扣减，否则每删一张照片都会
     * 把用户的 used_bytes 多扣掉缩略图/转码的体积。判定见 {@link #isQuotaCountedNode}。</p>
     */
    static long quotaReleaseBytes(
            List<FileNode> nodes,
            List<FileVersion> versions,
            Map<UUID, Long> objectSizes
    ) {
        long released = 0L;
        Map<UUID, UUID> currentObjectByNodeId = new LinkedHashMap<>();
        Set<UUID> personalNodeIds = new HashSet<>();
        for (FileNode node : nodes) {
            if (!NodeType.FILE.getValue().equals(node.getNodeType())
                    || node.getSpaceType() != SpaceType.PERSONAL
                    || !isQuotaCountedNode(node)) {
                continue;
            }
            personalNodeIds.add(node.getId());
            released += node.getSizeBytes();
            if (node.getCurrentObjectId() != null) {
                currentObjectByNodeId.put(node.getId(), node.getCurrentObjectId());
            }
        }
        Map<UUID, Set<UUID>> countedObjectIdsByNode = new LinkedHashMap<>();
        for (FileVersion version : versions) {
            UUID objectId = version.getObjectId();
            UUID nodeKey = version.getFileNodeId();
            if (!personalNodeIds.contains(nodeKey)) {
                continue;
            }
            if (objectId == null || objectId.equals(currentObjectByNodeId.get(nodeKey))) {
                continue;
            }
            Set<UUID> counted = countedObjectIdsByNode.computeIfAbsent(nodeKey, key -> new HashSet<>());
            if (!counted.add(objectId)) {
                continue;
            }
            released += objectSizes.getOrDefault(objectId, 0L);
        }
        return released;
    }

    private static Map<UUID, Long> sizeByObjectId(List<FileObject> objects) {
        Map<UUID, Long> sizes = new LinkedHashMap<>();
        objects.forEach(object -> sizes.put(object.getId(), object.getSizeBytes()));
        return sizes;
    }

    /**
     * 判断派生节点是否计入个人配额。
     *
     * <p>写入侧只对用户上传的内容与两类不可重建的派生写入加计配额：背景图原片与照片编辑
     * 版本（分别落在 {@code /.metadata/BACKDROP/{id}/ORIGINAL/...} 与
     * {@code /.metadata/PHOTO_ITEM/{id}/EDIT_VERSION/...}）。其余派生资产和只读本地影视库
     * 索引节点从不加计。谓词与 {@code FileMetricsRepository#sumFileSizeForUsers} 必须同一口径，
     * 否则夜间对账与彻底删除释放会互相抵消。</p>
     */
    private static boolean isQuotaCountedNode(FileNode node) {
        String sourceType = node.getSourceType();
        if (sourceType == null) {
            return true;
        }
        if (!"DERIVED".equals(sourceType)) {
            return !"LOCAL_FILESYSTEM".equals(sourceType);
        }
        return isChargedDerivedPath(node.getNormalizedPath());
    }

    private static boolean isChargedDerivedPath(String normalizedPath) {
        if (normalizedPath == null) {
            return false;
        }
        String[] segments = normalizedPath.split("/");
        if (segments.length < 6 || !".metadata".equals(segments[1])) {
            return false;
        }
        if ("BACKDROP".equals(segments[2])) {
            return "ORIGINAL".equals(segments[4]);
        }
        return "PHOTO_ITEM".equals(segments[2]) && "EDIT_VERSION".equals(segments[4]);
    }

    /**
     * 更新任务关联节点的永久删除状态。
     *
     * @param taskId 任务 ID
     * @param state 目标状态
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateNodeState(UUID taskId, FilePurgeState state) {
        fileNodeRepository.updatePurgeStateByTaskId(taskId, state);
    }

    static Map<UUID, List<UUID>> groupNodeIdsByOwner(List<FileNode> nodes) {
        Map<UUID, List<UUID>> idsByOwner = new LinkedHashMap<>();
        for (FileNode node : nodes) {
            UUID owner = node.getSpaceType() == SpaceType.SHARED && node.getUploadedBy() != null
                    ? node.getUploadedBy()
                    : node.getOwnerUserId();
            idsByOwner.computeIfAbsent(owner, key -> new ArrayList<>()).add(node.getId());
        }
        return idsByOwner;
    }

    static void validateTaskNodes(FilePurgeRequestedEvent event, List<FileNode> nodes) {
        if (nodes.isEmpty()) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "永久删除任务没有关联文件");
        }
        // 共享空间目录可由不同成员上传子文件，owner_user_id 因此天然不一致；
        // 只有个人空间节点必须与任务发起者一致。
        boolean invalidOwner = nodes.stream()
                .anyMatch(node -> node.getSpaceType() != SpaceType.SHARED
                        && !event.ownerUserId().equals(node.getOwnerUserId()));
        if (invalidOwner) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "永久删除任务文件归属不一致");
        }
    }

    private Map<UUID, FileObject> loadObjects(List<FileNode> nodes, List<FileVersion> versions) {
        Set<UUID> objectIds = new LinkedHashSet<>();
        nodes.stream().map(FileNode::getCurrentObjectId).filter(Objects::nonNull).forEach(objectIds::add);
        versions.stream().map(FileVersion::getObjectId).forEach(objectIds::add);
        Map<UUID, FileObject> objects = new LinkedHashMap<>();
        fileObjectRepository.findAllById(objectIds).forEach(object -> objects.put(object.getId(), object));
        return objects;
    }

    private Set<UUID> findExternallyReferencedObjectIds(Collection<UUID> objectIds) {
        if (objectIds.isEmpty()) {
            return Set.of();
        }
        Set<UUID> referencedObjectIds = new HashSet<>(
                fileNodeRepository.findCurrentObjectIdsReferencedByUnpurgedNodes(objectIds)
        );
        referencedObjectIds.addAll(
                fileVersionRepository.findObjectIdsReferencedByUnpurgedNodes(objectIds)
        );
        return referencedObjectIds;
    }

    private void addCurrentObjectEntry(
            FilePurgeRequestedEvent event,
            Map<UUID, FileObject> objects,
            Set<UUID> externallyReferencedObjectIds,
            Map<EntryKey, FilePurgeEntry> entries,
            FileNode node
    ) {
        UUID objectId = node.getCurrentObjectId();
        if (objectId == null || externallyReferencedObjectIds.contains(objectId)) {
            return;
        }
        FileObject object = objects.get(objectId);
        if (object == null) {
            return;
        }
        String entryType = SOURCE_TYPE_DERIVED.equals(node.getSourceType()) ? "DERIVED" : "SOURCE";
        addEntry(entries, event, node.getId(), object, null, entryType);
    }

    private void addVersionEntry(
            FilePurgeRequestedEvent event,
            Map<UUID, FileObject> objects,
            Set<UUID> externallyReferencedObjectIds,
            Map<EntryKey, FilePurgeEntry> entries,
            FileVersion version
    ) {
        UUID objectId = version.getObjectId();
        if (externallyReferencedObjectIds.contains(objectId)) {
            return;
        }
        FileObject object = objects.get(objectId);
        if (object != null) {
            addEntry(entries, event, version.getFileNodeId(), object, version.getMinioVersionId(), "VERSION");
        }
    }

    private void addEntry(
            Map<EntryKey, FilePurgeEntry> entries,
            FilePurgeRequestedEvent event,
            UUID fileNodeId,
            FileObject object,
            String minioVersionId,
            String entryType
    ) {
        EntryKey key = new EntryKey(object.getBucketName(), object.getObjectKey(), minioVersionId);
        entries.computeIfAbsent(key, ignored -> {
            FilePurgeEntry entry = new FilePurgeEntry();
            entry.setTaskId(event.taskId());
            entry.setOwnerUserId(event.ownerUserId());
            entry.setFileNodeId(fileNodeId);
            entry.setObjectId(object.getId());
            entry.setBucketName(object.getBucketName());
            entry.setObjectKey(object.getObjectKey());
            entry.setMinioVersionId(minioVersionId);
            entry.setEntryType(entryType);
            return entry;
        });
    }

    private void addLegacyEntry(
            Map<EntryKey, FilePurgeEntry> entries,
            FilePurgeRequestedEvent event,
            LegacyObjectReference reference
    ) {
        EntryKey key = new EntryKey(reference.bucketName(), reference.objectKey(), null);
        entries.computeIfAbsent(key, ignored -> {
            FilePurgeEntry entry = new FilePurgeEntry();
            entry.setTaskId(event.taskId());
            entry.setOwnerUserId(event.ownerUserId());
            entry.setBucketName(reference.bucketName());
            entry.setObjectKey(reference.objectKey());
            entry.setEntryType("LEGACY");
            return entry;
        });
    }

    private FilePurgeEntry requireEntry(UUID entryId) {
        return purgeEntryRepository.findById(entryId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "永久删除清单条目不存在"));
    }

    private EntryKey entryKey(FilePurgeEntry entry) {
        return new EntryKey(entry.getBucketName(), entry.getObjectKey(), entry.getMinioVersionId());
    }

    private record EntryKey(String bucketName, String objectKey, String minioVersionId) {
    }

    private record FinalizationResult(long nodeCount, long releasedBytes, Set<UUID> objectIds) {
    }
}
