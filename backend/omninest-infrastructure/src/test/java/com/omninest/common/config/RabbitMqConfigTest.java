package com.omninest.common.config;

import com.omninest.common.messaging.QueueNames;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.time.Duration;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.support.converter.MessageConversionException;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * RabbitMQ 消息容量、过期时间和兼容队列声明测试。
 *
 * @author OmniNest
 */
class RabbitMqConfigTest {
    private final RabbitMessagingProperties properties = new RabbitMessagingProperties();
    private final RabbitMqConfig config = new RabbitMqConfig(properties);

    @BeforeEach
    void setUp() {
        properties.setMaximumMessageBytes(128);
        properties.setMessageTtl(Duration.ofMinutes(5));
        properties.setConsumerPrefetch(10);
    }

    @Test
    void messageConverterAppliesSizeMetadataAndExpiration() {
        MessageConverter converter = config.rabbitMessageConverter();
        MessageProperties messageProperties = new MessageProperties();

        Message message = converter.toMessage(Map.of("taskId", "task-1"), messageProperties);

        Assertions.assertThat(message.getBody()).isNotEmpty();
        Assertions.assertThat(message.getMessageProperties().getContentLength())
                .isEqualTo(message.getBody().length);
        Assertions.assertThat(message.getMessageProperties().getExpiration()).isEqualTo("300000");
    }

    @Test
    void taskListenerFactoriesRejectWithoutRequeueWhileBroadcastKeepsDefault() {
        ConnectionFactory connectionFactory = Mockito.mock(ConnectionFactory.class);
        MessageConverter converter = config.rabbitMessageConverter();

        // MANUAL 确认的任务队列：监听异常直接进死信，杜绝毒消息无限 requeue。
        Assertions.assertThat(ReflectionTestUtils.getField(
                        config.rabbitListenerContainerFactory(connectionFactory, converter),
                        "defaultRequeueRejected"))
                .isEqualTo(Boolean.FALSE);
        Assertions.assertThat(ReflectionTestUtils.getField(
                        config.transcodeListenerContainerFactory(connectionFactory, converter),
                        "defaultRequeueRejected"))
                .isEqualTo(Boolean.FALSE);
        Assertions.assertThat(ReflectionTestUtils.getField(
                        config.localMediaTaskListenerContainerFactory(connectionFactory, converter),
                        "defaultRequeueRejected"))
                .isEqualTo(Boolean.FALSE);
        // 广播队列自动确认，保持容器默认行为。
        Assertions.assertThat(ReflectionTestUtils.getField(
                        config.broadcastListenerContainerFactory(connectionFactory, converter),
                        "defaultRequeueRejected"))
                .isNull();
    }

    @Test
    void messageConverterRejectsOversizedOutgoingAndIncomingBodies() {
        MessageConverter converter = config.rabbitMessageConverter();

        Assertions.assertThatThrownBy(() -> converter.toMessage(
                Map.of("payload", "x".repeat(256)),
                new MessageProperties()
        )).isInstanceOf(MessageConversionException.class)
                .hasMessageContaining("消息体超过容量限制");

        Message oversized = new Message(new byte[129], new MessageProperties());
        Assertions.assertThatThrownBy(() -> converter.fromMessage(oversized))
                .isInstanceOf(MessageConversionException.class)
                .hasMessageContaining("消息体超过容量限制");
    }

    @Test
    void durableQueueKeepsExistingDeadLetterArgumentsWithoutNewDeclarationLimits() {
        Queue queue = config.textExtractionQueue();

        Assertions.assertThat(queue.getName()).isEqualTo(QueueNames.TEXT_EXTRACTION_QUEUE);
        Assertions.assertThat(queue.getArguments())
                .containsEntry("x-dead-letter-exchange", QueueNames.DEAD_LETTER_EXCHANGE)
                .containsEntry("x-dead-letter-routing-key", QueueNames.DEAD_LETTER_ROUTING_KEY)
                .doesNotContainKeys("x-max-length", "x-max-length-bytes", "x-message-ttl");
    }

    @Test
    void configRefreshQueueUsesSupportedTransientQueueArguments() {
        Queue queue = config.configRefreshQueue();

        Assertions.assertThat(queue.isDurable()).isFalse();
        Assertions.assertThat(queue.isExclusive()).isTrue();
        Assertions.assertThat(queue.isAutoDelete()).isTrue();
        Assertions.assertThat(queue.getArguments()).doesNotContainKey("x-queue-master-locator");
    }

    /**
     * 架构棘轮：QueueNames 里每个任务队列常量都必须有对应的 Queue bean。
     *
     * <p>漏声明 bean 时 Broker 上不会建队列，消息进交换机后直接丢弃，
     * 而且只有跑到那条链路才暴露。新增队列必须同时补 bean 与 Binding。</p>
     */
    @Test
    void everyTaskQueueConstantIsDeclaredAsQueueBean() throws Exception {
        Set<String> constants = new LinkedHashSet<>();
        for (Field field : QueueNames.class.getFields()) {
            if (field.getName().endsWith("_QUEUE") && field.getType() == String.class) {
                String value = (String) field.get(null);
                if (value.startsWith("omni.task.")) {
                    constants.add(value);
                }
            }
        }

        Set<String> declared = new LinkedHashSet<>();
        for (Method method : RabbitMqConfig.class.getDeclaredMethods()) {
            if (method.getReturnType() == Queue.class && method.getParameterCount() == 0) {
                declared.add(((Queue) method.invoke(config)).getName());
            }
        }

        Assertions.assertThat(declared)
                .as("任务队列常量必须逐个声明为 durableQueue bean")
                .containsAll(constants);
    }
}
