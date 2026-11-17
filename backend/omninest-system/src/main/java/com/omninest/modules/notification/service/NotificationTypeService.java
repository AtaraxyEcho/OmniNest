package com.omninest.modules.notification.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.notification.domain.NotificationType;
import com.omninest.modules.notification.dto.NotificationTypeDto;
import com.omninest.modules.notification.repository.NotificationTypeRepository;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 通知类型查询与配置服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class NotificationTypeService {

    private final NotificationTypeRepository notificationTypeRepository;

    /**
     * 查询启用的通知类型。
     *
     * @return 已启用类型列表
     */
    @Transactional(readOnly = true)
    public List<NotificationTypeDto> listEnabled() {
        return notificationTypeRepository.findByEnabledTrueOrderBySortOrderAsc()
                .stream()
                .map(NotificationTypeDto::from)
                .toList();
    }

    /**
     * 查询全部通知类型。
     *
     * @return 全部类型列表
     */
    @Transactional(readOnly = true)
    public List<NotificationTypeDto> listAll() {
        return notificationTypeRepository.findAll()
                .stream()
                .map(NotificationTypeDto::from)
                .toList();
    }

    /**
     * 更新通知类型配置。
     *
     * @param id 类型标识
     * @param label 显示标签
     * @param description 类型描述
     * @param icon 图标名称
     * @param color 颜色值
     * @param sortOrder 排序序号
     * @param enabled 启用状态
     * @return 更新后的类型
     */
    @Transactional(rollbackFor = Exception.class)
    public NotificationTypeDto update(
            UUID id,
            String label,
            String description,
            String icon,
            String color,
            Integer sortOrder,
            Boolean enabled
    ) {
        NotificationType entity = notificationTypeRepository.findById(id)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "通知类型不存在: " + id));
        if (label != null) {
            entity.setLabel(label);
        }
        if (description != null) {
            entity.setDescription(description);
        }
        if (icon != null) {
            entity.setIcon(icon);
        }
        if (color != null) {
            entity.setColor(color);
        }
        if (sortOrder != null) {
            entity.setSortOrder(sortOrder);
        }
        if (enabled != null) {
            entity.setEnabled(enabled);
        }
        return NotificationTypeDto.from(notificationTypeRepository.save(entity));
    }
}
