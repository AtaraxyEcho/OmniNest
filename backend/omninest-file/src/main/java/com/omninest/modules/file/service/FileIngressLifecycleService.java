package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileIngressItem;
import com.omninest.modules.file.domain.FileIngressStatus;
import com.omninest.modules.file.repository.FileIngressItemRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 在独立事务中维护文件安全入库状态。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileIngressLifecycleService {
    private final FileIngressItemRepository ingressItemRepository;

    /**
     * 创建或复用上传会话的入库记录。
     *
     * @param command 入库命令
     * @return 入库记录标识
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public UUID open(IngressCommand command) {
        FileIngressItem item = command.uploadSessionId() == null
                ? new FileIngressItem()
                : ingressItemRepository.findByUploadSessionId(command.uploadSessionId())
                        .orElseGet(FileIngressItem::new);
        if (item.getId() != null && item.getStatus() == FileIngressStatus.AVAILABLE) {
            return item.getId();
        }
        item.setOwnerUserId(command.ownerUserId());
        item.setSourceType(command.sourceType());
        item.setSourceTaskId(command.sourceTaskId());
        item.setUploadSessionId(command.uploadSessionId());
        item.setQuarantineBucket(command.quarantineBucket());
        item.setQuarantineObjectKey(command.quarantineObjectKey());
        item.setTargetBucket(command.targetBucket());
        item.setTargetObjectKey(command.targetObjectKey());
        item.setTargetParentId(command.targetParentId());
        item.setTargetName(command.targetName());
        item.setSizeBytes(command.sizeBytes());
        item.setMimeType(command.mimeType());
        item.setStatus(FileIngressStatus.PENDING_SCAN);
        item.setThreatName(null);
        item.setErrorCode(null);
        return ingressItemRepository.save(item).getId();
    }

    /**
     * 标记扫描开始。
     *
     * @param ingressId 入库记录标识
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markScanning(UUID ingressId) {
        FileIngressItem item = requireItem(ingressId);
        item.setStatus(FileIngressStatus.SCANNING);
        item.setScanAttemptCount(item.getScanAttemptCount() + 1);
        ingressItemRepository.save(item);
    }

    /**
     * 标记扫描通过。
     *
     * @param ingressId 入库记录标识
     * @param sha256 服务端摘要
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markClean(UUID ingressId, String sha256) {
        FileIngressItem item = requireItem(ingressId);
        item.setStatus(FileIngressStatus.CLEAN);
        item.setSha256(sha256);
        item.setErrorCode(null);
        ingressItemRepository.save(item);
    }

    /**
     * 标记文件已经发布为业务节点。
     *
     * @param ingressId 入库记录标识
     * @param fileNodeId 文件节点标识
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markAvailable(UUID ingressId, UUID fileNodeId) {
        applyAvailable(ingressId, fileNodeId);
    }

    /**
     * 在调用方现有事务内标记文件已经发布为业务节点。
     *
     * <p>发布链路要求“业务资产置可用 + 配额结算 + 入库记录置可用”原子提交，任何一步失败
     * 都必须整体回滚；{@link #markAvailable} 的独立事务会破坏该原子性，因此发布方在
     * 自身事务块内改用本方法。无事务上下文调用直接抛异常，避免误用后静默降级。</p>
     *
     * @param ingressId 入库记录标识
     * @param fileNodeId 文件节点标识
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public void markAvailableWithinTransaction(UUID ingressId, UUID fileNodeId) {
        applyAvailable(ingressId, fileNodeId);
    }

    private void applyAvailable(UUID ingressId, UUID fileNodeId) {
        FileIngressItem item = requireItem(ingressId);
        item.setStatus(FileIngressStatus.AVAILABLE);
        item.setResultFileNodeId(fileNodeId);
        item.setNextScanAt(null);
        item.setErrorCode(null);
        ingressItemRepository.save(item);
    }

    /**
     * 标记扫描或发布失败。
     *
     * @param ingressId 入库记录标识
     * @param rejected 是否因威胁被拒绝
     * @param errorCode 稳定错误码
     * @param summary 有界错误摘要
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markFailed(UUID ingressId, boolean rejected, String errorCode, String summary) {
        FileIngressItem item = requireItem(ingressId);
        item.setStatus(rejected ? FileIngressStatus.REJECTED : FileIngressStatus.FAILED);
        item.setErrorCode(errorCode);
        item.setThreatName(rejected ? bounded(summary) : null);
        ingressItemRepository.save(item);
    }

    private FileIngressItem requireItem(UUID ingressId) {
        return ingressItemRepository.findById(ingressId)
                .orElseThrow(() -> new IllegalStateException("文件入库记录不存在: " + ingressId));
    }

    private String bounded(String summary) {
        if (summary == null || summary.isBlank()) {
            return null;
        }
        return summary.length() <= 255 ? summary : summary.substring(0, 255);
    }

    /**
     * 创建文件安全入库记录所需的数据。
     *
     * @param ownerUserId 所属用户
     * @param sourceType 来源类型
     * @param sourceTaskId 来源任务
     * @param uploadSessionId 上传会话
     * @param quarantineBucket 隔离桶
     * @param quarantineObjectKey 隔离对象键
     * @param targetBucket 目标桶
     * @param targetObjectKey 目标对象键
     * @param targetParentId 目标父节点
     * @param targetName 目标文件名
     * @param sizeBytes 文件大小
     * @param mimeType MIME 类型
     * @author OmniNest
     */
    public record IngressCommand(
            UUID ownerUserId,
            String sourceType,
            UUID sourceTaskId,
            UUID uploadSessionId,
            String quarantineBucket,
            String quarantineObjectKey,
            String targetBucket,
            String targetObjectKey,
            UUID targetParentId,
            String targetName,
            long sizeBytes,
            String mimeType
    ) {
    }
}
