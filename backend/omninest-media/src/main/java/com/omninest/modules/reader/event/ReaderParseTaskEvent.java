package com.omninest.modules.reader.event;

import java.util.UUID;

/**
 * 文本书籍解析任务消息。
 *
 * @param taskId 任务 ID
 * @param ownerUserId 所属用户 ID
 * @param itemId 阅读条目 ID
 * @param fileNodeId 文件节点 ID
 * @param fileFormat 文件格式
 * @param contentHash 内容哈希
 * @param isRetry 是否为重试消息
 * @author OmniNest
 */
public record ReaderParseTaskEvent(
        UUID taskId,
        UUID ownerUserId,
        UUID itemId,
        UUID fileNodeId,
        String fileFormat,
        String contentHash,
        boolean isRetry
) {
}
