package com.omninest.modules.task.service;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.IntSupplier;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 长耗时任务心跳保活。
 *
 * <p>FFmpeg 转码、全量扫描等同步执行体不会主动写 {@code sys_tasks}，超过恢复调度器
 * 的 stale 阈值后会被判定为僵尸任务并重复并发投递。调用方在长任务开始时开启心跳，
 * 由后台虚拟线程周期性刷新 {@code last_heartbeat_at}。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TaskHeartbeatRunner {

    private static final Duration DEFAULT_INTERVAL = Duration.ofSeconds(30);

    /**
     * 单次心跳租约的最长存活时间。
     *
     * <p>调用方若在网络异常等路径上漏掉 close，租约会一直刷新心跳，让恢复调度器永远
     * 看不到已经卡死的任务——这比不续期更危险。租约到期后自行停止，把主动权交回调度器。</p>
     */
    private static final Duration MAX_LEASE_LIFETIME = Duration.ofHours(6);

    private final TaskRecordService taskRecordService;

    /**
     * 启动周期心跳，只刷新心跳时间，不改写任务进度。
     *
     * @param taskId 任务 ID
     * @return 可关闭的心跳租约
     */
    public Heartbeat start(UUID taskId) {
        return heartbeatLoop(taskId, () -> taskRecordService.touchHeartbeat(taskId));
    }

    /**
     * 启动周期心跳。
     *
     * @param taskId 任务 ID
     * @param progress 心跳期间保持的任务进度
     * @return 可关闭的心跳租约
     */
    public Heartbeat start(UUID taskId, int progress) {
        return heartbeatLoop(taskId, () -> taskRecordService.updateProgress(taskId, progress));
    }

    /**
     * 启动周期心跳，进度由调用方实时提供。
     *
     * @param taskId 任务 ID
     * @param progressSupplier 进度提供器
     * @return 可关闭的心跳租约
     */
    public Heartbeat start(UUID taskId, IntSupplier progressSupplier) {
        return heartbeatLoop(taskId, () -> taskRecordService.updateProgress(taskId, progressSupplier.getAsInt()));
    }

    private Heartbeat heartbeatLoop(UUID taskId, Runnable keepAlive) {
        AtomicBoolean running = new AtomicBoolean(true);
        Instant deadline = Instant.now().plus(MAX_LEASE_LIFETIME);
        Thread thread = Thread.ofVirtual()
                .name("task-heartbeat-" + taskId)
                .start(() -> {
                    while (running.get()) {
                        try {
                            Thread.sleep(DEFAULT_INTERVAL.toMillis());
                        } catch (InterruptedException interrupted) {
                            Thread.currentThread().interrupt();
                            return;
                        }
                        if (!running.get()) {
                            return;
                        }
                        if (Instant.now().isAfter(deadline)) {
                            log.warn("任务心跳租约超过最长存活时间并自行停止，交回恢复调度器: taskId={}", taskId);
                            running.set(false);
                            return;
                        }
                        try {
                            keepAlive.run();
                        } catch (RuntimeException exception) {
                            log.debug("任务心跳刷新失败: taskId={}, errorType={}",
                                    taskId, exception.getClass().getSimpleName());
                        }
                    }
                });
        return new Heartbeat(running, thread);
    }

    /**
     * 心跳租约；关闭后不再刷新。
     */
    public static final class Heartbeat implements AutoCloseable {
        private final AtomicBoolean running;
        private final Thread thread;

        private Heartbeat(AtomicBoolean running, Thread thread) {
            this.running = running;
            this.thread = thread;
        }

        @Override
        public void close() {
            running.set(false);
            thread.interrupt();
        }
    }
}
