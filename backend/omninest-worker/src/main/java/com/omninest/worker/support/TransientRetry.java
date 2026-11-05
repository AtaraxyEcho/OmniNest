package com.omninest.worker.support;

import java.util.concurrent.Callable;
import java.util.concurrent.TimeUnit;
import lombok.extern.slf4j.Slf4j;

/**
 * 无任务记录消息的本地少量重试。
 *
 * <p>索引与恢复类队列没有 {@code sys_task} 行，进入死信后没有任何补跑机制：
 * 一次瞬时失败（Lucene 写锁竞争、句柄尚未释放）就会让该节点永久缺索引，
 * 只能靠全量重建恢复。因此在投递死信之前先做几次短退避重试。</p>
 *
 * @author OmniNest
 */
@Slf4j
public final class TransientRetry {

    private static final int MAX_ATTEMPTS = 4;
    /** 递增退避：500ms、1500ms、3000ms；必须跨过 Lucene 全量重建的写锁窗口。 */
    private static final long[] BACKOFF_MILLIS = {500L, 1500L, 3000L};

    private TransientRetry() {
    }

    /**
     * 执行动作，失败时按 500/1500/3000 毫秒退避重试，最多四次；最后一次失败原样抛出。
     *
     * @param label 日志标识
     * @param callable 业务动作
     * @param <T> 返回值类型
     * @return 业务动作的返回值
     * @throws Exception 最后一次失败的原因
     */
    public static <T> T call(String label, Callable<T> callable) throws Exception {
        for (int attempt = 1; ; attempt++) {
            try {
                return callable.call();
            } catch (Exception exception) {
                if (attempt >= MAX_ATTEMPTS) {
                    throw exception;
                }
                log.warn("{}失败，准备重试: attempt={}/{}, errorType={}, message={}",
                        label, attempt, MAX_ATTEMPTS,
                        exception.getClass().getSimpleName(), exception.getMessage());
                try {
                    TimeUnit.MILLISECONDS.sleep(BACKOFF_MILLIS[Math.min(attempt - 1, BACKOFF_MILLIS.length - 1)]);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    throw exception;
                }
            }
        }
    }
}
