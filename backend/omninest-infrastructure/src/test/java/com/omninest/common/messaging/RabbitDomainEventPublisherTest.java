package com.omninest.common.messaging;

import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

/**
 * 验证 RabbitMQ 事件发布适配器的路由行为。
 *
 * @author OmniNest
 */
class RabbitDomainEventPublisherTest {

    @Test
    void publishFanoutUsesEmptyRoutingKey() {
        RabbitTemplate rabbitTemplate = mock(RabbitTemplate.class);
        RabbitDomainEventPublisher publisher = new RabbitDomainEventPublisher(rabbitTemplate);
        Object payload = new Object();

        publisher.publishFanout("omni.config", payload);

        verify(rabbitTemplate).convertAndSend("omni.config", "", payload);
    }

    @Test
    void publishTaskUsesTaskExchange() {
        RabbitTemplate rabbitTemplate = mock(RabbitTemplate.class);
        RabbitDomainEventPublisher publisher = new RabbitDomainEventPublisher(rabbitTemplate);
        Object payload = new Object();

        publisher.publishTask("file.index", payload);

        verify(rabbitTemplate).convertAndSend(QueueNames.TASK_EXCHANGE, "file.index", payload);
    }
}
