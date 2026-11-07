package com.omninest.modules.configcenter.service;

import com.omninest.modules.configcenter.repository.ConfigHistoryRepository;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;

/**
 * 配置历史最近版本保护与分批清理测试。
 *
 * @author OmniNest
 */
class ConfigHistoryRetentionServiceTest {
    private final ConfigHistoryRepository repository = Mockito.mock(ConfigHistoryRepository.class);
    private final ConfigHistoryRetentionService service = new ConfigHistoryRetentionService(repository);

    @Test
    void deleteExpiredBatchDeletesCandidatesReturnedByRetentionQuery() {
        Instant cutoff = Instant.parse("2025-07-25T00:00:00Z");
        UUID expiredA = UUID.randomUUID();
        UUID expiredB = UUID.randomUUID();
        Mockito.when(repository.findRetentionCandidateIds(cutoff, 2, 2))
                .thenReturn(List.of(expiredA, expiredB));

        int deleted = service.deleteExpiredBatch(cutoff, 2, 2);

        Assertions.assertThat(deleted).isEqualTo(2);
        Mockito.verify(repository).deleteAllByIdInBatch(List.of(expiredA, expiredB));
    }

    @Test
    void deleteExpiredBatchKeepsOnlyAvailableHistoryAsRollbackBaseline() {
        Instant cutoff = Instant.parse("2025-07-25T00:00:00Z");
        Mockito.when(repository.findRetentionCandidateIds(
                ArgumentMatchers.eq(cutoff),
                ArgumentMatchers.eq(20),
                ArgumentMatchers.anyInt()
        )).thenReturn(List.of());

        int deleted = service.deleteExpiredBatch(cutoff, 20, 500);

        Assertions.assertThat(deleted).isZero();
        Mockito.verify(repository, Mockito.never()).deleteAllByIdInBatch(ArgumentMatchers.anyList());
    }

    @Test
    void deleteExpiredBatchClampsRetentionAndBatchBounds() {
        Instant cutoff = Instant.parse("2025-07-25T00:00:00Z");
        Mockito.when(repository.findRetentionCandidateIds(cutoff, 1, 5000))
                .thenReturn(List.of());

        service.deleteExpiredBatch(cutoff, 0, 10_000);

        Mockito.verify(repository).findRetentionCandidateIds(cutoff, 1, 5000);
    }
}
