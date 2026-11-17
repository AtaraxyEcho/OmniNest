package com.omninest.common.config;

import java.time.Instant;
import java.util.UUID;

/**
 * 描述需要广播到各运行节点的配置变更。
 *
 * @param version 事件版本标识
 * @param key 变更的配置键
 * @param changedAt 变更时间
 * @author OmniNest
 */
public record ConfigRefreshEvent(
        UUID version,
        String key,
        Instant changedAt
) {
}
