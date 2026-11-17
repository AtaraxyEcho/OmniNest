package com.omninest.modules.reader.event;

import java.util.UUID;

/**
 * 漫画解析任务消息：投递到 RabbitMQ，由 Worker 消费。
 *
 * @param taskId      任务 ID（用于幂等和状态追踪）
 * @param ownerUserId 所有者用户 ID
 * @param itemId      漫画作品 ID
 * @param sourceId    来源 ID
 * @param fileNodeId  文件节点 ID
 * @param fileFormat  文件格式（CBZ/ZIP/EPUB）
 * @param contentHash 文件内容哈希
 * @param isRetry     是否为重试任务
 */
public record ComicParseTaskEvent(
        UUID taskId,
        UUID ownerUserId,
        UUID itemId,
        UUID sourceId,
        UUID fileNodeId,
        String fileFormat,
        String contentHash,
        boolean isRetry
) {}
