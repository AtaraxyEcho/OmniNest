package com.omninest.common.config;

import java.util.concurrent.Executor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.task.SimpleAsyncTaskExecutor;

/**
 * 异步执行器配置：按任务创建虚拟线程，并用并发上限保护外部依赖与本地子进程。
 *
 * <p>不再使用固定平台线程池：外部 HTTP I/O 会长期占住线程，饱和后 CallerRuns 又会
 * 把阻塞传导回请求线程。虚拟线程按任务创建，真正的资源闸门放在各服务的 Semaphore
 * （数据库连接、ffmpeg/ffprobe、图像解码）上。</p>
 *
 * @author OmniNest
 */
@Configuration
public class AsyncConfig {

    /**
     * 在线音乐第三方读取专用执行器：虚拟线程 + 并发上限 64。
     */
    @Bean("musicOnlineExecutor")
    public Executor musicOnlineExecutor() {
        SimpleAsyncTaskExecutor executor = new SimpleAsyncTaskExecutor("music-online-");
        executor.setVirtualThreads(true);
        executor.setConcurrencyLimit(64);
        return executor;
    }

    /**
     * 媒体异步任务执行器：虚拟线程 + 并发上限 16。
     *
     * <p>本地 ffprobe/ffmpeg 子进程数由 {@code VideoProbeService} 内的信号量独立限流，
     * 剧照远程下载不会因为长篇字幕提取而饥饿。</p>
     */
    @Bean("mediaAsyncExecutor")
    public Executor mediaAsyncExecutor() {
        SimpleAsyncTaskExecutor executor = new SimpleAsyncTaskExecutor("media-async-");
        executor.setVirtualThreads(true);
        executor.setConcurrencyLimit(16);
        return executor;
    }
}
