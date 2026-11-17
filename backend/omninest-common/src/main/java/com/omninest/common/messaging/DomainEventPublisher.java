package com.omninest.common.messaging;

/**
 * 领域事件和异步任务发布端口。
 *
 * @author OmniNest
 */
public interface DomainEventPublisher {

    /**
     * 向广播交换机发布事件。
     *
     * @param exchange 交换机名称
     * @param payload 事件载荷
     */
    void publishFanout(String exchange, Object payload);

    /**
     * 向任务交换机发布任务。
     *
     * @param routingKey 路由键
     * @param payload 任务载荷
     */
    void publishTask(String routingKey, Object payload);
}
