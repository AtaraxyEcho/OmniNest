package com.omninest.modules.user.service;

import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.port.RoleLookup;
import com.omninest.modules.user.repository.AuthRoleRepository;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * {@link RoleLookup} 的默认实现，直接读 {@code auth_roles}。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class RoleLookupService implements RoleLookup {

    private final AuthRoleRepository authRoleRepository;

    @Override
    @Transactional(readOnly = true)
    public List<RoleRef> listAll() {
        return authRoleRepository.findAll().stream()
                .map(role -> new RoleRef(role.getId(), role.getCode()))
                .toList();
    }

    @Override
    @Transactional(readOnly = true)
    public boolean existsById(UUID roleId) {
        return roleId != null && authRoleRepository.existsById(roleId);
    }

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, String> codesById(Collection<UUID> roleIds) {
        if (roleIds == null || roleIds.isEmpty()) {
            return Map.of();
        }
        return authRoleRepository.findAllById(roleIds).stream()
                .collect(Collectors.toMap(AuthRole::getId, AuthRole::getCode, (l, r) -> l));
    }
}
