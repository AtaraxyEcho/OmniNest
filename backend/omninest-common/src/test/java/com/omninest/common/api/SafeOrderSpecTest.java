package com.omninest.common.api;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * 任务排序列白名单测试。
 *
 * @author OmniNest
 */
class SafeOrderSpecTest {

    @Test
    void resolvesAllWhitelistedColumns() {
        for (SafeOrderSpec spec : SafeOrderSpec.values()) {
            assertThat(SafeOrderSpec.resolve(spec.column())).isEqualTo(spec);
        }
    }

    @Test
    void unknownColumnFallsBackToUpdatedAt() {
        assertThat(SafeOrderSpec.resolve("drop table")).isEqualTo(SafeOrderSpec.UPDATED_AT);
        assertThat(SafeOrderSpec.resolve(null)).isEqualTo(SafeOrderSpec.UPDATED_AT);
        assertThat(SafeOrderSpec.resolve("  ")).isEqualTo(SafeOrderSpec.UPDATED_AT);
    }
}
