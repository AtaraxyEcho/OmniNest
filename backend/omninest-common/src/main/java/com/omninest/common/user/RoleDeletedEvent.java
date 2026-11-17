package com.omninest.common.user;

import java.util.UUID;

/**
 * 角色删除事件。
 *
 * <p>数据库不声明外键，角色在其他模块的关联行需要在删除角色的事务内同步清理；
 * 事件由本进程同步投递，监听方与删除方共享同一事务。</p>
 *
 * @param roleId 已删除角色 ID
 * @param roleCode 已删除角色编码
 * @author OmniNest
 */
public record RoleDeletedEvent(UUID roleId, String roleCode) {
}
