package com.omninest.modules.video.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.common.user.UserDataPurgePort;
import com.omninest.modules.photos.event.PhotoIndexUserPurgeEvent;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.video.repository.MediaLibraryAccessRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 媒体模块的用户删除清理：影视库成员授权与照片共享索引残留。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MediaUserDataPurgeService implements UserDataPurgePort {

    private final MediaLibraryAccessRepository mediaLibraryAccessRepository;
    private final TaskDispatchService taskDispatchService;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void purgeUserData(UUID userId) {
        mediaLibraryAccessRepository.deleteByUserId(userId);
        // 照片索引是 Worker 独占写入的共享卷，请求进程不能直接删文档；
        // 与文件索引目录清理同口径，先落 Outbox，提交后由 Worker 执行。
        taskDispatchService.enqueue(
                userId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_INDEX_USER_PURGE_ROUTING_KEY,
                new PhotoIndexUserPurgeEvent(userId)
        );
        log.info("已清理媒体库用户授权并提交照片索引清理: userId={}", userId);
    }
}
