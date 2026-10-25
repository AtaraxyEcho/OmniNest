package com.omninest.modules.file.service;

import com.omninest.common.concurrency.DistributedLock;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FilePurgeImpactDto;
import com.omninest.modules.file.event.FilePurgeRequestedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 文件永久删除任务创建服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileDeletionService {
    private static final String TASK_TYPE = "FILE_PURGE";
    private static final String RESOURCE_TYPE = "FILE_NODE";
    private static final Duration LOCK_TTL = Duration.ofSeconds(30);
    private static final int LIFECYCLE_BATCH_SIZE = 500;
    private static final List<String> ACTIVE_STATUSES = List.of(
            TaskStatus.QUEUED.getValue(),
            TaskStatus.RUNNING.getValue(),
            TaskStatus.RETRY_WAIT.getValue()
    );

    private final FileNodeRepository fileNodeRepository;
    private final FileQueryService fileQueryService;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final DistributedLock distributedLock;
    private final PlatformTransactionManager transactionManager;
    private final List<FilePurgeParticipant> participants;

    /**
     * 创建用户文件永久删除任务。
     *
     * @param ownerUserId 操作用户 ID；共享空间允许实际删除者清理自己的回收站
     * @param fileNodeId 文件节点 ID
     * @return 任务 ID
     */
    public UUID deletePermanently(UUID ownerUserId, UUID fileNodeId) {
        return deletePermanently(ownerUserId, fileNodeId, false, null, null);
    }

    /**
     * 创建带业务引用裁决的永久删除任务。
     *
     * @param ownerUserId 操作用户 ID；共享空间允许实际删除者清理自己的回收站
     * @param fileNodeId 文件节点 ID
     * @param cascade 是否允许级联清理额外业务引用
     * @param origin 请求来源业务资源
     * @param expectedVersion 预期文件版本，可为空
     * @return 任务 ID
     */
    public UUID deletePermanently(
            UUID ownerUserId,
            UUID fileNodeId,
            boolean cascade,
            FilePurgeOrigin origin,
            Long expectedVersion
    ) {
        String lockKey = "lock:file-lifecycle:" + fileNodeId;
        String lockToken = distributedLock.newToken();
        LockAttempt lockAttempt = tryAcquireLock(lockKey, lockToken);
        if (lockAttempt.redisAvailable() && !lockAttempt.acquired()) {
            return findActiveTask(ownerUserId, fileNodeId)
                    .map(TaskRecord::getId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.CONFLICT, "文件正在执行其他生命周期操作"));
        }
        try {
            TransactionTemplate transactionTemplate = new TransactionTemplate(transactionManager);
            transactionTemplate.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
            UUID taskId = transactionTemplate.execute(status -> createTaskInTransaction(
                    ownerUserId,
                    fileNodeId,
                    cascade,
                    origin,
                    expectedVersion
            ));
            if (taskId == null) {
                throw new BusinessException(ErrorCode.INTERNAL_ERROR, "永久删除任务创建失败");
            }
            return taskId;
        } finally {
            if (lockAttempt.acquired()) {
                releaseLock(lockKey, lockToken);
            }
        }
    }

    /**
     * 为多个文件根节点创建一个永久删除任务。
     *
     * @param ownerUserId 文件所有者用户 ID
     * @param fileNodeIds 文件根节点 ID
     * @param cascade 是否允许级联清理额外业务引用
     * @param origins 请求来源业务资源
     * @return 任务 ID
     */
    public UUID deletePermanentlyBatch(
            UUID ownerUserId,
            List<UUID> fileNodeIds,
            boolean cascade,
            List<FilePurgeOrigin> origins
    ) {
        List<UUID> distinctIds = fileNodeIds.stream()
                .distinct()
                .sorted()
                .toList();
        if (distinctIds.isEmpty()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "永久删除文件列表不能为空");
        }

        List<LifecycleLock> acquiredLocks = new ArrayList<>();
        try {
            for (UUID fileNodeId : distinctIds) {
                String lockKey = "lock:file-lifecycle:" + fileNodeId;
                String lockToken = distributedLock.newToken();
                LockAttempt lockAttempt = tryAcquireLock(lockKey, lockToken);
                if (lockAttempt.redisAvailable() && !lockAttempt.acquired()) {
                    throw new BusinessException(
                            ErrorCode.FILE_LIFECYCLE_CONFLICT,
                            "批量永久删除包含正在执行其他生命周期操作的文件"
                    );
                }
                if (lockAttempt.acquired()) {
                    acquiredLocks.add(new LifecycleLock(lockKey, lockToken));
                }
            }

            TransactionTemplate transactionTemplate = new TransactionTemplate(transactionManager);
            transactionTemplate.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
            UUID taskId = transactionTemplate.execute(status -> createBatchTaskInTransaction(
                    ownerUserId,
                    distinctIds,
                    cascade,
                    origins == null ? List.of() : List.copyOf(origins)
            ));
            if (taskId == null) {
                throw new BusinessException(ErrorCode.INTERNAL_ERROR, "批量永久删除任务创建失败");
            }
            return taskId;
        } finally {
            for (int index = acquiredLocks.size() - 1; index >= 0; index--) {
                LifecycleLock lock = acquiredLocks.get(index);
                releaseLock(lock.key(), lock.token());
            }
        }
    }

    /**
     * 预览永久删除影响，不改变文件状态。
     *
     * @param operatorId 操作用户 ID
     * @param fileNodeId 文件节点 ID
     * @param origin 请求来源业务资源
     * @return 删除影响摘要
     */
    public FilePurgeImpactDto previewImpact(UUID operatorId, UUID fileNodeId, FilePurgeOrigin origin) {
        FileNode root = resolvePurgePreviewRoot(operatorId, fileNodeId);
        List<FilePurgeOrigin> origins = origin == null ? List.of() : List.of(origin);
        return calculateImpact(root.getOwnerUserId(), List.of(root), origins);
    }

    /**
     * 解析永久删除根节点并按所有者加锁。
     *
     * <p>个人空间仍只接受所有者；共享空间额外接受实际删除者（回收站按 deleted_by 展示），
     * 权限复核与恢复共用同一判定。共享节点的 owner_user_id 是上传者，后续子树更新、
     * 任务负载和事件都必须使用该 ID，不能使用删除者。</p>
     */
    private FileNode resolvePurgeRoot(UUID operatorId, UUID fileNodeId) {
        Optional<FileNode> owned = fileNodeRepository.findOwnedForUpdate(fileNodeId, operatorId);
        if (owned.isPresent()) {
            FileNode root = owned.get();
            fileQueryService.requireSharedLifecycleOperator(operatorId, root);
            return root;
        }
        FileNode shared = fileQueryService.requireTrashOperatorNode(operatorId, fileNodeId);
        return fileNodeRepository.findOwnedForUpdate(fileNodeId, shared.getOwnerUserId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
    }

    /**
     * 预览不需要行锁，个人空间按所有者读取，共享空间回退到删除者视图。
     */
    private FileNode resolvePurgePreviewRoot(UUID operatorId, UUID fileNodeId) {
        Optional<FileNode> owned = fileNodeRepository.findByIdAndOwnerUserId(fileNodeId, operatorId);
        if (owned.isPresent()) {
            FileNode root = owned.get();
            fileQueryService.requireSharedLifecycleOperator(operatorId, root);
            return root;
        }
        return fileQueryService.requireTrashOperatorNode(operatorId, fileNodeId);
    }

    private UUID createTaskInTransaction(
            UUID operatorId,
            UUID fileNodeId,
            boolean cascade,
            FilePurgeOrigin origin,
            Long expectedVersion
    ) {
        FileNode root = resolvePurgeRoot(operatorId, fileNodeId);
        // 内容归属沿用节点上传者：子树、配额与业务事件都按它结算。
        // 任务记录归属必须写成发起操作者，否则非上传者删除后轮询自己的任务会 404。
        UUID ownerUserId = root.getOwnerUserId();
        TaskRecord activeTask = findActiveTask(operatorId, fileNodeId).orElse(null);
        if (activeTask != null) {
            return activeTask.getId();
        }
        if (root.getPurgeState() != null && root.getPurgeState() != FilePurgeState.NONE) {
            throw new BusinessException(ErrorCode.CONFLICT, "文件已进入永久删除流程");
        }
        if (expectedVersion != null && !expectedVersion.equals(root.getVersion())) {
            throw new BusinessException(ErrorCode.CONFLICT, "文件版本已变化，请重新确认删除影响");
        }
        List<FilePurgeOrigin> origins = origin == null ? List.of() : List.of(origin);
        FilePurgeImpactDto impact = calculateImpact(ownerUserId, List.of(root), origins);
        if (!cascade && impact.inUse()) {
            throw new BusinessException(
                    ErrorCode.RESOURCE_IN_USE,
                    "文件仍被其他业务资源引用，请确认影响后再执行级联删除",
                    Map.of("impact", impact)
            );
        }
        if (!root.isDeleted()) {
            // 软删除必须由实际操作人执行：共享空间要按操作者复核权限并写入 deleted_by。
            fileQueryService.deleteNode(operatorId, fileNodeId);
        }
        UUID taskId = UUID.randomUUID();
        Instant requestedAt = Instant.now();
        markPurgeQueued(root, taskId, requestedAt);
        fileNodeRepository.save(root);
        assignSubtreeToPurge(ownerUserId, root, taskId, requestedAt);
        int cancelledTaskCount = cancelRelatedTasksInBatches(List.of(ownerUserId), taskId);
        if (cancelledTaskCount > 0) {
            log.info("永久删除任务已冻结关联任务: fileNodeId={}, cancelledTaskCount={}",
                    fileNodeId, cancelledTaskCount);
        }

        Map<String, Object> payload = Map.of(
                "taskId", taskId.toString(),
                "ownerUserId", ownerUserId.toString(),
                "rootFileNodeId", fileNodeId.toString(),
                "cascade", cascade
        );
        taskRecordService.createQueuedTask(
                taskId,
                operatorId,
                TASK_TYPE,
                QueueNames.FILE_PURGE_ROUTING_KEY,
                "PLANNING",
                RESOURCE_TYPE,
                fileNodeId,
                payload
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_PURGE_ROUTING_KEY,
                new FilePurgeRequestedEvent(taskId, ownerUserId, fileNodeId)
        );
        log.info("文件永久删除任务已创建: taskId={}, operatorId={}, contentOwnerId={}, fileNodeId={}",
                taskId, operatorId, ownerUserId, fileNodeId);
        return taskId;
    }

    private UUID createBatchTaskInTransaction(
            UUID operatorId,
            List<UUID> fileNodeIds,
            boolean cascade,
            List<FilePurgeOrigin> origins
    ) {
        // 与单文件路径同一判定：个人空间只认所有者，共享空间还接受实际删除者，
        // 否则回收站里「自己删除、他人上传」的共享文件在批量彻底删除时一律 404。
        List<FileNode> roots = fileNodeIds.stream()
                .map(fileNodeId -> resolvePurgeRoot(operatorId, fileNodeId))
                .toList();
        Set<UUID> rootOwners = roots.stream()
                .map(FileNode::getOwnerUserId)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        // 共享回收站允许一次勾选多个成员上传的文件。事件与配额按内容所有者结算；
        // 若混有个人节点，则其所有者必然是操作者，事件归属取操作者。
        UUID eventOwnerUserId = roots.stream()
                .filter(root -> root.getSpaceType() != SpaceType.SHARED)
                .map(FileNode::getOwnerUserId)
                .findFirst()
                .orElseGet(() -> roots.getFirst().getOwnerUserId());

        for (UUID fileNodeId : fileNodeIds) {
            if (findActiveTask(operatorId, fileNodeId).isPresent()) {
                throw new BusinessException(
                        ErrorCode.FILE_LIFECYCLE_CONFLICT,
                        "批量永久删除包含已进入永久删除流程的文件"
                );
            }
        }

        boolean lifecycleConflict = roots.stream().anyMatch(root ->
                root.getPurgeState() != null && root.getPurgeState() != FilePurgeState.NONE);
        if (lifecycleConflict) {
            throw new BusinessException(
                    ErrorCode.FILE_LIFECYCLE_CONFLICT,
                    "批量永久删除包含已进入永久删除流程的文件"
            );
        }

        FilePurgeImpactDto impact = calculateImpact(eventOwnerUserId, roots, origins);
        if (!cascade && impact.inUse()) {
            throw new BusinessException(
                    ErrorCode.RESOURCE_IN_USE,
                    "文件仍被其他业务资源引用，请确认影响后再执行级联删除",
                    Map.of("impact", impact)
            );
        }

        for (FileNode root : roots) {
            if (!root.isDeleted()) {
                // 与单文件路径一致：共享节点由操作者软删除，个人节点要求操作者即所有者。
                fileQueryService.deleteNode(operatorId, root.getId());
            }
        }

        UUID taskId = UUID.randomUUID();
        Instant requestedAt = Instant.now();
        roots.forEach(root -> markPurgeQueued(root, taskId, requestedAt));
        fileNodeRepository.saveAll(roots);
        roots.forEach(root -> assignSubtreeToPurge(root.getOwnerUserId(), root, taskId, requestedAt));
        int cancelledTaskCount = cancelRelatedTasksInBatches(rootOwners, taskId);
        if (cancelledTaskCount > 0) {
            log.info("批量永久删除任务已冻结关联任务: taskId={}, cancelledTaskCount={}",
                    taskId, cancelledTaskCount);
        }

        UUID representativeRootId = roots.getFirst().getId();
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("taskId", taskId.toString());
        payload.put("ownerUserId", eventOwnerUserId.toString());
        payload.put("rootFileNodeId", representativeRootId.toString());
        payload.put("rootFileNodeIds", roots.stream().map(FileNode::getId).map(UUID::toString).toList());
        payload.put("cascade", cascade);
        taskRecordService.createQueuedTask(
                taskId,
                operatorId,
                TASK_TYPE,
                QueueNames.FILE_PURGE_ROUTING_KEY,
                "PLANNING",
                RESOURCE_TYPE,
                representativeRootId,
                payload
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_PURGE_ROUTING_KEY,
                new FilePurgeRequestedEvent(taskId, eventOwnerUserId, representativeRootId)
        );
        log.info("批量文件永久删除任务已创建: taskId={}, operatorId={}, contentOwnerId={}, "
                        + "rootCount={}, fileNodeCount={}",
                taskId, operatorId, eventOwnerUserId, roots.size(),
                fileNodeRepository.countByPurgeTaskId(taskId));
        return taskId;
    }

    private FilePurgeImpactDto calculateImpact(
            UUID ownerUserId,
            List<FileNode> roots,
            List<FilePurgeOrigin> origins
    ) {
        List<FileNode> effectiveRoots = removeNestedRoots(roots);
        ImpactAccumulator accumulator = new ImpactAccumulator();
        accumulateImpact(ownerUserId, roots.getFirst().getId(), effectiveRoots, origins, accumulator);
        Map<String, Integer> byModule = new LinkedHashMap<>();
        accumulator.references.forEach(reference -> byModule.merge(reference.module(), 1, Integer::sum));
        return new FilePurgeImpactDto(
                roots.getFirst().getId(),
                accumulator.nodeCount,
                accumulator.estimatedBytes,
                accumulator.references.size(),
                Map.copyOf(byModule),
                List.copyOf(accumulator.references)
        );
    }

    private void accumulateImpact(
            UUID ownerUserId,
            UUID representativeRootId,
            List<FileNode> roots,
            List<FilePurgeOrigin> origins,
            ImpactAccumulator accumulator
    ) {
        for (FileNode root : roots) {
            accumulateImpactBatch(ownerUserId, representativeRootId, List.of(root), origins, accumulator);
            if (root.getSpaceType() == SpaceType.SHARED) {
                accumulateSharedImpact(ownerUserId, representativeRootId, root, origins, accumulator);
                continue;
            }
            int pageNumber = 0;
            Page<FileNode> page;
            do {
                page = fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithOrderById(
                        ownerUserId,
                        root.getSpaceType(),
                        subtreePrefix(root),
                        PageRequest.of(pageNumber, LIFECYCLE_BATCH_SIZE)
                );
                accumulateImpactBatch(
                        ownerUserId,
                        representativeRootId,
                        page.getContent(),
                        origins,
                        accumulator
                );
                pageNumber++;
            } while (page.hasNext());
        }
    }

    /**
     * 共享空间按空间与路径前缀统计影响面：目录内可能混有多个成员上传的文件，
     * 按 owner_user_id 过滤会漏算其他成员的节点与字节。
     */
    private void accumulateSharedImpact(
            UUID ownerUserId,
            UUID representativeRootId,
            FileNode root,
            List<FilePurgeOrigin> origins,
            ImpactAccumulator accumulator
    ) {
        UUID afterId = new UUID(0L, 0L);
        while (true) {
            List<FileNode> batch = fileNodeRepository.findSubtreeBySpaceTypeAfterId(
                    SpaceType.SHARED,
                    subtreePrefix(root),
                    afterId,
                    PageRequest.of(0, LIFECYCLE_BATCH_SIZE)
            );
            if (batch.isEmpty()) {
                return;
            }
            accumulateImpactBatch(ownerUserId, representativeRootId, batch, origins, accumulator);
            afterId = batch.getLast().getId();
            if (batch.size() < LIFECYCLE_BATCH_SIZE) {
                return;
            }
        }
    }

    private void accumulateImpactBatch(
            UUID ownerUserId,
            UUID rootFileNodeId,
            List<FileNode> nodes,
            List<FilePurgeOrigin> origins,
            ImpactAccumulator accumulator
    ) {
        if (nodes.isEmpty()) {
            return;
        }
        List<UUID> ids = nodes.stream().map(FileNode::getId).toList();
        PurgeContext context = new PurgeContext(null, ownerUserId, rootFileNodeId, ids);
        participants.forEach(participant -> participant.findBusinessReferences(context).stream()
                .filter(reference -> !matchesOrigin(reference, origins))
                .forEach(accumulator.references::add));
        accumulator.nodeCount += nodes.size();
        accumulator.estimatedBytes += nodes.stream()
                .filter(node -> NodeType.FILE.getValue().equals(node.getNodeType()))
                .mapToLong(FileNode::getSizeBytes)
                .sum();
    }

    private List<FileNode> removeNestedRoots(List<FileNode> roots) {
        return roots.stream()
                .filter(candidate -> roots.stream().noneMatch(other ->
                        !candidate.getId().equals(other.getId())
                                && candidate.getSpaceType() == other.getSpaceType()
                                && candidate.getNormalizedPath().startsWith(other.getNormalizedPath() + "/")))
                .toList();
    }

    private int cancelRelatedTasksInBatches(Collection<UUID> ownerUserIds, UUID taskId) {
        int cancelledCount = 0;
        int pageNumber = 0;
        Page<UUID> page;
        do {
            page = fileNodeRepository.findIdsByPurgeTaskId(
                    taskId,
                    PageRequest.of(pageNumber, LIFECYCLE_BATCH_SIZE)
            );
            if (!page.isEmpty()) {
                for (UUID ownerUserId : ownerUserIds) {
                    cancelledCount += taskRecordService.cancelActiveResourceTasks(
                            ownerUserId,
                            RESOURCE_TYPE,
                            page.getContent(),
                            ACTIVE_STATUSES,
                            TASK_TYPE
                    );
                }
            }
            pageNumber++;
        } while (page.hasNext());
        return cancelledCount;
    }

    private boolean matchesOrigin(FileBusinessReference reference, List<FilePurgeOrigin> origins) {
        return origins.stream().anyMatch(origin ->
                origin.module() != null
                        && origin.resourceId() != null
                        && origin.module().equalsIgnoreCase(reference.module())
                        && origin.resourceId().equals(reference.resourceId()));
    }

    private Optional<TaskRecord> findActiveTask(UUID ownerUserId, UUID fileNodeId) {
        return taskRecordService.findActiveResourceTask(
                ownerUserId,
                TASK_TYPE,
                RESOURCE_TYPE,
                fileNodeId,
                ACTIVE_STATUSES
        );
    }

    /**
     * 构造子树前缀的 LIKE 字面量。
     *
     * <p>前缀来自真实目录名，消费方有两条批量更新与一条影响面预估：把后代挂到本次清理任务的
     * 更新、按子树统计业务引用的分页读取。目录名里的 {@code _} 或 {@code %} 若按通配符解释，
     * 兄弟目录的已删除文件会被同一 {@code taskId} 认领并物理清除。配套查询必须声明
     * {@code escape '\'}。</p>
     */
    /**
     * 把子树内已软删除节点挂到粉碎任务上。
     *
     * <p>共享空间按空间认领，个人空间按所有者认领：前者若仍限制所有者，
     * 别人上传的子文件不会进入物理清除清单，父目录粉碎后这些节点永久悬挂。</p>
     */
    private void assignSubtreeToPurge(UUID ownerUserId, FileNode root, UUID taskId, Instant requestedAt) {
        if (root.getSpaceType() == SpaceType.SHARED) {
            fileNodeRepository.assignDeletedDescendantsToPurgeInSpace(
                    SpaceType.SHARED,
                    subtreePrefix(root),
                    taskId,
                    FilePurgeState.QUEUED,
                    requestedAt
            );
            return;
        }
        fileNodeRepository.assignDeletedDescendantsToPurge(
                ownerUserId,
                root.getSpaceType(),
                subtreePrefix(root),
                taskId,
                FilePurgeState.QUEUED,
                requestedAt
        );
    }

    private String subtreePrefix(FileNode root) {
        return LikePatterns.escapeSpecials(root.getNormalizedPath() + "/");
    }

    private void markPurgeQueued(FileNode node, UUID taskId, Instant requestedAt) {
        node.setPurgeState(FilePurgeState.QUEUED);
        node.setPurgeTaskId(taskId);
        node.setPurgeRequestedAt(requestedAt);
    }

    private LockAttempt tryAcquireLock(String key, String token) {
        try {
            return new LockAttempt(true, distributedLock.tryLock(key, token, LOCK_TTL));
        } catch (RuntimeException exception) {
            log.warn("Redis 生命周期锁不可用，回退到数据库并发控制: key={}, errorType={}",
                    key, exception.getClass().getSimpleName());
            return new LockAttempt(false, false);
        }
    }

    private void releaseLock(String key, String token) {
        try {
            if (!distributedLock.unlock(key, token)) {
                log.warn("文件生命周期锁未释放，将等待 TTL 到期: key={}", key);
            }
        } catch (RuntimeException exception) {
            log.warn("文件生命周期锁释放失败，将等待 TTL 到期: key={}, errorType={}",
                    key, exception.getClass().getSimpleName());
        }
    }

    private record LockAttempt(boolean redisAvailable, boolean acquired) {
    }

    private record LifecycleLock(String key, String token) {
    }

    private static final class ImpactAccumulator {
        private final LinkedHashSet<FileBusinessReference> references = new LinkedHashSet<>();
        private int nodeCount;
        private long estimatedBytes;
    }
}
