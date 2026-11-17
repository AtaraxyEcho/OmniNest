package com.omninest.modules.sync.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.Queue;

/**
 * 同步事件实例队列的 RabbitMQ 兼容性测试。
 *
 * @author OmniNest
 */
class SyncRabbitTopologyConfigTest {

    private final SyncRabbitTopologyConfig config = new SyncRabbitTopologyConfig();

    @Test
    void syncEventQueueUsesSupportedTransientQueueArguments() {
        Queue queue = config.syncEventInstanceQueue();

        assertThat(queue.isDurable()).isFalse();
        assertThat(queue.isExclusive()).isTrue();
        assertThat(queue.isAutoDelete()).isTrue();
        assertThat(queue.getArguments()).doesNotContainKey("x-queue-master-locator");
    }
}
