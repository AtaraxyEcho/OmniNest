package com.omninest.modules.photos.service;

import java.time.Duration;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.locks.LockSupport;
import org.springframework.stereotype.Component;

/**
 * Nominatim 请求使用的进程级动态速率限制器。
 *
 * @author OmniNest
 */
@Component
public class NominatimRateLimiter {

    private static final long NANOS_PER_SECOND = Duration.ofSeconds(1).toNanos();

    private final AtomicLong nextPermitNanos = new AtomicLong();

    /**
     * 在指定等待时间内获取请求时隙。
     *
     * @param permitsPerSecond 每秒允许请求数
     * @param timeout 最大等待时间
     * @return 是否获得请求时隙
     */
    public boolean tryAcquire(int permitsPerSecond, Duration timeout) {
        int normalizedRate = Math.max(1, permitsPerSecond);
        long intervalNanos = Math.max(1, NANOS_PER_SECOND / normalizedRate);
        long timeoutNanos = Math.max(0, timeout.toNanos());
        while (true) {
            long now = System.nanoTime();
            long currentSlot = nextPermitNanos.get();
            long permitSlot = Math.max(now, currentSlot);
            long waitNanos = permitSlot - now;
            if (waitNanos > timeoutNanos) {
                return false;
            }
            if (nextPermitNanos.compareAndSet(currentSlot, permitSlot + intervalNanos)) {
                return waitForSlot(permitSlot);
            }
        }
    }

    private boolean waitForSlot(long permitSlot) {
        long remainingNanos = permitSlot - System.nanoTime();
        while (remainingNanos > 0) {
            LockSupport.parkNanos(remainingNanos);
            if (Thread.currentThread().isInterrupted()) {
                return false;
            }
            remainingNanos = permitSlot - System.nanoTime();
        }
        return true;
    }
}
