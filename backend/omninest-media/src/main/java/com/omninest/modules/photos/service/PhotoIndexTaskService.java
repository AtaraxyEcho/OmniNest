package com.omninest.modules.photos.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.event.PhotoIndexEvent;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import com.omninest.modules.task.service.TaskDispatchService;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 照片搜索索引任务服务。
 *
 * <p>索引请求一律经 Outbox 投递给 Worker，由单进程写 Lucene：API 与 Worker 共挂
 * 同一索引卷时，API 内直接打开 {@code IndexWriter} 会与 Worker 抢 {@code write.lock}，
 * 写入被吞掉后表现为索引静默丢失。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class PhotoIndexTaskService {
    private final PhotoItemRepository photoItemRepository;
    private final PhotoTagRepository photoTagRepository;
    private final PhotoSearchIndexService photoSearchIndexService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final TaskDispatchService taskDispatchService;

    /**
     * 把指定照片同步到搜索索引：可见照片写入，回收站或生命周期中的照片移出索引。
     *
     * <p>仅由 Worker 侧消费调用。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     * @return 照片存在且处于可搜索状态时返回 true
     */
    public boolean index(UUID ownerUserId, UUID photoId) {
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId).orElse(null);
        if (photo == null) {
            return false;
        }
        if (photo.getDeletedAt() != null
                || !fileLifecycleGuard.isOwnedProcessable(ownerUserId, photo.getFileNodeId())) {
            photoSearchIndexService.deletePhoto(photoId);
            return false;
        }
        List<String> tags = photoTagRepository.findByOwnerUserIdAndPhotoId(ownerUserId, photoId)
                .stream()
                .map(PhotoTag::getTag)
                .toList();
        photoSearchIndexService.indexPhoto(
                photo.getId(),
                photo.getOwnerUserId(),
                photo.getTitle(),
                photo.getDescription(),
                tags
        );
        return true;
    }

    /**
     * 请求把照片重新同步进搜索索引。
     *
     * <p>投递走 Outbox，与标签等变更同一事务落库、提交后发布；索引载荷复用照片 ID
     * 作为任务标识。回收站进入/移出、批量打标签与单张增删标签都用同一入口，
     * 由消费侧按照片当前状态决定写入还是移除。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     */
    public void scheduleIndexAfterCommit(UUID ownerUserId, UUID photoId) {
        taskDispatchService.enqueue(
                photoId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.PHOTO_INDEX_ROUTING_KEY,
                new PhotoIndexEvent(photoId, ownerUserId)
        );
    }
}
