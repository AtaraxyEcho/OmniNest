package com.omninest.modules.file.service;

import com.omninest.modules.file.repository.FilePurgeEntryRepository;
import com.omninest.modules.user.port.PurgeHistoryRetention;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 物理删除清单的历史保留实现，供系统历史清理调度器分批回收已完成条目。
 *
 * <p>只清理 DELETED 与 NOT_FOUND 两类成功终态：FAILED 条目仍会被重试点亮，
 * PENDING 条目代表尚未执行完的删除计划，删掉就等于让对象永远留在桶里。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FilePurgeHistoryRetention implements PurgeHistoryRetention {

    private static final List<String> COMPLETED_STATUSES = List.of("DELETED", "NOT_FOUND");

    private final FilePurgeEntryRepository purgeEntryRepository;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public int deleteCompletedEntriesBefore(Instant cutoff, int batchSize) {
        List<UUID> ids = purgeEntryRepository.findIdsByStatusInAndCreatedAtBefore(
                COMPLETED_STATUSES, cutoff, PageRequest.of(0, Math.max(1, Math.min(batchSize, 5000))));
        if (ids.isEmpty()) {
            return 0;
        }
        purgeEntryRepository.deleteAllByIdInBatch(ids);
        return ids.size();
    }
}
