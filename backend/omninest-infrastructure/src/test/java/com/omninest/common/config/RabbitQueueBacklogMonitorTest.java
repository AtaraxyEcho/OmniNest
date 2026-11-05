package com.omninest.common.config;

import com.omninest.common.messaging.QueueNames;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.Properties;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.amqp.core.AmqpAdmin;
import org.springframework.amqp.rabbit.core.RabbitAdmin;

/**
 * RabbitMQ 持久队列深度指标与采样容错测试。
 *
 * @author OmniNest
 */
class RabbitQueueBacklogMonitorTest {

    @Test
    void inspectPublishesQueueDepthMetrics() {
        AmqpAdmin amqpAdmin = Mockito.mock(AmqpAdmin.class);
        RabbitMessagingProperties properties = new RabbitMessagingProperties();
        properties.setBacklogWarningMessages(10);
        properties.setBacklogCriticalMessages(20);
        SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
        RabbitQueueBacklogMonitor monitor = new RabbitQueueBacklogMonitor(
                amqpAdmin,
                meterRegistry,
                properties
        );
        monitor.registerMetrics();
        Mockito.when(amqpAdmin.getQueueProperties(Mockito.anyString()))
                .thenAnswer(invocation -> queueProperties(
                        QueueNames.TEXT_EXTRACTION_QUEUE.equals(invocation.getArgument(0)) ? 12 : 0
                ));

        monitor.inspect();

        double queueDepth = meterRegistry.get("omninest.rabbitmq.queue.messages")
                .tag("queue", QueueNames.TEXT_EXTRACTION_QUEUE)
                .gauge()
                .value();
        Assertions.assertThat(queueDepth).isEqualTo(12.0);
        Mockito.verify(amqpAdmin, Mockito.times(QueueNames.durableQueues().size()))
                .getQueueProperties(Mockito.anyString());
    }

    @Test
    void inspectSkipsBrokerCallsWhenMonitoringDisabled() {
        AmqpAdmin amqpAdmin = Mockito.mock(AmqpAdmin.class);
        RabbitMessagingProperties properties = new RabbitMessagingProperties();
        properties.setBacklogMonitoringEnabled(false);
        RabbitQueueBacklogMonitor monitor = new RabbitQueueBacklogMonitor(
                amqpAdmin,
                new SimpleMeterRegistry(),
                properties
        );

        monitor.inspect();

        Mockito.verifyNoInteractions(amqpAdmin);
    }

    @Test
    void inspectMarksFailedQueueSampleWithoutStoppingRemainingQueues() {
        AmqpAdmin amqpAdmin = Mockito.mock(AmqpAdmin.class);
        RabbitMessagingProperties properties = new RabbitMessagingProperties();
        SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
        RabbitQueueBacklogMonitor monitor = new RabbitQueueBacklogMonitor(
                amqpAdmin,
                meterRegistry,
                properties
        );
        monitor.registerMetrics();
        Mockito.when(amqpAdmin.getQueueProperties(QueueNames.TEXT_EXTRACTION_QUEUE))
                .thenThrow(new IllegalStateException("broker unavailable"));
        Mockito.when(amqpAdmin.getQueueProperties(Mockito.argThat(
                queue -> !QueueNames.TEXT_EXTRACTION_QUEUE.equals(queue)
        ))).thenReturn(queueProperties(1));

        monitor.inspect();

        double failedDepth = meterRegistry.get("omninest.rabbitmq.queue.messages")
                .tag("queue", QueueNames.TEXT_EXTRACTION_QUEUE)
                .gauge()
                .value();
        double nextDepth = meterRegistry.get("omninest.rabbitmq.queue.messages")
                .tag("queue", QueueNames.THUMBNAIL_QUEUE)
                .gauge()
                .value();
        Assertions.assertThat(failedDepth).isEqualTo(-1.0);
        Assertions.assertThat(nextDepth).isEqualTo(1.0);
    }

    private Properties queueProperties(long messageCount) {
        Properties properties = new Properties();
        properties.put(RabbitAdmin.QUEUE_MESSAGE_COUNT, messageCount);
        return properties;
    }
}
