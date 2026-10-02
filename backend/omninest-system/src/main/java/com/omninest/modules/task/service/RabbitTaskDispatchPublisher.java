package com.omninest.modules.task.service;

import com.omninest.common.json.JsonSupport;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.config.TaskOutboxProperties;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import lombok.RequiredArgsConstructor;
import org.springframework.amqp.rabbit.connection.CorrelationData;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Service;

/**
 * 发布任务 Outbox 消息并等待 Broker 确认。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class RabbitTaskDispatchPublisher {
    private static final int MAX_SANITIZE_DEPTH = 8;
    private static final int MAX_COLLECTION_ITEMS = 100;
    private static final int MAX_STRING_LENGTH = 512;
    private static final String REDACTED = "[REDACTED]";
    private static final String TRUNCATED = "[TRUNCATED]";

    private final RabbitTemplate rabbitTemplate;
    private final TaskOutboxProperties properties;

    /**
     * 发布单条任务消息。
     *
     * @param dispatch 已领取记录
     */
    public void publish(ClaimedTaskDispatch dispatch) {
        Object payload;
        try {
            payload = JsonSupport.fromJson(dispatch.payload(), Object.class);
        } catch (RuntimeException exception) {
            throw failure("PAYLOAD_INVALID", false, exception);
        }
        publishAndConfirm(
                dispatch.exchangeName(),
                dispatch.routingKey(),
                payload,
                dispatch.id().toString()
        );
    }

    /**
     * 将原任务投递失败信息发布到死信交换机。
     *
     * @param dispatch 原投递快照
     * @param errorCode 原始错误码
     * @param failureType 失败类型摘要
     * @param failedAt 失败时间
     */
    public void publishDeadLetter(
            ClaimedTaskDispatch dispatch,
            String errorCode,
            String failureType,
            Instant failedAt
    ) {
        TaskDispatchDeadLetter deadLetter = new TaskDispatchDeadLetter(
                dispatch.taskId(),
                dispatch.id(),
                dispatch.exchangeName(),
                dispatch.routingKey(),
                sanitizedPayload(dispatch.payload()),
                dispatch.attemptCount() + 1,
                errorCode,
                failureType,
                properties.getInstanceId(),
                failedAt
        );
        publishAndConfirm(
                QueueNames.DEAD_LETTER_EXCHANGE,
                QueueNames.DEAD_LETTER_ROUTING_KEY,
                deadLetter,
                dispatch.id() + ":dlq"
        );
    }

    private void publishAndConfirm(
            String exchange,
            String routingKey,
            Object payload,
            String correlationId
    ) {
        CorrelationData correlationData = new CorrelationData(correlationId);
        try {
            rabbitTemplate.convertAndSend(exchange, routingKey, payload, correlationData);
        } catch (RuntimeException exception) {
            throw failure("BROKER_UNAVAILABLE", true, exception);
        }
        CorrelationData.Confirm confirm = awaitConfirm(correlationData);
        if (confirm == null || !confirm.ack()) {
            throw failure("BROKER_NACK", true, null);
        }
        if (correlationData.getReturned() != null) {
            throw failure("MESSAGE_UNROUTABLE", true, null);
        }
    }

    private CorrelationData.Confirm awaitConfirm(CorrelationData correlationData) {
        try {
            long timeout = Math.max(1L, properties.getConfirmTimeoutMillis());
            return correlationData.getFuture().get(timeout, TimeUnit.MILLISECONDS);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw failure("CONFIRM_INTERRUPTED", true, exception);
        } catch (TimeoutException exception) {
            throw failure("CONFIRM_TIMEOUT", true, exception);
        } catch (ExecutionException exception) {
            throw failure("CONFIRM_FAILED", true, exception);
        }
    }

    private Object sanitizedPayload(String payload) {
        try {
            return sanitize(JsonSupport.fromJson(payload, Object.class), 0);
        } catch (RuntimeException exception) {
            return Map.of("invalidPayload", true, "payloadLength", payload == null ? 0 : payload.length());
        }
    }

    private Object sanitize(Object value, int depth) {
        if (value == null) {
            return null;
        }
        if (depth >= MAX_SANITIZE_DEPTH) {
            return TRUNCATED;
        }
        if (value instanceof Map<?, ?> map) {
            Map<String, Object> sanitized = new LinkedHashMap<>();
            int count = 0;
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                if (count++ >= MAX_COLLECTION_ITEMS) {
                    sanitized.put("truncated", true);
                    break;
                }
                String key = String.valueOf(entry.getKey());
                sanitized.put(key, isSensitiveKey(key) ? REDACTED : sanitize(entry.getValue(), depth + 1));
            }
            return sanitized;
        }
        if (value instanceof Collection<?> collection) {
            List<Object> sanitized = new ArrayList<>();
            int count = 0;
            for (Object item : collection) {
                if (count++ >= MAX_COLLECTION_ITEMS) {
                    sanitized.add(TRUNCATED);
                    break;
                }
                sanitized.add(sanitize(item, depth + 1));
            }
            return sanitized;
        }
        if (value instanceof String text && text.length() > MAX_STRING_LENGTH) {
            return text.substring(0, MAX_STRING_LENGTH) + TRUNCATED;
        }
        return value;
    }

    private boolean isSensitiveKey(String key) {
        String normalized = key.toLowerCase(Locale.ROOT).replace("-", "").replace("_", "");
        return normalized.contains("password")
                || normalized.contains("secret")
                || normalized.contains("token")
                || normalized.contains("credential")
                || normalized.contains("authorization")
                || normalized.contains("accesskey")
                || normalized.contains("privatekey")
                || normalized.endsWith("url")
                || normalized.endsWith("uri")
                || normalized.endsWith("path");
    }

    private TaskDispatchPublishException failure(
            String errorCode,
            boolean retryable,
            Throwable cause
    ) {
        String failureType = cause == null ? errorCode : cause.getClass().getSimpleName();
        return new TaskDispatchPublishException(
                errorCode,
                retryable,
                failureType,
                "RabbitMQ 任务消息发布失败: " + errorCode,
                cause
        );
    }
}
