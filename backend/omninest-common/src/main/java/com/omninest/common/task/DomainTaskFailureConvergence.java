package com.omninest.common.task;

import java.util.UUID;

/**
 * 系统任务进入死信终态时，把对应领域任务表收敛为失败终态的端口。
 *
 * <p>异步任务的状态分散在两层：{@code sys_tasks} 记录调度视角的状态，各业务表
 * （{@code photo_scan_jobs}、{@code music_scan_jobs}、{@code storage_import_tasks} 等）
 * 记录前端轮询的业务状态。恢复调度器只能裁决前者，裁决为死信后若不同步收敛后者，
 * 领域行会永久停在 {@code RUNNING}/{@code SCANNING}，用户看到的进度条永远转圈，
 * 绑定在领域行上的配额预占也一直不释放。</p>
 *
 * <p>实现方按任务类型注册，由 Worker 侧统一分发；实现必须幂等——同一条任务可能被
 * 多个入口重复收敛（死信消费者、心跳恢复、重试耗尽）。</p>
 *
 * @author OmniNest
 */
public interface DomainTaskFailureConvergence {

    /**
     * 是否处理该任务类型。
     *
     * @param taskType 系统任务类型
     * @return 支持时返回 true
     */
    boolean supports(String taskType);

    /**
     * 把领域任务行收敛为失败终态，并完成与终态绑定的资源结算。
     *
     * @param taskId 系统任务 ID
     * @param reason 失败原因摘要
     */
    void converge(UUID taskId, String reason);
}
