package com.omninest.modules.file.event;

import java.util.List;
import java.util.UUID;

/**
 * 文件搜索索引同步事件，经 Outbox 投递给 Worker 写入 Lucene。
 *
 * <p>载荷只带节点 ID：索引内容（标题、空间类型、是否已删除）由消费侧回读数据库决定，
 * 重命名、软删除与恢复可以共用同一入口，避免请求进程把过期字段写进索引。</p>
 *
 * @param ownerUserId 索引归属用户 ID
 * @param fileNodeIds 需要同步的文件节点 ID
 */
public record FileIndexSyncEvent(UUID ownerUserId, List<UUID> fileNodeIds) {
}
