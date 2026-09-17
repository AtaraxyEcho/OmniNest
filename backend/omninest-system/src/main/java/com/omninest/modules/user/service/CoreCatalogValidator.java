package com.omninest.modules.user.service;

import com.omninest.common.security.Permissions;
import com.omninest.common.security.Roles;
import com.omninest.modules.user.config.InitialSetupProperties;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.SystemInstance;
import com.omninest.modules.user.repository.AuthPermissionRepository;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.SystemInstanceRepository;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 在应用就绪前校验首次安装所依赖的内置目录。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class CoreCatalogValidator implements ApplicationRunner {
    private static final Set<String> REQUIRED_ROLES = Set.of(
            Roles.SUPER_ADMIN,
            Roles.ADMIN,
            Roles.MEMBER,
            Roles.GUEST
    );

    private final AuthRoleRepository authRoleRepository;
    private final AuthPermissionRepository authPermissionRepository;
    private final SystemInstanceRepository systemInstanceRepository;
    private final InitialSetupProperties initialSetupProperties;

    /**
     * 校验角色、权限和可选的持久实例状态。
     *
     * @param arguments 应用启动参数
     */
    @Override
    @Transactional(readOnly = true)
    public void run(ApplicationArguments arguments) {
        Map<String, AuthRole> roles = authRoleRepository
                .findAllWithPermissions(Sort.unsorted())
                .stream()
                .collect(Collectors.toMap(AuthRole::getCode, Function.identity()));
        Set<String> missingRoles = REQUIRED_ROLES.stream()
                .filter(code -> !roles.containsKey(code) || !roles.get(code).isEnabled())
                .collect(Collectors.toSet());
        if (!missingRoles.isEmpty()) {
            throw new IllegalStateException("内置角色目录缺失或已禁用: " + missingRoles);
        }

        Set<AuthPermission> permissions = authPermissionRepository.findByCodeIn(Permissions.SUPER_ADMIN_PERMISSIONS);
        Set<String> enabledPermissionCodes = permissions.stream()
                .filter(AuthPermission::isEnabled)
                .map(AuthPermission::getCode)
                .collect(Collectors.toSet());
        if (!enabledPermissionCodes.containsAll(Permissions.SUPER_ADMIN_PERMISSIONS)) {
            Set<String> missingPermissions = Permissions.SUPER_ADMIN_PERMISSIONS.stream()
                    .filter(code -> !enabledPermissionCodes.contains(code))
                    .collect(Collectors.toSet());
            throw new IllegalStateException("内置权限目录缺失或已禁用: " + missingPermissions);
        }

        Set<String> superAdminPermissions = roles.get(Roles.SUPER_ADMIN).getPermissions().stream()
                .map(AuthPermission::getCode)
                .collect(Collectors.toSet());
        if (!superAdminPermissions.containsAll(Permissions.SUPER_ADMIN_PERMISSIONS)) {
            throw new IllegalStateException("超级管理员角色未包含全部内置权限");
        }

        if (initialSetupProperties.isPersistentStateEnabled()
                && !systemInstanceRepository.existsById(SystemInstance.SINGLETON_ID)) {
            throw new IllegalStateException("系统实例状态未初始化");
        }
        log.info(
                "首次安装核心目录校验完成: persistentStateEnabled={}",
                initialSetupProperties.isPersistentStateEnabled()
        );
    }
}
