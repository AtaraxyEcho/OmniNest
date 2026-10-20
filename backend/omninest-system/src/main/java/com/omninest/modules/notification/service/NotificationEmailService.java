package com.omninest.modules.notification.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.common.preferences.UserPreferenceQuery;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.modules.notification.config.NotificationEmailRuntimeConfig;
import com.omninest.modules.notification.domain.NotificationMessage;
import com.omninest.modules.notification.domain.NotificationType;
import com.omninest.modules.notification.event.NotificationEmailRequestedEvent;
import com.omninest.modules.notification.repository.NotificationRepository;
import com.omninest.modules.notification.repository.NotificationTypeRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Duration;
import java.time.Instant;
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
 * {@code emailNotification}，两者任一关闭时创建通知不会留下任务行，默认部署因此
 * 零额外写入。登记前还要过每用户每小时上限：批量收尾放出的通知不能把收件箱
 * 和邮件服务商配额一起打满，超限只丢邮件、站内通知照旧。</p>
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
    private static final Duration RATE_WINDOW = Duration.ofHours(1);

    private final NotificationRepository notificationRepository;
    private final NotificationTypeRepository notificationTypeRepository;
    private final NotificationEmailRuntimeConfig runtimeConfig;
    private final NotificationEmailSender emailSender;
    private final NotificationEmailRenderer emailRenderer;
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
        if (exceedsRateLimit(recipientUserId)) {
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
        String typeLabel = typeLabel(message.getNotificationType());
        String subject = message.getTitle() == null || message.getTitle().isBlank()
                ? typeLabel
                : message.getTitle();
        var rendered = emailRenderer.render(
                subject,
                message.getTitle(),
                message.getMessage(),
                typeLabel,
                message.getCreatedAt(),
                runtimeConfig.webBaseUrl(),
                runtimeConfig.format());
        emailSender.send(recipient.get(), rendered.subject(), rendered.plainText(), rendered.html());
        taskRecordService.markCompleted(event.taskId(), Map.of("delivered", true));
        log.info("已投递通知邮件: taskId={}, type={}, rich={}",
                event.taskId(), message.getNotificationType(), rendered.html() != null);
    }

    /**
     * 管理员验证 SMTP 参数：按当前格式同步发送一封测试邮件。
     *
     * @param recipient 收件地址
     */
    public void sendTestMail(String recipient) {
        var rendered = emailRenderer.render(
                "OmniNest 邮件通道测试",
                "OmniNest 邮件通道测试",
                "这是一封测试邮件，说明通知邮件通道的 SMTP 参数可用。",
                typeLabel("SYSTEM_MESSAGE"),
                Instant.now(),
                runtimeConfig.webBaseUrl(),
                runtimeConfig.format());
        emailSender.send(recipient, rendered.subject(), rendered.plainText(), rendered.html());
    }

    private Optional<String> resolveRecipient(UUID userId) {
        return userAccountQuery.findDeliverableEmail(userId);
    }

    /**
     * 每小时上限判定：批量任务收尾会一次性放出大量通知，不设上限会把收件箱和
     * 服务商配额一起打爆；超限的通知只丢邮件，站内通知仍然保留。
     */
    private boolean exceedsRateLimit(UUID recipientUserId) {
        int limit = runtimeConfig.ratePerHour();
        if (limit <= 0) {
            return false;
        }
        long recent = taskRecordService.countRecentTasks(
                TASK_TYPE, recipientUserId, Instant.now().minus(RATE_WINDOW));
        if (recent < limit) {
            return false;
        }
        log.warn("邮件投递达到每小时上限，本次不登记: userId={}, limit={}, recent={}",
                recipientUserId, limit, recent);
        return true;
    }

    private String typeLabel(String typeCode) {
        return notificationTypeRepository.findByTypeCode(typeCode)
                .map(NotificationType::getLabel)
                .filter(label -> !label.isBlank())
                .orElse(typeCode);
    }
}
