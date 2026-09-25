package com.omninest.modules.sync.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.sync.domain.SyncEvent;
import com.omninest.modules.sync.dto.SyncDtos.SyncBootstrapDto;
import com.omninest.modules.sync.dto.SyncDtos.SyncEventDto;
import com.omninest.modules.sync.dto.SyncDtos.SyncEventPageDto;
import com.omninest.modules.sync.dto.SyncDtos.SyncHeadDto;
import com.omninest.modules.sync.repository.SyncEventCheckpointRepository;
import com.omninest.modules.sync.repository.SyncEventRepository;
import java.time.Instant;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 提供用户同步游标初始化、增量补偿与高水位查询。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class SyncEventQueryService {

    static final int SCHEMA_VERSION = 1;
    static final String RETENTION_FLOOR_KEY = "retention_floor";

    private final SyncEventRepository syncEventRepository;
    private final SyncEventCheckpointRepository checkpointRepository;

    /**
     * 获取首次建立同步状态使用的全局高水位。
     *
     * @return 同步初始化数据
     */
    @Transactional(readOnly = true)
    public SyncBootstrapDto bootstrap() {
        return new SyncBootstrapDto(
                SCHEMA_VERSION,
                latestCursor(),
                retentionFloor(),
                Instant.now()
        );
    }

    /**
     * 按全局游标查询当前用户可见的同步事件。
     *
     * @param userId 当前用户标识
     * @param after 起始游标，不包含
     * @param limit 最大返回数量
     * @return 同步事件增量页
     */
    @Transactional(readOnly = true)
    public SyncEventPageDto events(UUID userId, long after, int limit) {
        validate(userId, after, limit);
        long latest = latestCursor();
        long floor = retentionFloor();
        if (after < floor || after > latest) {
            return new SyncEventPageDto(List.of(), latest, latest, false, true);
        }

        List<SyncEvent> fetched = syncEventRepository.findVisibleEvents(
                userId,
                after,
                latest,
                PageRequest.of(0, limit + 1)
        );
        boolean hasMore = fetched.size() > limit;
        List<SyncEvent> visible = hasMore ? fetched.subList(0, limit) : fetched;
        List<SyncEventDto> items = visible.stream().map(this::toDto).toList();
        long nextCursor = hasMore ? visible.get(visible.size() - 1).getSequenceNo() : latest;
        return new SyncEventPageDto(items, nextCursor, latest, hasMore, false);
    }

    /**
     * 获取同步链路轻量高水位。
     *
     * @return 当前高水位
     */
    @Transactional(readOnly = true)
    public SyncHeadDto head() {
        return new SyncHeadDto(SCHEMA_VERSION, latestCursor(), retentionFloor());
    }

    private void validate(UUID userId, long after, int limit) {
        if (userId == null) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "未认证");
        }
        if (after < 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "同步游标不能小于零");
        }
        if (limit < 1 || limit > com.omninest.common.api.PageClamps.MAX_SIZE) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "同步事件分页大小必须在 1 到 200 之间");
        }
    }

    private long latestCursor() {
        return syncEventRepository.findLatestSequenceNo();
    }

    private long retentionFloor() {
        return checkpointRepository.findByCheckpointKey(RETENTION_FLOOR_KEY)
                .map(checkpoint -> checkpoint.getSequenceNo())
                .orElse(0L);
    }

    private SyncEventDto toDto(SyncEvent event) {
        return new SyncEventDto(
                SCHEMA_VERSION,
                event.getId(),
                event.getSequenceNo(),
                event.getScope().name(),
                event.getResourceType(),
                event.getResourceId(),
                event.getAction().name(),
                event.getResourceVersion(),
                immutableHints(event.getPayload()),
                event.getCreatedAt()
        );
    }

    private Map<String, Object> immutableHints(Map<String, Object> hints) {
        if (hints == null || hints.isEmpty()) {
            return Map.of();
        }
        return Collections.unmodifiableMap(new LinkedHashMap<>(hints));
    }
}
