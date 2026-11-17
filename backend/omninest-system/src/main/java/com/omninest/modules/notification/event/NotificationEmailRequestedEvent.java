package com.omninest.modules.notification.event;

import java.util.UUID;

/**
 * 通知邮件投递任务消息。
 *
 * <p>载荷只携带定位信息：收件地址与正文在执行时按最新账户和通知行读取，
 * 避免把邮箱等账户数据冗余进任务载荷与投递记录。
 *
 * @param taskId 任务标识
 * @param ownerUserId 收件用户标识
 * @param notificationId 站内通知标识
 * @author OmniNest
 */
public record NotificationEmailRequestedEvent(
        UUID taskId,
        UUID ownerUserId,
        UUID notificationId
) {
}
