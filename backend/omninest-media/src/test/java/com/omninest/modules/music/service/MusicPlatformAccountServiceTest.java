package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginSession;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginStatus;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.service.platform.MusicPlatform;
import com.omninest.modules.music.service.platform.MusicPlatformCapabilities;
import com.omninest.modules.music.service.platform.NeteaseMusicProxy;
import com.omninest.modules.music.service.platform.QQMusicApi;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 在线音乐平台账号编排测试。
 *
 * @author OmniNest
 */
class MusicPlatformAccountServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final NeteaseMusicProxy neteaseProvider = mock(NeteaseMusicProxy.class);
    private final QQMusicApi qqProvider = mock(QQMusicApi.class);
    private final MusicRuntimeConfigService configService = mock(MusicRuntimeConfigService.class);
    private final MusicPlatformLoginSessionService loginSessionService = mock(MusicPlatformLoginSessionService.class);
    private final MusicPlatformCredentialService credentialService = mock(MusicPlatformCredentialService.class);
    private final MediaSyncEventService mediaSyncEventService = mock(MediaSyncEventService.class);
    private final MusicPlatformAccountService service = new MusicPlatformAccountService(
            List.of(neteaseProvider, qqProvider),
            neteaseProvider,
            qqProvider,
            configService,
            loginSessionService,
            credentialService,
            mediaSyncEventService
    );

    @BeforeEach
    void setUp() {
        when(neteaseProvider.platform()).thenReturn(MusicPlatform.NETEASE);
        when(qqProvider.platform()).thenReturn(MusicPlatform.QQ);
        when(neteaseProvider.capabilities()).thenReturn(new MusicPlatformCapabilities(
                true,
                true,
                true,
                true,
                true,
                List.of("lossless")
        ));
        when(qqProvider.capabilities()).thenReturn(new MusicPlatformCapabilities(
                true,
                true,
                false,
                true,
                false,
                List.of("exhigh")
        ));
        when(configService.onlineEnabled()).thenReturn(true);
        when(configService.neteaseEnabled()).thenReturn(true);
        when(configService.qqMusicEnabled()).thenReturn(true);
    }

    @Test
    void qrLoginSessionIsBoundToCurrentUser() {
        QrLoginSession session = new QrLoginSession("login-key", "qr-url", "image");
        when(neteaseProvider.createQrLogin()).thenReturn(session);

        assertThat(service.createNeteaseQrLogin(OWNER_ID)).isEqualTo(session);

        verify(loginSessionService).register(OWNER_ID, MusicPlatform.NETEASE, "login-key");
    }

    @Test
    void qrLoginPollRequiresSessionOwnershipAndCompletesTerminalState() {
        when(neteaseProvider.checkQrLogin(OWNER_ID, "login-key"))
                .thenReturn(new QrLoginStatus("confirmed", null));

        QrLoginStatus status = service.checkNeteaseQrLogin(OWNER_ID, "login-key");

        assertThat(status.status()).isEqualTo("confirmed");
        verify(loginSessionService).requireOwner(OWNER_ID, MusicPlatform.NETEASE, "login-key");
        verify(loginSessionService).complete(MusicPlatform.NETEASE, "login-key");
    }

    @Test
    void platformStatusExposesCapabilitiesWithoutCredentials() {
        var statuses = service.platforms(OWNER_ID);

        assertThat(statuses).hasSize(2);
        assertThat(statuses.get(0).platform()).isEqualTo("netease");
        assertThat(statuses.get(0).connected()).isFalse();
        assertThat(statuses.get(1).capabilities().likedTracks()).isFalse();
    }
}
