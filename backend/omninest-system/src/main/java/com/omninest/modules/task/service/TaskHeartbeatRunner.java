package com.omninest.modules.task.service;

import java.time.Duration;
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

    private final TaskRecordService taskRecordService;

    /**
     * 启动周期心跳。
     *
     * @param taskId 任务 ID
     * @param progress 心跳期间保持的任务进度
     * @return 可关闭的心跳租约
     */
    public Heartbeat start(UUID taskId, int progress) {
        return start(taskId, () -> progress);
    }

    /**
     * 启动周期心跳，进度由调用方实时提供。
     *
     * @param taskId 任务 ID
     * @param progressSupplier 进度提供器
     * @return 可关闭的心跳租约
     */
    public Heartbeat start(UUID taskId, IntSupplier progressSupplier) {
        AtomicBoolean running = new AtomicBoolean(true);
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
                        try {
                            taskRecordService.updateProgress(taskId, progressSupplier.getAsInt());
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
