package com.omninest.modules.file.service;

import com.omninest.common.user.RoleDeletedEvent;
import com.omninest.modules.file.repository.SharedSpacePermissionRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * 角色删除后的共享空间权限清理。
 *
 * <p>删除角色时系统模块发布事件，本监听器在同一事务内移除共享空间权限行，
 * 避免数据库无外键时残留孤儿授权。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class SharedSpaceRoleCleanupListener {

    private final SharedSpacePermissionRepository permissionRepository;

    @EventListener
    public void onRoleDeleted(RoleDeletedEvent event) {
        permissionRepository.deleteByRoleId(event.roleId());
        log.info("已清理共享空间角色权限: roleId={}, roleCode={}", event.roleId(), event.roleCode());
    }
}
