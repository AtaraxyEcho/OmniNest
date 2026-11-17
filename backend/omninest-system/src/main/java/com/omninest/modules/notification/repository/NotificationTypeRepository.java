package com.omninest.modules.notification.repository;

import com.omninest.modules.notification.domain.NotificationType;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 通知类型仓储接口。
 */
public interface NotificationTypeRepository extends JpaRepository<NotificationType, UUID> {

    /**
     * 查询所有启用的通知类型，按排序权重升序。
     */
    List<NotificationType> findByEnabledTrueOrderBySortOrderAsc();

    /**
     * 根据类型标识码查询。
     */
    Optional<NotificationType> findByTypeCode(String typeCode);
}
