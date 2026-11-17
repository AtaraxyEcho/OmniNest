package com.omninest.modules.notification.service;

import com.omninest.modules.notification.dto.NotificationDto;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.stereotype.Component;

/**
 * 非 API 角色使用的通知实时投递空实现。
 *
 * <p>通知仍会持久化，跨进程实时投递由后续 RabbitMQ 通知桥接负责。
 *
 * @author OmniNest
 */
@Component
@ConditionalOnExpression("'${omninest.runtime.role:api}' != 'api'")
public class NonApiNotificationRealtimeGateway implements NotificationRealtimeGateway {

    @Override
    public void send(UUID recipientUserId, NotificationDto notification) {
        // 非 API 角色不持有客户端连接。
    }
}
