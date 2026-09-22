package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.music.dto.OnlineMusicDtos.PlatformUserInfo;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginSession;
import com.omninest.modules.music.dto.OnlineMusicDtos.QrLoginStatus;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.service.platform.MusicPlatform;
import com.omninest.modules.music.service.platform.MusicPlatformCapabilities;
import com.omninest.modules.music.service.platform.MusicPlatformCredential;
import com.omninest.modules.music.service.platform.NeteaseMusicProxy;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 在线音乐平台账号编排测试。
 *
 * @author OmniNest
 */
class MusicPlatformAccountServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final String LOGIN_KEY = "login-key";
    private static final PlatformUserInfo SAVED_USER =
            new PlatformUserInfo("netease", "42", "听歌的人", "https://cdn/avatar.png", true);

    private final NeteaseMusicProxy neteaseProvider = mock(NeteaseMusicProxy.class);
    private final MusicRuntimeConfigService configService = mock(MusicRuntimeConfigService.class);
    private final MusicPlatformLoginSessionService loginSessionService = mock(MusicPlatformLoginSessionService.class);
    private final MusicPlatformCredentialService credentialService = mock(MusicPlatformCredentialService.class);
    private final MediaSyncEventService mediaSyncEventService = mock(MediaSyncEventService.class);
    private final MusicPlatformService musicPlatformService = mock(MusicPlatformService.class);
    private final MusicPlaybackQueueService musicPlaybackQueueService = mock(MusicPlaybackQueueService.class);
    private final MusicPlatformAccountService service = new MusicPlatformAccountService(
            List.of(neteaseProvider),
            neteaseProvider,
            configService,
            loginSessionService,
            credentialService,
            mediaSyncEventService,
            musicPlatformService,
            musicPlaybackQueueService,
            new StubTransactionManager()
    );

    /**
     * 最小事务管理器：把"当前存在活动事务"如实反映到
     * {@link TransactionSynchronizationManager}，使同步事件记录器的
     * {@code Propagation.MANDATORY} 契约在无 Spring 上下文的单测中也可断言。
     */
    private static final class StubTransactionManager implements PlatformTransactionManager {

        @Override
        public TransactionStatus getTransaction(TransactionDefinition definition) {
            TransactionSynchronizationManager.setActualTransactionActive(true);
            if (!TransactionSynchronizationManager.isSynchronizationActive()) {
                TransactionSynchronizationManager.initSynchronization();
            }
            return new SimpleTransactionStatus(true);
        }

        @Override
        public void commit(TransactionStatus status) {
            release();
        }

        @Override
        public void rollback(TransactionStatus status) {
            release();
        }

        private void release() {
            if (TransactionSynchronizationManager.isSynchronizationActive()) {
                TransactionSynchronizationManager.clearSynchronization();
            }
            TransactionSynchronizationManager.setActualTransactionActive(false);
        }
    }

    @BeforeEach
    void setUp() {
        when(neteaseProvider.platform()).thenReturn(MusicPlatform.NETEASE);
        when(neteaseProvider.capabilities()).thenReturn(new MusicPlatformCapabilities(
                true,
                true,
                true,
                true,
                true,
                List.of("lossless")
        ));
        when(configService.onlineEnabled()).thenReturn(true);
        when(configService.neteaseEnabled()).thenReturn(true);
        service.initTransactionTemplate();
    }

    @Test
    void qrLoginSessionIsBoundToCurrentUser() {
        QrLoginSession session = new QrLoginSession(LOGIN_KEY, "qr-url", "image");
        when(neteaseProvider.createQrLogin()).thenReturn(session);

        assertThat(service.createNeteaseQrLogin(OWNER_ID)).isEqualTo(session);

        verify(loginSessionService).register(OWNER_ID, MusicPlatform.NETEASE, LOGIN_KEY);
    }

    @Test
    void qrLoginPollRequiresSessionOwnershipAndMarksConfirmed() {
        when(neteaseProvider.checkQrLogin(OWNER_ID, LOGIN_KEY))
                .thenReturn(new QrLoginStatus("confirmed", SAVED_USER));

        QrLoginStatus status = service.checkNeteaseQrLogin(OWNER_ID, LOGIN_KEY);

        assertThat(status.status()).isEqualTo("confirmed");
        verify(loginSessionService).requireOwner(OWNER_ID, MusicPlatform.NETEASE, LOGIN_KEY);
        // 确认成功后不再结束会话，而是留档确认标记：平台已消费一次性密钥，
        // 后续同一 key 的轮询只能拿到 800，需要靠标记幂等回退为成功。
        verify(loginSessionService).markConfirmed(OWNER_ID, MusicPlatform.NETEASE, LOGIN_KEY);
        verify(loginSessionService, never()).complete(MusicPlatform.NETEASE, LOGIN_KEY);
        verify(mediaSyncEventService).invalidate(eq(OWNER_ID), any(), eq("MUSIC_PLATFORM"), any());
    }

    @Test
    void qrLoginPollFallsBackToConfirmedWhenPlatformExpiresAfterConfirmation() {
        when(neteaseProvider.checkQrLogin(OWNER_ID, LOGIN_KEY))
                .thenReturn(new QrLoginStatus("expired", null));
        when(loginSessionService.wasConfirmed(MusicPlatform.NETEASE, LOGIN_KEY)).thenReturn(true);
        when(credentialService.find(OWNER_ID, MusicPlatform.NETEASE)).thenReturn(Optional.of(
                new MusicPlatformCredential("cookie", "42", SAVED_USER, Instant.now())
        ));

        QrLoginStatus status = service.checkNeteaseQrLogin(OWNER_ID, LOGIN_KEY);

        // 平台报失效但此前已确认过：判定为登录成功并携带已落库的账号资料。
        assertThat(status.status()).isEqualTo("confirmed");
        assertThat(status.userInfo()).isEqualTo(SAVED_USER);
        verify(loginSessionService).complete(MusicPlatform.NETEASE, LOGIN_KEY);
    }

    @Test
    void qrLoginPollKeepsExpiredWhenNeverConfirmed() {
        when(neteaseProvider.checkQrLogin(OWNER_ID, LOGIN_KEY))
                .thenReturn(new QrLoginStatus("expired", null));
        when(loginSessionService.wasConfirmed(MusicPlatform.NETEASE, LOGIN_KEY)).thenReturn(false);

        QrLoginStatus status = service.checkNeteaseQrLogin(OWNER_ID, LOGIN_KEY);

        assertThat(status.status()).isEqualTo("expired");
        verify(loginSessionService).complete(MusicPlatform.NETEASE, LOGIN_KEY);
        verify(credentialService, never()).find(any(), any());
    }

    @Test
    void platformStatusExposesCapabilitiesWithoutCredentials() {
        var statuses = service.platforms(OWNER_ID);

        assertThat(statuses).hasSize(1);
        assertThat(statuses.get(0).platform()).isEqualTo("netease");
        assertThat(statuses.get(0).connected()).isFalse();
        assertThat(statuses.get(0).capabilities().likedTracks()).isTrue();
    }

    /**
     * 同步事件记录器声明为 MANDATORY：缺少活动事务会抛 IllegalTransactionStateException
     * 并让接口整体 500。历史上平台登录/确认路径正是缺事务上下文触发了该异常，
     * 因此这里锁定"广播必须在事务内"这一契约。
     */
    @Test
    void platformChangeBroadcastRunsInsideActiveTransaction() {
        AtomicBoolean transactionActiveInsideCall = new AtomicBoolean(false);
        doAnswer(invocation -> {
            transactionActiveInsideCall.set(
                    TransactionSynchronizationManager.isActualTransactionActive()
            );
            return null;
        }).when(mediaSyncEventService).invalidate(any(), any(), any(), any());
        when(neteaseProvider.checkQrLogin(OWNER_ID, LOGIN_KEY))
                .thenReturn(new QrLoginStatus("confirmed", SAVED_USER));

        service.checkNeteaseQrLogin(OWNER_ID, LOGIN_KEY);

        assertThat(transactionActiveInsideCall).isTrue();
    }

    @Test
    void disconnectClearsCredentialsAndPlatformDerivedState() {
        when(musicPlaybackQueueService.removePlatformTracks(OWNER_ID, "netease")).thenReturn(3);

        service.disconnect(OWNER_ID, "netease");

        verify(neteaseProvider).clearLogin(OWNER_ID);
        // 断开标记用于拒绝旧会话的迟到确认，避免"退出后又被扫码确认登入"。
        verify(loginSessionService).markDisconnected(OWNER_ID, MusicPlatform.NETEASE);
        verify(musicPlatformService).invalidateDailyRecommendations(OWNER_ID, "netease");
        verify(musicPlaybackQueueService).removePlatformTracks(OWNER_ID, "netease");
        verify(mediaSyncEventService).invalidate(eq(OWNER_ID), any(), eq("MUSIC_PLATFORM"), any());
    }

    @Test
    void qrPollIsRejectedWhileUserIsMarkedDisconnected() {
        when(loginSessionService.isDisconnected(OWNER_ID, MusicPlatform.NETEASE)).thenReturn(true);

        QrLoginStatus status = service.checkNeteaseQrLogin(OWNER_ID, LOGIN_KEY);

        assertThat(status.status()).isEqualTo("expired");
        verify(neteaseProvider, never()).checkQrLogin(any(), anyString());
        verify(mediaSyncEventService, never()).invalidate(any(), any(), any(), any());
    }
}
