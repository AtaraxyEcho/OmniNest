package com.omninest.modules.sync.service;

import com.omninest.modules.sync.config.SyncEventProperties;
import com.omninest.modules.sync.domain.SyncEvent;
import com.omninest.modules.sync.repository.SyncEventRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理同步事件 Outbox 的数据库租约与发布状态。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class SyncOutboxStateService {

    private final SyncEventRepository syncEventRepository;
    private final SyncEventProperties properties;

    /**
     * 原子认领一批可发布事件并写入当前实例租约。
     *
     * @param now 当前时间
     * @return 已持有租约的事件快照
     */
    @Transactional(rollbackFor = Exception.class)
    public List<ClaimedSyncEvent> claimBatch(Instant now) {
        SyncEventProperties.Outbox outbox = properties.getOutbox();
        int batchSize = Math.max(1, Math.min(outbox.getBatchSize(), 500));
        Instant lockedUntil = now.plusSeconds(Math.max(1L, outbox.getLeaseSeconds()));
        String instanceId = outbox.getInstanceId();
        List<SyncEvent> events = syncEventRepository.findClaimableEvents(now, batchSize);
        events.forEach(event -> {
            event.setPublishStatus("PUBLISHING");
            event.setLockedBy(instanceId);
            event.setLockedUntil(lockedUntil);
        });
        syncEventRepository.flush();
        return events.stream().map(this::toClaimedEvent).toList();
    }

    /**
     * 批量将当前实例持有租约的事件标记为已发布，返回实际更新的行数。
     *
     * <p>行数少于入参数量说明有事件的租约在发布期间被其他实例接管，
     * 那些事件会由接管方重新置为终态，本实例不覆盖。</p>
     *
     * @param eventIds 本批发布成功的事件标识
     * @param publishedAt Broker 确认时间
     * @return 实际更新行数
     */
    @Transactional(rollbackFor = Exception.class)
    public int markPublishedBatch(Collection<UUID> eventIds, Instant publishedAt) {
        if (eventIds.isEmpty()) {
            return 0;
        }
        return syncEventRepository.markPublishedBatch(
                eventIds,
                properties.getOutbox().getInstanceId(),
                publishedAt
        );
    }

    /**
     * 记录发布失败并按尝试次数设置下一次可发布时间。
     *
     * @param event 已认领事件
     * @param failedAt 失败时间
     * @return 是否成功更新状态
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean markFailed(ClaimedSyncEvent event, Instant failedAt) {
        int attempts = event.publishAttempts() + 1;
        Instant availableAt = failedAt.plus(retryDelay(attempts));
        int updated = syncEventRepository.markPublishFailed(
                event.id(),
                properties.getOutbox().getInstanceId(),
                attempts,
                availableAt,
                failedAt
        );
        return updated == 1;
    }

    private Duration retryDelay(int attempts) {
        return switch (attempts) {
            case 1 -> Duration.ofSeconds(1);
            case 2 -> Duration.ofSeconds(5);
            case 3 -> Duration.ofSeconds(30);
            case 4 -> Duration.ofMinutes(2);
            default -> Duration.ofMinutes(10);
        };
    }

    private ClaimedSyncEvent toClaimedEvent(SyncEvent event) {
        return new ClaimedSyncEvent(
                event.getId(),
                event.getSequenceNo(),
                event.getRecipientUserId(),
                event.getScope(),
                event.getResourceType(),
                event.getResourceId(),
                event.getAction(),
                event.getResourceVersion(),
                immutableHints(event.getPayload()),
                event.getCreatedAt(),
                event.getPublishAttempts()
        );
    }

    private Map<String, Object> immutableHints(Map<String, Object> hints) {
        if (hints == null || hints.isEmpty()) {
            return Map.of();
        }
        return Collections.unmodifiableMap(new LinkedHashMap<>(hints));
    }
}
