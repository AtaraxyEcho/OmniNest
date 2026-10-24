package com.omninest.modules.search.event;

import java.util.UUID;

/**
 * 用户搜索索引目录清理事件，经 Outbox 投递给 Worker 串行执行。
 *
 * <p>索引卷由 Worker 独占写入，api 进程直接删除其它进程持有的 Lucene 目录会触发
 * 写锁冲突或留下悬空句柄；物理删除必须回到 Worker 关闭本地 writer 后再执行。</p>
 *
 * @param ownerUserId 被删除的用户 ID
 */
public record FileIndexUserPurgeEvent(UUID ownerUserId) {
}
