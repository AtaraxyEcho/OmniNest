package com.omninest.modules.notification.service;

import com.omninest.common.api.PageClamps;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.preferences.UserPreferenceQuery;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.notification.domain.NotificationMessage;
import com.omninest.modules.notification.domain.NotificationType;
import com.omninest.modules.notification.dto.NotificationDto;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.notification.port.NotificationRealtimeQuery;
import com.omninest.modules.notification.repository.NotificationRepository;
import com.omninest.modules.notification.repository.NotificationTypeRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 站内通知服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class NotificationService implements NotificationPublisher, NotificationRealtimeQuery {

    private final NotificationRepository notificationRepository;
    private final NotificationTypeRepository notificationTypeRepository;
    private final UserPreferenceQuery userPreferenceQuery;
    private final ReadThroughCache readThroughCache;
    private final UserSyncEventRecorder syncEventRecorder;
    private final PlatformTransactionManager transactionManager;

    /**
     * 创建通知并持久化。
     *
     * <p>流程：校验类型存在且启用 → 读取用户偏好 → 入库 → 推送。
     * 若类型禁用或用户关闭该类型，返回 null。
     */
    @Transactional(rollbackFor = Exception.class)
    @Override
    public NotificationDto create(UUID recipientUserId, String type, String title,
                                  String message, Map<String, Object> metadata) {
        // 1. 校验类型是否存在且启用
        NotificationType notificationType = notificationTypeRepository.findByTypeCode(type)
                .filter(NotificationType::isEnabled)
                .orElseThrow(() -> new BusinessException(ErrorCode.BAD_REQUEST, "通知类型不存在或已禁用: " + type));

        // 2. 读取用户偏好
        if (!isTypeEnabledForUser(recipientUserId, type)) {
            log.debug("用户已关闭该通知类型: userId={}, type={}", recipientUserId, type);
            return null;
        }

        // 3. 入库
        NotificationMessage entity = new NotificationMessage();
        entity.setRecipientUserId(recipientUserId);
        entity.setNotificationType(type);
        entity.setTitle(title);
        entity.setMessage(message);
        entity.setMetadata(metadata != null ? metadata : Map.of());
        notificationRepository.save(entity);
        recordEvent(recipientUserId, entity.getId(), SyncAction.CREATED, Map.of("type", type));
        log.info("已创建通知: userId={}, type={}", recipientUserId, type);

        // 清除未读数缓存
        readThroughCache.invalidate("omninest:notification:unread:" + recipientUserId);

        return toDto(entity);
    }

    /**
     * 检查用户是否启用了指定通知类型。
     * types 中未存储的默认为 true，只有显式关闭的才为 false。
     */
    @SuppressWarnings("unchecked")
    private boolean isTypeEnabledForUser(UUID userId, String typeCode) {
        Map<String, Object> prefs = userPreferenceQuery.findValues(userId, "notification");

        // 全局开关
        Object globalEnabled = prefs.get("enabled");
        if (globalEnabled instanceof Boolean enabled && !enabled) {
            return false;
        }

        // 类型开关
        Object typesObj = prefs.get("types");
        if (typesObj instanceof Map<?, ?> types) {
            Object typeEnabled = types.get(typeCode);
            if (typeEnabled instanceof Boolean enabled) {
                return enabled;
            }
        }

        // 未配置默认启用
        return true;
    }

    /**
     * 发送通知，失败时记录警告日志但不影响主流程。
     * 用于任务完成/失败等非关键通知场景。
     */
    @Override
    public void notifyOrLog(UUID userId, String type, String title, String message, Map<String, Object> metadata) {
        try {
            TransactionTemplate transaction = new TransactionTemplate(transactionManager);
            transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
            transaction.executeWithoutResult(status -> create(userId, type, title, message, metadata));
        } catch (Exception ex) {
            log.warn("发送通知失败: userId={}, type={}, errorType={}",
                    userId, type, ex.getClass().getSimpleName());
        }
    }

    /**
     * 为提交后的多实例实时投递读取指定用户通知。
     *
     * @param userId 接收用户标识
     * @param notificationId 通知标识
     * @return 匹配的通知
     */
    @Transactional(readOnly = true)
    @Override
    public Optional<NotificationDto> findForRealtime(UUID userId, UUID notificationId) {
        return notificationRepository.findByIdAndRecipientUserId(notificationId, userId)
                .map(this::toDto);
    }

    /**
     * 分页查询用户通知。
     */
    @Transactional(readOnly = true)
    public List<NotificationDto> list(UUID userId, int page, int size) {
        return notificationRepository
                .findByRecipientUserIdOrderByCreatedAtDesc(
                        userId,
                        PageRequest.of(PageClamps.safePage(page), PageClamps.safeSize(size)))
                .stream()
                .map(this::toDto)
                .toList();
    }

    /**
     * 查询用户未读通知数量（缓存 30 秒）。
     */
    @Transactional(readOnly = true)
    public long unreadCount(UUID userId) {
        String cacheKey = "omninest:notification:unread:" + userId;
        Long cached = readThroughCache.getOrLoad(cacheKey, Duration.ofSeconds(30),
                () -> notificationRepository.countByRecipientUserIdAndReadAtIsNull(userId),
                Long.class);
        return cached != null ? cached : 0L;
    }

    /**
     * 查询用户通知总数。
     */
    @Transactional(readOnly = true)
    public long totalCount(UUID userId) {
        return notificationRepository.countByRecipientUserId(userId);
    }

    /**
     * 批量标记已读。
     */
    @Transactional(rollbackFor = Exception.class)
    public int markRead(UUID userId, Collection<UUID> notificationIds) {
        int count = notificationRepository.markRead(userId, notificationIds, Instant.now());
        log.info("已标记通知已读: userId={}, count={}", userId, count);
        readThroughCache.invalidate("omninest:notification:unread:" + userId);
        if (count > 0) {
            recordEvent(userId, null, SyncAction.UPDATED, Map.of("updatedCount", count));
        }
        return count;
    }

    /**
     * 全部标记已读。
     */
    @Transactional(rollbackFor = Exception.class)
    public int markAllRead(UUID userId) {
        int count = notificationRepository.markAllRead(userId, Instant.now());
        log.info("已全部标记已读: userId={}, count={}", userId, count);
        readThroughCache.invalidate("omninest:notification:unread:" + userId);
        if (count > 0) {
            recordEvent(userId, null, SyncAction.UPDATED, Map.of("updatedCount", count));
        }
        return count;
    }

    /**
     * 删除当前用户的指定通知。
     *
     * @param userId 用户标识
     * @param notificationId 通知标识
     * @return 删除数量
     */
    @Transactional(rollbackFor = Exception.class)
    public int delete(UUID userId, UUID notificationId) {
        int count = notificationRepository.deleteForRecipient(userId, notificationId);
        if (count > 0) {
            readThroughCache.invalidate("omninest:notification:unread:" + userId);
            recordEvent(userId, notificationId, SyncAction.DELETED, Map.of("deletedCount", count));
            log.info("已删除通知: userId={}, notificationId={}", userId, notificationId);
        }
        return count;
    }

    /**
     * 清空当前用户的全部通知。
     *
     * @param userId 用户标识
     * @return 删除数量
     */
    @Transactional(rollbackFor = Exception.class)
    public int clearAll(UUID userId) {
        int count = notificationRepository.deleteAllForRecipient(userId);
        if (count > 0) {
            readThroughCache.invalidate("omninest:notification:unread:" + userId);
            recordEvent(userId, null, SyncAction.DELETED, Map.of("deletedCount", count));
            log.info("已清空通知: userId={}, count={}", userId, count);
        }
        return count;
    }

    private NotificationDto toDto(NotificationMessage entity) {
        return new NotificationDto(
                entity.getId(),
                entity.getNotificationType(),
                entity.getTitle(),
                entity.getMessage(),
                entity.isRead(),
                entity.getCreatedAt()
        );
    }

    private void recordEvent(
            UUID recipientUserId,
            UUID notificationId,
            SyncAction action,
            Map<String, Object> hints
    ) {
        syncEventRecorder.record(new SyncEventCommand(
                recipientUserId,
                SyncScope.NOTIFICATIONS,
                "NOTIFICATION",
                notificationId == null ? null : notificationId.toString(),
                action,
                null,
                hints
        ));
    }
}
