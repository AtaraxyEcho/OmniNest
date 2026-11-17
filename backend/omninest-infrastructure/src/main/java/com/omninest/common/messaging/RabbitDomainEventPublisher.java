package com.omninest.common.messaging;

import lombok.RequiredArgsConstructor;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Component;

/**
 * 使用 RabbitMQ 实现领域事件和异步任务发布端口。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class RabbitDomainEventPublisher implements DomainEventPublisher {
    private final RabbitTemplate rabbitTemplate;

    /**
     * 向指定广播交换机发布事件。
     *
     * @param exchange 交换机名称
     * @param payload 事件载荷
     */
    @Override
    public void publishFanout(String exchange, Object payload) {
        rabbitTemplate.convertAndSend(exchange, "", payload);
    }

    /**
     * 向任务交换机发布任务。
     *
     * @param routingKey 路由键
     * @param payload 任务载荷
     */
    @Override
    public void publishTask(String routingKey, Object payload) {
        rabbitTemplate.convertAndSend(QueueNames.TASK_EXCHANGE, routingKey, payload);
    }
}
