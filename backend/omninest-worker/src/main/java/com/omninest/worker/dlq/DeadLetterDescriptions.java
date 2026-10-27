package com.omninest.worker.dlq;

import com.omninest.common.json.JsonSupport;
import java.util.List;
import java.util.Map;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import tools.jackson.databind.JsonNode;

/**
 * 死信消息摘要拼装。
 *
 * <p>独立于消费者本身，避免消费编排与文本裁剪混在一个类里把消费者撑过长度上限。</p>
 *
 * @author OmniNest
 */
@Slf4j
final class DeadLetterDescriptions {

    private DeadLetterDescriptions() {
    }

    /**
     * 从死信消息体提取堆栈摘要字段，缺失或非 JSON 时返回 null。
     */
    static String stackSummary(String body) {
        try {
            JsonNode json = JsonSupport.readTree(body);
            return json == null ? null : json.path("stackSummary").asString(null);
        } catch (RuntimeException exception) {
            log.debug("死信消息体不是 JSON，不提取堆栈摘要");
            return null;
        }
    }

    /**
     * 组装死信错误摘要。
     *
     * <p>Outbox 死信消息体携带投递失败上下文（错误码、失败类型、失败实例）
     * 与脱敏后的原始载荷，一并写入任务错误摘要；普通死信仅保留原始路由键，
     * 并补充 Broker {@code x-death} 头记录的来源队列与拒绝原因——业务消费者
     * NACK 时消息体仍是原始事件，没有错误码，缺少这层信息就无法判断死信来自
     * 哪个队列。创建载荷本身已在任务记录中，无需重复存储。</p>
     */
    static String describe(Message message, String body, String routingKey) {
        StringBuilder summary = new StringBuilder("消息进入死信队列，原始路由键: ").append(routingKey);
        appendDeathOrigin(summary, message);
        JsonNode json = null;
        try {
            json = JsonSupport.readTree(body);
        } catch (RuntimeException exception) {
            log.debug("死信消息体不是 JSON，仅记录路由键");
        }
        if (json != null && json.path("errorCode").asString(null) != null) {
            summary.append("; 投递失败: ").append(json.path("failureType").asString(null))
                    .append('/').append(json.path("errorCode").asString(null));
            String instanceId = json.path("publisherInstanceId").asString(null);
            if (instanceId != null) {
                summary.append(" @").append(instanceId);
            }
            String taskId = json.path("taskId").asString(null);
            if (taskId != null && !taskId.isBlank() && taskId.length() <= 64) {
                summary.append("; taskId: ").append(taskId);
            }
        }
        return summary.toString();
    }

    /**
     * 追加 Broker 记录的最近一次死信来源；无 {@code x-death} 头（Outbox 直投死信）时跳过。
     *
     * <p>数组头部是最近一次死亡事件，后续条目属于更早的跳转，不作为本次原因。</p>
     */
    private static void appendDeathOrigin(StringBuilder summary, Message message) {
        List<Map<String, ?>> deaths = message.getMessageProperties().getXDeathHeader();
        if (deaths == null || deaths.isEmpty()) {
            return;
        }
        Map<String, ?> latest = deaths.get(0);
        summary.append("; 来源队列: ").append(latest.get("queue"))
                .append(", 原因: ").append(latest.get("reason"));
        Object count = latest.get("count");
        if (count != null) {
            summary.append(", 次数: ").append(count);
        }
    }
}
