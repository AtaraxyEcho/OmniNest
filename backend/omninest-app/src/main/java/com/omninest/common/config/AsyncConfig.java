package com.omninest.common.config;

import java.util.concurrent.Executor;
import java.util.concurrent.ThreadPoolExecutor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

@Configuration
public class AsyncConfig {

    /**
     * 在线音乐第三方读取专用线程池：与 Tomcat 请求线程隔离，容量有界；饱和时回退到调用
     * 线程执行，避免外部平台抖动把请求无限堆积。
     */
    @Bean("musicOnlineExecutor")
    public Executor musicOnlineExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(8);
        executor.setMaxPoolSize(32);
        executor.setQueueCapacity(200);
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.setThreadNamePrefix("music-online-");
        executor.initialize();
        return executor;
    }

    @Bean("mediaAsyncExecutor")
    public Executor mediaAsyncExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(4);
        executor.setMaxPoolSize(8);
        executor.setQueueCapacity(64);
        executor.setThreadNamePrefix("media-async-");
        executor.initialize();
        return executor;
    }
}
