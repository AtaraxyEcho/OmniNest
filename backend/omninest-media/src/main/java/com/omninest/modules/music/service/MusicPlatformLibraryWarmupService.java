package com.omninest.modules.music.service;

import com.omninest.modules.music.service.platform.MusicPlatform;
import com.omninest.modules.music.service.platform.NeteaseMusicProxy;
import jakarta.annotation.PreDestroy;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.SynchronousQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 扫码登录确认后的平台曲库预热。
 *
 * <p>确认响应保持轻量（落盘凭据即返回），账号资料、歌单与喜欢列表的第三方回源由本服务
 * 在后台先行填充读穿缓存；前端随后的请求直接命中缓存，或经缓存单飞合并到同一次回源，
 * 把「确认 → 曲库可用」从串行等待压成并行预热。</p>
 *
 * <p>预热是纯优化：使用单线程 + 同步队列 + 中止策略的专用执行器，繁忙时本次预热直接
 * 放弃，绝不借用 musicOnlineExecutor 的 CallerRuns 兜底（那会把扫码确认响应拖在请求线程上）。
 * 单用户以在途标记去重，双端同扫一个 key 的重复确认不会触发两次预热。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicPlatformLibraryWarmupService {

    private final MusicPlatformService musicPlatformService;
    private final NeteaseMusicProxy neteaseMusicProxy;
    private final MusicOnlineDispatcher dispatcher;

    private final Set<UUID> warmingUsers = ConcurrentHashMap.newKeySet();

    private final ThreadPoolExecutor warmupExecutor = new ThreadPoolExecutor(
            1,
            1,
            0L,
            TimeUnit.MILLISECONDS,
            new SynchronousQueue<>(),
            runnable -> {
                Thread thread = new Thread(runnable, "music-platform-warmup");
                thread.setDaemon(true);
                return thread;
            },
            new ThreadPoolExecutor.AbortPolicy()
    );

    /**
     * 登录确认后预热网易云账号内容缓存。
     *
     * <p>异步执行且不抛业务异常：用户可能随即断开连接，预热失败不影响正常读取路径
     * 自行回源。page/size 只影响返回切片，读穿缓存始终写入整表。</p>
     *
     * @param ownerUserId 所属用户 ID
     */
    public void warmNeteaseLibrary(UUID ownerUserId) {
        if (!warmingUsers.add(ownerUserId)) {
            return;
        }
        try {
            warmupExecutor.execute(() -> {
                try {
                    runWarmup(ownerUserId);
                } finally {
                    warmingUsers.remove(ownerUserId);
                }
            });
        } catch (RejectedExecutionException exception) {
            warmingUsers.remove(ownerUserId);
            log.debug("音乐平台曲库预热被跳过（执行器繁忙）: userId={}", ownerUserId);
        }
    }

    /**
     * 预热编排：资料先行，歌单与喜欢并行填充读穿缓存。
     *
     * <p>包内可见以便单测同步直调；在途标记由 {@link #warmNeteaseLibrary} 的执行器
     * 包装层负责，本方法自身不触碰标记。</p>
     */
    void runWarmup(UUID ownerUserId) {
        try {
            // 资料先行：确认时落盘的是占位资料，externalUserId 补齐后歌单/喜欢支路不必各自回源。
            neteaseMusicProxy.getUserInfo(ownerUserId);
            String platform = MusicPlatform.NETEASE.apiValue();
            CompletableFuture<?> playlists = dispatcher.supply(
                    () -> musicPlatformService.playlists(ownerUserId, platform, 0, 1, false)
            );
            CompletableFuture<?> liked = dispatcher.supply(
                    () -> musicPlatformService.likedTracks(ownerUserId, platform, 0, 1, false)
            );
            CompletableFuture.allOf(playlists, liked).join();
        } catch (RuntimeException exception) {
            log.debug(
                    "音乐平台曲库预热未完成: userId={}, reason={}",
                    ownerUserId,
                    exception.getMessage()
            );
        }
    }

    @PreDestroy
    void shutdown() {
        warmupExecutor.shutdownNow();
    }
}
