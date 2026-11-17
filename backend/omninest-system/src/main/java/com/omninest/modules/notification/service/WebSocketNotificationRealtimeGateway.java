package com.omninest.modules.notification.service;

import com.omninest.modules.notification.dto.NotificationDto;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Component;

/**
 * 使用本地 STOMP broker 投递通知的 API 角色实现。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(
        prefix = "omninest.runtime",
        name = "role",
        havingValue = "api",
        matchIfMissing = true
)
public class WebSocketNotificationRealtimeGateway implements NotificationRealtimeGateway {

    private final SimpMessagingTemplate messagingTemplate;

    @Override
    public void send(UUID recipientUserId, NotificationDto notification) {
        messagingTemplate.convertAndSendToUser(
                recipientUserId.toString(),
                "/queue/notifications",
                notification
        );
    }
}
