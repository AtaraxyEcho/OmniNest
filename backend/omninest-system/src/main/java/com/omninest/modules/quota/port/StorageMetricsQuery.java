package com.omninest.modules.quota.port;

import java.util.Collection;
import java.util.Map;
import java.util.UUID;

/**
 * 存储指标查询端口。
 *
 * @author OmniNest
 */
public interface StorageMetricsQuery {

    /**
     * 查询系统级存储指标。
     *
     * @return 系统级存储指标快照
     */
    StorageMetricsSnapshot systemMetrics();

    /**
     * 查询指定用户的实际存储用量。
     *
     * @param userIds 用户标识集合
     * @return 以用户标识为键的实际存储字节数
     */
    Map<UUID, Long> actualUsageByUsers(Collection<UUID> userIds);
}
