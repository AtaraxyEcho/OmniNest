package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.music.service.platform.NeteaseMusicProxy;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;

/**
 * 扫码确认后的曲库预热行为测试。
 *
 * <p>编排断言通过包内可见的 {@code runWarmup} 在测试线程同步直调，避免跨线程
 * Mockito 校验；经过执行器的去重语义用闩锁汇合预热线程后再断言。</p>
 *
 * @author OmniNest
 */
class MusicPlatformLibraryWarmupServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("20000000-0000-0000-0000-000000000002");

    private final MusicPlatformService musicPlatformService = mock(MusicPlatformService.class);
    private final NeteaseMusicProxy neteaseMusicProxy = mock(NeteaseMusicProxy.class);
    private final MusicOnlineDispatcher dispatcher = mock(MusicOnlineDispatcher.class);
    private final MusicPlatformLibraryWarmupService service = new MusicPlatformLibraryWarmupService(
            musicPlatformService,
            neteaseMusicProxy,
            dispatcher
    );

    @Test
    void warmupFillsAccountProfileBeforeLibraryCaches() {
        when(dispatcher.supply(any())).thenAnswer(invocation -> {
            Supplier<?> supplier = invocation.getArgument(0);
            return CompletableFuture.completedFuture(supplier.get());
        });

        service.runWarmup(OWNER_ID);

        verify(musicPlatformService).playlists(OWNER_ID, "netease", 0, 1, false);
        verify(musicPlatformService).likedTracks(OWNER_ID, "netease", 0, 1, false);
        InOrder order = inOrder(neteaseMusicProxy, musicPlatformService);
        order.verify(neteaseMusicProxy).getUserInfo(OWNER_ID);
        order.verify(musicPlatformService).playlists(OWNER_ID, "netease", 0, 1, false);
    }

    @Test
    void warmupSwallowsFailuresAndDoesNotPropagate() {
        when(neteaseMusicProxy.getUserInfo(OWNER_ID)).thenThrow(
                new BusinessException(ErrorCode.MUSIC_PLATFORM_NOT_CONNECTED, "请先连接网易云音乐")
        );

        assertThatCode(() -> service.runWarmup(OWNER_ID)).doesNotThrowAnyException();

        // 资料回源失败（用户可能已断开）不继续加载曲库。
        verify(dispatcher, never()).supply(any());
    }

    @Test
    void warmupTreatsAggregationFailureAsCompleted() {
        when(dispatcher.supply(any())).thenAnswer(invocation ->
                CompletableFuture.failedFuture(new IllegalStateException("boom"))
        );

        assertThatCode(() -> service.runWarmup(OWNER_ID)).doesNotThrowAnyException();

        verify(neteaseMusicProxy).getUserInfo(OWNER_ID);
        verify(dispatcher, times(2)).supply(any());
    }

    @Test
    void warmNeteaseLibraryDeduplicatesWhileWarmingAndReleasesAfterCompletion() throws Exception {
        CountDownLatch firstProfileFetched = new CountDownLatch(1);
        CountDownLatch profileFetches = new CountDownLatch(2);
        CountDownLatch libraryLoads = new CountDownLatch(2);
        CompletableFuture<Object> gate = new CompletableFuture<>();
        when(neteaseMusicProxy.getUserInfo(OWNER_ID)).thenAnswer(invocation -> {
            firstProfileFetched.countDown();
            profileFetches.countDown();
            return null;
        });
        when(dispatcher.supply(any())).thenAnswer(invocation -> {
            Supplier<?> supplier = invocation.getArgument(0);
            return gate.thenApply(ignored -> supplier.get());
        });
        doAnswer(invocation -> {
            libraryLoads.countDown();
            return null;
        }).when(musicPlatformService).likedTracks(any(), any(), anyInt(), anyInt(), anyBoolean());

        service.warmNeteaseLibrary(OWNER_ID);
        // 预热线程已进入聚合等待（资料已取、两笔曲库加载已挂起）。
        assertThat(firstProfileFetched.await(2, TimeUnit.SECONDS))
                .as("预热线程未在时限内取得账号资料")
                .isTrue();
        // 在途标记未释放期间，同一用户的重复预热被跳过。
        service.warmNeteaseLibrary(OWNER_ID);
        gate.complete(null);
        // 留出第一轮预热聚合返回并释放标记的余量。
        Thread.sleep(200);

        service.warmNeteaseLibrary(OWNER_ID);
        assertThat(libraryLoads.await(2, TimeUnit.SECONDS))
                .as("预热未在时限内完成曲库加载")
                .isTrue();
        // 留出预热线程 finally 移除标记与返回的余量后再做静态断言。
        Thread.sleep(200);

        // 三次发起只产生两轮预热（getUserInfo 两次、每轮两笔曲库加载）。
        verify(neteaseMusicProxy, times(2)).getUserInfo(OWNER_ID);
        verify(dispatcher, times(4)).supply(any());
    }
}
