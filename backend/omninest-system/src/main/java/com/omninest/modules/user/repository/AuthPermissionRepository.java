package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthPermission;
import java.util.Set;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AuthPermissionRepository extends JpaRepository<AuthPermission, UUID> {
    Set<AuthPermission> findByCodeIn(Set<String> codes);
}
