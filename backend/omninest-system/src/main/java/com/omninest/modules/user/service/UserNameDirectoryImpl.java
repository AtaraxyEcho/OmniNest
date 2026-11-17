package com.omninest.modules.user.service;

import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.port.UserNameDirectory;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 用户显示名查询端口的系统模块实现：只读、批量、容错（未知用户静默缺省）。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class UserNameDirectoryImpl implements UserNameDirectory {

    private final AuthUserRepository userRepository;

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, String> resolveDisplayNames(Collection<UUID> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, String> names = new HashMap<>();
        for (AuthUser user : userRepository.findAllById(userIds)) {
            String label = user.getDisplayName();
            if (label == null || label.isBlank()) {
                label = user.getUsername();
            }
            if (label != null && !label.isBlank()) {
                names.put(user.getId(), label);
            }
        }
        return names;
    }
}
