package com.omninest.modules.quota.service;

import com.omninest.modules.notification.port.NotificationPublisher;
import jakarta.annotation.PreDestroy;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 配额预警通知的异步投递器。
 *
 * <p>配额扣减处于业务主事务内，而通知落库使用独立短事务。若在同一线程内直接调用，
 * 主事务持有的连接尚未归还时又要申请第二条连接；虚拟线程下并发请求会把这个窗口
 * 放大成连接池死锁。这里用受并发上限约束的虚拟线程在事务提交后投递，主线程立即
 * 返回并释放连接。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class QuotaNotificationDispatcher {
    private static final int MAX_CONCURRENT_DELIVERIES = 2;

    private final NotificationPublisher notificationPublisher;
    private final Semaphore permits = new Semaphore(MAX_CONCURRENT_DELIVERIES);
    private final ExecutorService executor = Executors.newThreadPerTaskExecutor(
            Thread.ofVirtual().name("quota-notify-", 0).factory());

    /**
     * 异步投递配额预警；并发已满时丢弃本次预警，避免堆积线程与连接。
     *
     * @param userId 接收用户
     * @param type 通知类型
     * @param title 标题
     * @param message 正文
     * @param metadata 附加上下文
     */
    public void dispatch(UUID userId, String type, String title, String message, Map<String, Object> metadata) {
        if (!permits.tryAcquire()) {
            log.warn("配额预警投递并发已满，丢弃本次通知: userId={}, type={}", userId, type);
            return;
        }
        executor.execute(() -> {
            try {
                notificationPublisher.notifyOrLog(userId, type, title, message, metadata);
            } catch (RuntimeException exception) {
                log.warn("配额预警异步投递失败: userId={}, errorType={}", userId,
                        exception.getClass().getSimpleName());
            } finally {
                permits.release();
            }
        });
    }

    @PreDestroy
    void shutdown() {
        executor.shutdown();
    }
}
