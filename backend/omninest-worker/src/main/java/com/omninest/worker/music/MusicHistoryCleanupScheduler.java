package com.omninest.worker.music;

import com.omninest.modules.music.service.MusicLibraryService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import com.omninest.modules.task.runtime.ConditionalOnSchedulerRuntime;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 音乐播放历史过期清理调度器。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnSchedulerRuntime
public class MusicHistoryCleanupScheduler {

    private final MusicLibraryService musicLibraryService;

    /**
     * 按计划清理超过保留期的播放历史。
     */
    @Scheduled(cron = "${omninest.music.history-cleanup-cron:0 20 3 * * *}")
    public void cleanupExpiredHistory() {
        try {
            musicLibraryService.cleanupExpiredPlayHistory();
        } catch (RuntimeException exception) {
            log.error("音乐播放历史过期清理失败: errorType={}", exception.getClass().getSimpleName(), exception);
        }
    }
}
