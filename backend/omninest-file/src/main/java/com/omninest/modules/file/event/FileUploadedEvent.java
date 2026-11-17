package com.omninest.modules.file.event;

import com.omninest.modules.file.domain.FileNode;
import java.time.Instant;
import java.util.UUID;

/**
 * 文件上传完成事件。
 *
 * @param fileNodeId 文件节点 ID
 * @param fileObjectId 文件对象 ID
 * @param ownerUserId 所有者用户 ID
 * @param bucket 对象存储桶
 * @param objectKey 对象键
 * @param fileName 文件名
 * @param mimeType MIME 类型
 * @param sizeBytes 文件字节数
 * @param occurredAt 发生时间
 * @author OmniNest
 */
public record FileUploadedEvent(
        UUID fileNodeId,
        UUID fileObjectId,
        UUID ownerUserId,
        String bucket,
        String objectKey,
        String fileName,
        String mimeType,
        long sizeBytes,
        Instant occurredAt
) {
    /**
     * 由存量文件节点还原事件，供索引重投与全站重建使用。
     *
     * <p>桶与对象键留空：下游的文件索引与文本提取消费都按 {@code fileNodeId} 经 File 模块
     * 回读内容定位，不消费这两个字段，留空可避免为每个节点额外查询一次对象记录。</p>
     *
     * @param node 当前活动文件节点
     * @return 可直接投递后处理任务的事件
     */
    public static FileUploadedEvent fromNode(FileNode node) {
        return new FileUploadedEvent(
                node.getId(),
                node.getCurrentObjectId(),
                node.getOwnerUserId(),
                "",
                "",
                node.getName(),
                node.getMimeType(),
                node.getSizeBytes(),
                Instant.now()
        );
    }
}
