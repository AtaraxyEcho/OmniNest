package com.omninest.modules.notification.repository;

import com.omninest.modules.notification.domain.NotificationMessage;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 站内通知仓储接口。
 */
public interface NotificationRepository extends JpaRepository<NotificationMessage, UUID> {

    /**
     * 分页查询用户通知，按创建时间倒序。
     */
    List<NotificationMessage> findByRecipientUserIdOrderByCreatedAtDesc(UUID recipientUserId, Pageable pageable);

    /**
     * 分页查询用户未读通知，按创建时间倒序。
     */
    List<NotificationMessage> findByRecipientUserIdAndReadAtIsNullOrderByCreatedAtDesc(
            UUID recipientUserId,
            Pageable pageable
    );

    /**
     * 按接收用户读取指定通知。
     *
     * @param id 通知标识
     * @param recipientUserId 接收用户标识
     * @return 匹配的通知
     */
    Optional<NotificationMessage> findByIdAndRecipientUserId(UUID id, UUID recipientUserId);

    /**
     * 统计用户未读通知数量。
     */
    long countByRecipientUserIdAndReadAtIsNull(UUID recipientUserId);

    /**
     * 统计用户通知总数。
     */
    long countByRecipientUserId(UUID recipientUserId);

    /**
     * 批量标记已读。
     */
    @Modifying
    @Query("UPDATE NotificationMessage n SET n.readAt = :now "
            + "WHERE n.recipientUserId = :userId AND n.id IN :ids AND n.readAt IS NULL")
    int markRead(
            @Param("userId") UUID userId,
            @Param("ids") Collection<UUID> ids,
            @Param("now") Instant now
    );

    /**
     * 全部标记已读。
     */
    @Modifying
    @Query("UPDATE NotificationMessage n SET n.readAt = :now WHERE n.recipientUserId = :userId AND n.readAt IS NULL")
    int markAllRead(@Param("userId") UUID userId, @Param("now") Instant now);

    /**
     * 删除用户的指定通知。
     *
     * @param userId 用户标识
     * @param notificationId 通知标识
     * @return 删除数量
     */
    @Modifying
    @Query("DELETE FROM NotificationMessage n WHERE n.recipientUserId = :userId AND n.id = :notificationId")
    int deleteForRecipient(
            @Param("userId") UUID userId,
            @Param("notificationId") UUID notificationId
    );

    /**
     * 清空用户的全部通知。
     *
     * @param userId 用户标识
     * @return 删除数量
     */
    @Modifying
    @Query("DELETE FROM NotificationMessage n WHERE n.recipientUserId = :userId")
    int deleteAllForRecipient(@Param("userId") UUID userId);
}
