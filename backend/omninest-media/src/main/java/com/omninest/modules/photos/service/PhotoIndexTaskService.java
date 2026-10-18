package com.omninest.modules.photos.service;

import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 照片搜索索引任务服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoIndexTaskService {
    private final PhotoItemRepository photoItemRepository;
    private final PhotoTagRepository photoTagRepository;
    private final PhotoSearchIndexService photoSearchIndexService;
    private final FileLifecycleGuard fileLifecycleGuard;

    /**
     * 为当前用户的指定照片写入搜索索引。
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     * @return 照片存在并完成索引时返回 true
     */
    public boolean index(UUID ownerUserId, UUID photoId) {
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId).orElse(null);
        if (photo == null) {
            return false;
        }
        if (!fileLifecycleGuard.isOwnedProcessable(ownerUserId, photo.getFileNodeId())) {
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
     * 在事务提交后刷新单张照片索引；无活动事务时立即刷新。
     *
     * <p>索引写入不受数据库事务约束：提交前写索引会让回滚事务留下幽灵文档，
     * 因此标签等变更必须在 afterCommit 触发，失败由管理员 PHOTO_INDEX 批量任务兜底。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     */
    public void scheduleIndexAfterCommit(UUID ownerUserId, UUID photoId) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            indexQuietly(ownerUserId, photoId);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                indexQuietly(ownerUserId, photoId);
            }
        });
    }

    private void indexQuietly(UUID ownerUserId, UUID photoId) {
        try {
            index(ownerUserId, photoId);
        } catch (RuntimeException exception) {
            log.warn("照片索引刷新失败: photoId={}", photoId, exception);
        }
    }
}
