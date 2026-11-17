package com.omninest.modules.video.service;

import org.springframework.stereotype.Component;

/**
 * 根据总量和最近批次反馈计算下一安全 Chunk。
 */
@Component
public class AdaptiveChunkPolicy {
    private static final int MIN_TARGET_CHUNKS = 8;
    private static final int MAX_TARGET_CHUNKS = 256;
    private static final int DATABASE_BIND_BUDGET = 60_000;

    /** 根据估计总量取得首个 Chunk 大小。 */
    public int initialSize(BatchWorkloadProfile profile, long estimatedTotal) {
        if (estimatedTotal <= 0) {
            return profile.minItems();
        }
        long targetChunks = clamp(
                (long) Math.ceil(Math.sqrt(estimatedTotal)),
                MIN_TARGET_CHUNKS,
                MAX_TARGET_CHUNKS
        );
        long sizeByTotal = divideCeil(estimatedTotal, targetChunks);
        long sizeByDatabase = DATABASE_BIND_BUDGET / profile.bindColumnsPerItem();
        return Math.toIntExact(clamp(
                Math.min(sizeByTotal, sizeByDatabase),
                profile.minItems(),
                profile.maxItems()
        ));
    }

    /**
     * 根据最近提交结果反馈计算下一 Chunk。
     */
    public int nextSize(
            BatchWorkloadProfile profile,
            long estimatedTotal,
            int currentSize,
            ChunkFeedback feedback,
            Long remainingCount
    ) {
        int totalBased = initialSize(profile, estimatedTotal);
        long next = currentSize;
        if (feedback.failed()) {
            next = Math.max(profile.minItems(), currentSize / 2L);
        } else {
            long sizeByTime = feedback.itemCount() == 0 || feedback.durationMillis() == 0
                    ? profile.maxItems()
                    : profile.targetDurationMillis() * feedback.itemCount() / feedback.durationMillis();
            long sizeByMemory = feedback.itemCount() == 0 || feedback.payloadBytes() == 0
                    ? profile.maxItems()
                    : profile.memoryBudgetBytes() * feedback.itemCount() / feedback.payloadBytes();
            long feedbackLimit = Math.min(sizeByTime, sizeByMemory);
            if (feedback.durationMillis() < profile.targetDurationMillis() / 2
                    && feedback.payloadBytes() < profile.memoryBudgetBytes() / 2) {
                long growthStep = currentSize < totalBased
                        ? Math.max(1, currentSize / 4L)
                        : Math.max(1, currentSize / 10L);
                next = Math.min(feedbackLimit, currentSize + growthStep);
            } else if (feedback.durationMillis() > profile.targetDurationMillis()
                    || feedback.payloadBytes() > profile.memoryBudgetBytes()) {
                next = Math.min(feedbackLimit, Math.max(profile.minItems(), currentSize / 2L));
            } else {
                next = Math.min(feedbackLimit, currentSize);
            }
        }
        next = clamp(next, profile.minItems(), profile.maxItems());
        if (remainingCount != null) {
            next = Math.min(next, Math.max(1, remainingCount));
        }
        return Math.toIntExact(next);
    }

    private long divideCeil(long value, long divisor) {
        return (value + divisor - 1) / divisor;
    }

    private long clamp(long value, long minimum, long maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    /** 最近一个已提交 Chunk 的反馈。 */
    public record ChunkFeedback(int itemCount, long payloadBytes, long durationMillis, boolean failed) {
    }
}
