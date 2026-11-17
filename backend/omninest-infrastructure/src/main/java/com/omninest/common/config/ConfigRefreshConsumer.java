package com.omninest.common.config;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

/**
 * 配置热更新消费者。
 * 监听配置变更 fanout 交换机，清除本节点的运行时配置缓存。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ConfigRefreshConsumer {

    private final RuntimeConfigCache runtimeConfigCache;
    private final ApplicationEventPublisher applicationEventPublisher;

    /**
     * 处理配置变更事件，清除对应运行时配置缓存。
     *
     * @param event 配置变更事件
     */
    @RabbitListener(
            queues = "#{configRefreshQueue.name}",
            containerFactory = "broadcastListenerContainerFactory"
    )
    public void onConfigRefresh(ConfigRefreshEvent event) {
        try {
            String key = event.key();
            if (key == null || key.isBlank()) {
                log.warn("收到配置变更事件但 key 为空，清除全部配置缓存");
                runtimeConfigCache.evictAll();
                publishLocalEvent(event);
                return;
            }
            runtimeConfigCache.evict(key);
            publishLocalEvent(event);
            log.info("配置热更新: 已清除缓存 key={}", key);
        } catch (Throwable t) {
            log.error("配置热更新处理失败: key={}", event == null ? null : event.key(), t);
        }
    }

    private void publishLocalEvent(ConfigRefreshEvent event) {
        if (applicationEventPublisher != null) {
            applicationEventPublisher.publishEvent(event);
        }
    }
}
