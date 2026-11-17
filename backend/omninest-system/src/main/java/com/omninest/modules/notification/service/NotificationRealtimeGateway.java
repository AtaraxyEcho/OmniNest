package com.omninest.modules.notification.service;

import com.omninest.modules.notification.dto.NotificationDto;
import java.util.UUID;

/**
 * 定义通知持久化完成后的实时投递边界。
 *
 * @author OmniNest
 */
public interface NotificationRealtimeGateway {

    /**
     * 将通知投递给当前 API 实例上连接的目标用户。
     *
     * @param recipientUserId 接收用户 ID
     * @param notification 通知内容
     */
    void send(UUID recipientUserId, NotificationDto notification);
}
