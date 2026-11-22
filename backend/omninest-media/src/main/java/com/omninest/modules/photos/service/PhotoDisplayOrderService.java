package com.omninest.modules.photos.service;

import com.omninest.modules.photos.domain.PhotoDisplayOrder;
import com.omninest.modules.photos.repository.PhotoDisplayOrderRepository;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 照片多视图自定义排序持久化服务。
 *
 * <p>将保存与删除封装在独立事务边界内，便于控制器在并发唯一键冲突或乐观锁冲突时
 * 干净地执行单次重试。</p>
 */
@Service
@RequiredArgsConstructor
public class PhotoDisplayOrderService {

    private final PhotoDisplayOrderRepository displayOrderRepository;

    @Transactional(rollbackFor = Exception.class)
    public List<UUID> saveDisplayOrder(UUID ownerUserId, String contextKey, List<UUID> dedupedPhotoIds) {
        PhotoDisplayOrder record = displayOrderRepository
                .findByOwnerUserIdAndContextKey(ownerUserId, contextKey)
                .orElseGet(() -> {
                    PhotoDisplayOrder created = new PhotoDisplayOrder();
                    created.setOwnerUserId(ownerUserId);
                    created.setContextKey(contextKey);
                    return created;
                });
        record.setOrderedPhotoIds(new ArrayList<>(dedupedPhotoIds));
        displayOrderRepository.saveAndFlush(record);
        return dedupedPhotoIds;
    }

    @Transactional(rollbackFor = Exception.class)
    public void deleteDisplayOrder(UUID ownerUserId, String contextKey) {
        displayOrderRepository.deleteByOwnerUserIdAndContextKey(ownerUserId, contextKey);
        displayOrderRepository.flush();
    }
}
