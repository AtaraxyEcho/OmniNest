package com.omninest.modules.sync.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.sync.domain.SyncEvent;
import com.omninest.modules.sync.repository.SyncEventRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 将业务变更持久化为用户同步事件。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class PersistentUserSyncEventRecorder implements UserSyncEventRecorder {

    private static final int MAX_RESOURCE_TYPE_LENGTH = 64;
    private static final int MAX_RESOURCE_ID_LENGTH = 128;

    private final SyncEventRepository syncEventRepository;

    /**
     * 在调用方事务内保存待发布事件。
     *
     * @param command 同步事件命令
     * @return 事件标识
     */
    @Override
    @Transactional(propagation = Propagation.MANDATORY, rollbackFor = Exception.class)
    public UUID record(SyncEventCommand command) {
        SyncEvent event = toEntity(command);
        syncEventRepository.save(event);
        return event.getId();
    }

    /**
     * 广播型事件一次落库：收件人数量与用户规模同阶，逐条 insert 会把一次管理
     * 操作的写入放大到与用户数成正比。
     */
    @Override
    @Transactional(propagation = Propagation.MANDATORY, rollbackFor = Exception.class)
    public List<UUID> recordAll(List<SyncEventCommand> commands) {
        if (commands == null || commands.isEmpty()) {
            return List.of();
        }
        List<SyncEvent> events = commands.stream().map(this::toEntity).toList();
        syncEventRepository.saveAll(events);
        return events.stream().map(SyncEvent::getId).toList();
    }

    private SyncEvent toEntity(SyncEventCommand command) {
        validate(command);
        SyncEvent event = new SyncEvent();
        event.setId(UUID.randomUUID());
        event.setRecipientUserId(command.recipientUserId());
        event.setScope(command.scope());
        event.setResourceType(command.resourceType().trim());
        event.setResourceId(normalizeResourceId(command.resourceId()));
        event.setAction(command.action());
        event.setResourceVersion(command.resourceVersion());
        event.setPayload(command.hints() == null
                ? new LinkedHashMap<>()
                : new LinkedHashMap<>(command.hints()));
        event.setPublishStatus("PENDING");
        event.setPublishAttempts(0);
        return event;
    }

    private void validate(SyncEventCommand command) {
        if (command == null
                || command.recipientUserId() == null
                || command.scope() == null
                || command.action() == null
                || command.resourceType() == null
                || command.resourceType().isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "同步事件参数不完整");
        }
        String resourceType = command.resourceType().trim();
        if (resourceType.length() > MAX_RESOURCE_TYPE_LENGTH) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "同步资源类型长度超限");
        }
        if (command.resourceId() != null
                && command.resourceId().trim().length() > MAX_RESOURCE_ID_LENGTH) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "同步资源标识长度超限");
        }
    }

    private String normalizeResourceId(String resourceId) {
        if (resourceId == null || resourceId.isBlank()) {
            return null;
        }
        return resourceId.trim();
    }
}
