package com.omninest.modules.sync.config;

import com.omninest.common.messaging.QueueNames;
import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 每个 API 实例独立的同步事件广播队列配置。
 *
 * @author OmniNest
 */
@Configuration
@ConditionalOnProperty(
        prefix = "omninest.runtime",
        name = "role",
        havingValue = "api",
        matchIfMissing = true
)
public class SyncRabbitTopologyConfig {

    /**
     * 创建仅属于当前 API 实例的临时同步队列。
     *
     * @return 独占自动删除队列
     */
    @Bean
    Queue syncEventInstanceQueue() {
        return QueueBuilder.nonDurable()
                .exclusive()
                .autoDelete()
                .build();
    }

    /**
     * 将当前 API 实例队列绑定到所有用户同步路由。
     *
     * @param syncEventInstanceQueue 当前实例队列
     * @param syncEventExchange 同步事件交换机
     * @return RabbitMQ 绑定
     */
    @Bean
    Binding syncEventInstanceBinding(
            @Qualifier("syncEventInstanceQueue") Queue syncEventInstanceQueue,
            @Qualifier("syncEventExchange") TopicExchange syncEventExchange
    ) {
        return BindingBuilder.bind(syncEventInstanceQueue)
                .to(syncEventExchange)
                .with(QueueNames.SYNC_EVENT_ROUTING_PATTERN);
    }
}
