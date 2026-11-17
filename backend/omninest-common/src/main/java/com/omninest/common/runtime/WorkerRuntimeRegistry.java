package com.omninest.common.runtime;

import java.time.Duration;
import java.util.List;

/**
 * 提供 Worker 运行状态的跨进程发布与查询能力。
 *
 * @author OmniNest
 */
public interface WorkerRuntimeRegistry {

    /**
     * 发布 Worker 状态并设置自动过期时间。
     *
     * @param state Worker 状态
     * @param ttl 状态有效期
     */
    void publish(WorkerRuntimeState state, Duration ttl);

    /**
     * 查询仍在有效期内的 Worker 状态，按上报时间从新到旧排列。
     *
     * @return 活动 Worker 状态列表，读取失败时返回空列表
     */
    List<WorkerRuntimeState> activeInstances();
}
