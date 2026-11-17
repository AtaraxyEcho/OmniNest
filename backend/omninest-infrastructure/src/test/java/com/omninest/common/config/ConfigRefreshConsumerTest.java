package com.omninest.common.config;

import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;

/**
 * 配置热更新消费者单元测试，验证缓存失效范围。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ConfigRefreshConsumerTest {

    @Mock
    private RuntimeConfigCache runtimeConfigCache;

    @Mock
    private ApplicationEventPublisher applicationEventPublisher;

    @InjectMocks
    private ConfigRefreshConsumer consumer;

    @Test
    void onConfigRefreshEvictsChangedKey() {
        ConfigRefreshEvent event = new ConfigRefreshEvent(UUID.randomUUID(), "music.quality", Instant.now());

        consumer.onConfigRefresh(event);

        Mockito.verify(runtimeConfigCache).evict("music.quality");
        Mockito.verify(runtimeConfigCache, Mockito.never()).evictAll();
        Mockito.verify(applicationEventPublisher).publishEvent(event);
    }

    @Test
    void onConfigRefreshEvictsAllWhenKeyIsBlank() {
        ConfigRefreshEvent event = new ConfigRefreshEvent(UUID.randomUUID(), " ", Instant.now());

        consumer.onConfigRefresh(event);

        Mockito.verify(runtimeConfigCache).evictAll();
        Mockito.verify(runtimeConfigCache, Mockito.never()).evict(Mockito.anyString());
        Mockito.verify(applicationEventPublisher).publishEvent(event);
    }
}
