package com.omninest.modules.notification.port;

import com.omninest.modules.notification.dto.NotificationDto;
import java.util.Optional;
import java.util.UUID;

/**
 * 向实时同步模块暴露通知读取能力。
 *
 * @author OmniNest
 */
public interface NotificationRealtimeQuery {

    /**
     * 查询指定用户可实时投递的通知。
     *
     * @param userId 接收用户标识
     * @param notificationId 通知标识
     * @return 匹配的通知
     */
    Optional<NotificationDto> findForRealtime(UUID userId, UUID notificationId);
}
