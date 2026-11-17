package com.omninest.modules.video.service;

/**
 * 自适应批次的内部工作负载画像。
 *
 * <p>这些边界保护事务、内存和数据库参数预算，不属于配置中心业务参数。</p>
 */
public enum BatchWorkloadProfile {
    DISCOVERY(32, 1024, 750, 4L * 1024 * 1024, 12),
    APPLY(8, 128, 1200, 2L * 1024 * 1024, 16),
    CLEANUP(32, 512, 900, 2L * 1024 * 1024, 8);

    private final int minItems;
    private final int maxItems;
    private final long targetDurationMillis;
    private final long memoryBudgetBytes;
    private final int bindColumnsPerItem;

    BatchWorkloadProfile(
            int minItems,
            int maxItems,
            long targetDurationMillis,
            long memoryBudgetBytes,
            int bindColumnsPerItem
    ) {
        this.minItems = minItems;
        this.maxItems = maxItems;
        this.targetDurationMillis = targetDurationMillis;
        this.memoryBudgetBytes = memoryBudgetBytes;
        this.bindColumnsPerItem = bindColumnsPerItem;
    }

    public int minItems() {
        return minItems;
    }

    public int maxItems() {
        return maxItems;
    }

    public long targetDurationMillis() {
        return targetDurationMillis;
    }

    public long memoryBudgetBytes() {
        return memoryBudgetBytes;
    }

    public int bindColumnsPerItem() {
        return bindColumnsPerItem;
    }
}
