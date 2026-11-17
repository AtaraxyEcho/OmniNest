package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.common.security.ExpiringOwnershipRegistry;
import com.omninest.modules.music.service.platform.MusicPlatform;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 音乐平台登录会话归属测试。
 *
 * @author OmniNest
 */
class MusicPlatformLoginSessionServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OTHER_USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final String LOGIN_KEY = "login-key";

    private final ExpiringOwnershipRegistry ownershipRegistry = Mockito.mock(ExpiringOwnershipRegistry.class);
    private final MusicPlatformLoginSessionService service =
            new MusicPlatformLoginSessionService(ownershipRegistry);

    @Test
    void registerStoresOwnerWithShortTtl() {
        service.register(OWNER_ID, MusicPlatform.NETEASE, LOGIN_KEY);

        verify(ownershipRegistry).register(
                "omninest:integration:music:login:netease:" + LOGIN_KEY,
                OWNER_ID,
                Duration.ofMinutes(5)
        );
    }

    @Test
    void registerClearsDisconnectedMarkForNewSession() {
        service.register(OWNER_ID, MusicPlatform.NETEASE, LOGIN_KEY);

        // 重新发起登录必须清除断开标记，否则新会话的确认会被误判为"迟到的旧确认"。
        verify(ownershipRegistry).remove(
                "omninest:integration:music:disconnected:netease:" + OWNER_ID
        );
    }

    @Test
    void markDisconnectedOutlivesConfirmedMarkWindow() {
        service.markDisconnected(OWNER_ID, MusicPlatform.NETEASE);

        verify(ownershipRegistry).register(
                "omninest:integration:music:disconnected:netease:" + OWNER_ID,
                OWNER_ID,
                Duration.ofMinutes(15)
        );
    }

    @Test
    void isDisconnectedReflectsMarkPresence() {
        when(ownershipRegistry.findOwner(
                "omninest:integration:music:disconnected:netease:" + OWNER_ID
        )).thenReturn(Optional.of(OWNER_ID));

        assertThat(service.isDisconnected(OWNER_ID, MusicPlatform.NETEASE)).isTrue();
        assertThat(service.isDisconnected(OTHER_USER_ID, MusicPlatform.NETEASE)).isFalse();
    }

    @Test
    void requireOwnerRejectsAnotherUser() {
        when(ownershipRegistry.findOwner("omninest:integration:music:login:netease:" + LOGIN_KEY))
                .thenReturn(Optional.of(OWNER_ID));

        assertThatThrownBy(() -> service.requireOwner(OTHER_USER_ID, MusicPlatform.NETEASE, LOGIN_KEY))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("无权访问");
    }

    @Test
    void requireOwnerRejectsExpiredSession() {
        when(ownershipRegistry.findOwner("omninest:integration:music:login:netease:" + LOGIN_KEY))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.requireOwner(OWNER_ID, MusicPlatform.NETEASE, LOGIN_KEY))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不存在或已过期");
    }

    @Test
    void completeRemovesOwnershipRegistration() {
        service.complete(MusicPlatform.NETEASE, LOGIN_KEY);

        verify(ownershipRegistry).remove(
                "omninest:integration:music:login:netease:" + LOGIN_KEY
        );
    }
}
