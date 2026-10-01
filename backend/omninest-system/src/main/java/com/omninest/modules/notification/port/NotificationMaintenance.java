package com.omninest.modules.notification.port;

import java.util.UUID;

/**
 * 通知模块对外维护端口：供跨模块治理流程（如管理端账户删除）清空用户通知。
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
}
