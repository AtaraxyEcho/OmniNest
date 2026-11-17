package com.omninest.modules.video.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.omninest.modules.video.service.AdaptiveChunkPolicy.ChunkFeedback;
import org.junit.jupiter.api.Test;

class AdaptiveChunkPolicyTest {

    private final AdaptiveChunkPolicy policy = new AdaptiveChunkPolicy();

    @Test
    void initialSizeGrowsWithTotalWithinWorkloadBounds() {
        int small = policy.initialSize(BatchWorkloadProfile.DISCOVERY, 10);
        int medium = policy.initialSize(BatchWorkloadProfile.DISCOVERY, 10_000);
        int large = policy.initialSize(BatchWorkloadProfile.DISCOVERY, 100_000);

        assertEquals(BatchWorkloadProfile.DISCOVERY.minItems(), small);
        assertTrue(medium >= small);
        assertTrue(large > medium);
        assertTrue(large <= BatchWorkloadProfile.DISCOVERY.maxItems());
    }

    @Test
    void fastStableChunkGrowsGradually() {
        int next = policy.nextSize(
                BatchWorkloadProfile.APPLY,
                10_000,
                32,
                new ChunkFeedback(32, 32_000, 200, false),
                5_000L
        );

        assertTrue(next > 32);
        assertTrue(next <= 40);
    }

    @Test
    void failedChunkBacksOffImmediately() {
        int next = policy.nextSize(
                BatchWorkloadProfile.APPLY,
                10_000,
                64,
                new ChunkFeedback(20, 80_000, 400, true),
                5_000L
        );

        assertEquals(32, next);
    }

    @Test
    void finalChunkUsesRemainingCount() {
        int next = policy.nextSize(
                BatchWorkloadProfile.DISCOVERY,
                100_000,
                512,
                new ChunkFeedback(512, 200_000, 300, false),
                7L
        );

        assertEquals(7, next);
    }
}
