package com.omninest.modules.media.service;

import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件可见性变化后的媒体同步失效编排服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MediaFileVisibilitySyncService {

    private final List<MediaFileVisibilitySyncParticipant> participants;

    /**
     * 文件进入回收站后通知各媒体模块刷新可见性。
     *
     * @param event 文件软删除事件
     */
    @EventListener
    @Transactional(propagation = Propagation.MANDATORY)
    public void handleSoftDeleted(FileNodesSoftDeletedEvent event) {
        participants.forEach(participant -> participant.invalidateFileVisibility(event.fileNodeIds()));
    }

    /**
     * 文件恢复后通知各媒体模块刷新可见性。
     *
     * @param event 文件恢复事件
     */
    @EventListener
    @Transactional(propagation = Propagation.MANDATORY)
    public void handleRestored(FileNodesRestoredEvent event) {
        participants.forEach(participant -> participant.invalidateFileVisibility(event.fileNodeIds()));
    }
}
