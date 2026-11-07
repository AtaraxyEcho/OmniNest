package com.omninest.modules.configcenter.service;

import com.omninest.modules.configcenter.repository.ConfigHistoryRepository;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 按配置键保护最近版本并分批清理过期配置历史。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class ConfigHistoryRetentionService {

    private final ConfigHistoryRepository configHistoryRepository;

    /**
     * 删除一批超过保留时间且不属于最近保护版本的配置历史。
     *
     * @param cutoff 截止时间
     * @param minimumVersions 每个配置键最少保留版本数
     * @param batchSize 单批删除数量
     * @return 删除记录数
     */
    @Transactional(rollbackFor = Exception.class)
    public int deleteExpiredBatch(Instant cutoff, int minimumVersions, int batchSize) {
        int normalizedMinimumVersions = Math.max(1, Math.min(minimumVersions, 100));
        int normalizedBatchSize = Math.max(1, Math.min(batchSize, 5000));
        // 一次取回整批候选：逐配置键"先查保护集、再查过期集"会让查询次数随键数量线性增长，
        // 而分区排名本来就能在库内一次算完。
        List<UUID> candidateIds = configHistoryRepository.findRetentionCandidateIds(
                cutoff,
                normalizedMinimumVersions,
                normalizedBatchSize
        );
        if (candidateIds.isEmpty()) {
            return 0;
        }
        configHistoryRepository.deleteAllByIdInBatch(candidateIds);
        return candidateIds.size();
    }
}
