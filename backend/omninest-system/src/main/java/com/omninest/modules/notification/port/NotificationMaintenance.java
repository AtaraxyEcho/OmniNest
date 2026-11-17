package com.omninest.modules.notification.port;

import java.time.Instant;
import java.util.UUID;

/**
 * 通知模块对外维护端口：供跨模块治理流程（如管理端账户删除、保留期清理）维护用户通知。
 *
 * @author OmniNest
 */
public interface NotificationMaintenance {

    /**
     * 物理清空该用户全部站内通知，不产生同步事件。
     *
     * @param userId 用户标识
     */
    void adminPurgeForUser(UUID userId);

    /**
     * 分批删除已读且创建时间早于截止时刻的站内通知。
     *
     * <p>未读通知不参与清理：配额预警这类提醒只有读过才算送达，静默删除会让用户永久错过。
     * 删除的都是已读项，未读数缓存无需失效，也不产生同步事件。</p>
     *
     * @param cutoff 截止时刻
     * @param limit 单批最大删除条数
     * @return 实际删除条数
     */
    int deleteReadNotificationsBefore(Instant cutoff, int limit);
}
