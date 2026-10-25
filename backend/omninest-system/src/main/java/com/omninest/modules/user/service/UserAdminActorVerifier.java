package com.omninest.modules.user.service;

import com.omninest.common.security.FreshAdminActorVerifier;
import com.omninest.modules.quota.port.AdminActorVerifier;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 以库内当前角色绑定复核管理台操作者，供配额等跨模块写入口使用。
 *
 * <p>只转发 {@link AdminActorGuard}，不额外加判据：撤权即时生效的口径必须与
 * 用户、角色管理端一致，否则同为管理员写操作却有两套严格度。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class UserAdminActorVerifier implements AdminActorVerifier, FreshAdminActorVerifier {

    private final AdminActorGuard adminActorGuard;

    @Override
    public void requireFreshAdminActor(UUID actorUserId) {
        adminActorGuard.requireFreshAdminActor(actorUserId);
    }
}
