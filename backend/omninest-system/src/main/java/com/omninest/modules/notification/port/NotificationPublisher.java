package com.omninest.modules.notification.port;

import com.omninest.modules.notification.dto.NotificationDto;
import java.util.Map;
import java.util.UUID;

/**
 * 向业务模块暴露站内通知发布能力。
 *
 * @author OmniNest
 */
public interface NotificationPublisher {

    /**
     * 创建并持久化通知。
     *
     * @param recipientUserId 接收用户标识
     * @param type 通知类型编码
     * @param title 通知标题
     * @param message 通知正文
     * @param metadata 通知元数据
     * @return 已创建的通知，用户关闭该类型时返回 null
     */
    NotificationDto create(
            UUID recipientUserId,
            String type,
            String title,
            String message,
            Map<String, Object> metadata
    );

    /**
     * 在独立事务中发布通知，失败时不影响调用方主流程。
     *
     * @param userId 接收用户标识
     * @param type 通知类型编码
     * @param title 通知标题
     * @param message 通知正文
     * @param metadata 通知元数据
     */
    void notifyOrLog(
            UUID userId,
            String type,
            String title,
            String message,
            Map<String, Object> metadata
    );
}
