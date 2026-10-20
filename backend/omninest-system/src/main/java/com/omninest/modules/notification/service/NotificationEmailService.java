package com.omninest.modules.notification.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.common.preferences.UserPreferenceQuery;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig;
import com.omninest.modules.notification.domain.NotificationMessage;
import com.omninest.modules.notification.event.NotificationEmailRequestedEvent;
import com.omninest.modules.notification.repository.NotificationRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 通知邮件通道服务：入队投递任务并执行实际发送。
 *
 * <p>通道开关与 SMTP 参数来自配置中心，用户是否收邮件来自其站内通知偏好
 * {@code emailNotification}。两者任一关闭时创建通知不会留下任务行，
 * 默认部署因此零额外写入。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class NotificationEmailService {

    /** 任务类型编码，用于任务列表与重新投递识别。 */
    public static final String TASK_TYPE = "NOTIFICATION_EMAIL";

    private static final String RESOURCE_TYPE = "NOTIFICATION";
    private static final String PHASE = "EMAILING";
    private static final String PREFERENCE_SCOPE = "notification";
    private static final String EMAIL_PREFERENCE_KEY = "emailNotification";
    private static final DateTimeFormatter TIMESTAMP_FORMAT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault());

    private final NotificationRepository notificationRepository;
    private final NotificationEmailRuntimeConfig runtimeConfig;
    private final NotificationEmailSender emailSender;
    private final UserPreferenceQuery userPreferenceQuery;
    private final UserAccountQuery userAccountQuery;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;

    /**
     * 判断该用户此刻是否需要邮件投递：通道可用且偏好显式开启。
     *
     * @param userId 收件用户标识
     * @return 需要投递时返回 true
     */
    public boolean shouldDeliver(UUID userId) {
        if (!runtimeConfig.configured()) {
            return false;
        }
        Object value = userPreferenceQuery.findValues(userId, PREFERENCE_SCOPE).get(EMAIL_PREFERENCE_KEY);
        return value instanceof Boolean enabled && enabled;
    }

    /**
     * 为一条已入库的站内通知登记邮件投递任务。
     *
     * <p>与通知创建同事务写入任务行与 outbox 记录，消息由 outbox 派发器在提交后投递。</p>
     *
     * @param recipientUserId 收件用户标识
     * @param notificationId 通知标识
     * @return 任务标识，未登记时返回空
     */
    @Transactional(rollbackFor = Exception.class)
    public Optional<UUID> enqueueDelivery(UUID recipientUserId, UUID notificationId) {
        if (!shouldDeliver(recipientUserId)) {
            return Optional.empty();
        }
        UUID taskId = UUID.randomUUID();
        Map<String, Object> payload = Map.of(
                "taskId", taskId.toString(),
                "ownerUserId", recipientUserId.toString(),
                "notificationId", notificationId.toString()
        );
        taskRecordService.createQueuedTask(
                taskId,
                recipientUserId,
                TASK_TYPE,
                QueueNames.NOTIFICATION_EMAIL_ROUTING_KEY,
                PHASE,
                RESOURCE_TYPE,
                notificationId,
                payload
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.NOTIFICATION_EMAIL_ROUTING_KEY,
                new NotificationEmailRequestedEvent(taskId, recipientUserId, notificationId)
        );
        return Optional.of(taskId);
    }

    /**
     * 执行一次邮件投递。
     *
     * <p>重复投递、通知已删除、账户停用或无邮箱都按取消处理而非失败重试：
     * 这些原因不会随重试消失，留在队列里只会反复撞同一堵墙。</p>
     *
     * @param event 投递任务消息
     */
    public void deliver(NotificationEmailRequestedEvent event) {
        if (!taskRecordService.claimForExecution(event.taskId(), PHASE)) {
            log.info("邮件投递任务已被其他消费者领取，跳过: taskId={}", event.taskId());
            return;
        }
        Optional<NotificationMessage> notification =
                notificationRepository.findByIdAndRecipientUserId(event.notificationId(), event.ownerUserId());
        if (notification.isEmpty()) {
            taskRecordService.markCancelled(event.taskId());
            log.info("站内通知已删除，取消邮件投递: taskId={}", event.taskId());
            return;
        }
        Optional<String> recipient = resolveRecipient(event.ownerUserId());
        if (recipient.isEmpty()) {
            taskRecordService.markCancelled(event.taskId());
            log.info("收件账户不可发邮件，取消投递: taskId={}", event.taskId());
            return;
        }
        NotificationMessage message = notification.get();
        emailSender.send(recipient.get(), subjectOf(message), bodyOf(message));
        taskRecordService.markCompleted(event.taskId(), Map.of("delivered", true));
        log.info("已投递通知邮件: taskId={}, type={}", event.taskId(), message.getNotificationType());
    }

    /**
     * 管理员验证 SMTP 参数：同步发送一封测试邮件。
     *
     * @param recipient 收件地址
     */
    public void sendTestMail(String recipient) {
        emailSender.send(recipient, "OmniNest 邮件通道测试",
                "这是一封测试邮件，说明通知邮件通道的 SMTP 参数可用。");
    }

    private Optional<String> resolveRecipient(UUID userId) {
        return userAccountQuery.findDeliverableEmail(userId);
    }

    private String subjectOf(NotificationMessage message) {
        String title = message.getTitle();
        return title == null || title.isBlank() ? message.getNotificationType() : title;
    }

    private String bodyOf(NotificationMessage message) {
        String body = message.getMessage() == null ? "" : message.getMessage();
        return body + System.lineSeparator() + System.lineSeparator()
                + "通知类型：" + message.getNotificationType() + System.lineSeparator()
                + "创建时间：" + TIMESTAMP_FORMAT.format(message.getCreatedAt()) + System.lineSeparator()
                + System.lineSeparator()
                + "由 OmniNest 通知邮件通道发送。";
    }
}
