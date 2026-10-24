package com.omninest.modules.sync.service;

import com.omninest.modules.sync.config.SyncEventProperties;
import java.time.Instant;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * 同步事件 Outbox 调度器。
 *
 * <p>所有运行角色都会轮询：worker 与 scheduler 写入的同步事件不能依赖 api 实例派发。
 * 认领使用 {@code FOR UPDATE SKIP LOCKED} 与实例租约，多实例并发安全。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class SyncOutboxDispatcher {

    private final SyncOutboxStateService stateService;
    private final RabbitSyncEventPublisher publisher;
    private final SyncEventProperties properties;

    /**
     * 定期认领并发布一批同步事件。
     */
    @Scheduled(fixedDelayString = "${omninest.sync.outbox.interval-millis:500}")
    public void dispatch() {
        if (!properties.getOutbox().isEnabled()) {
            return;
        }
        List<ClaimedSyncEvent> events = stateService.claimBatch(Instant.now());
        events.forEach(this::publishOne);
    }

    private void publishOne(ClaimedSyncEvent event) {
        Instant publishedAt = Instant.now();
        try {
            publisher.publish(event, publishedAt);
            if (!stateService.markPublished(event.id(), publishedAt)) {
                log.warn("同步事件发布成功但租约状态已变化: eventId={}", event.id());
            }
        } catch (RuntimeException ex) {
            boolean updated = stateService.markFailed(event, Instant.now());
            log.warn(
                    "同步事件发布失败: eventId={}, sequenceNo={}, stateUpdated={}, message={}",
                    event.id(),
                    event.sequenceNo(),
                    updated,
                    ex.getMessage()
            );
        }
    }
}
