package com.omninest.modules.photos.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.domain.PhotoAlbum;
import com.omninest.modules.photos.repository.PhotoAlbumItemRepository;
import com.omninest.modules.photos.repository.PhotoAlbumRepository;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 照片行变更后的统一收尾副作用：相册落库计数重算、逐张同步事件、搜索索引投递、看板缓存失效。
 *
 * <p>这些副作用必须成组发生，历史上散落在各业务方法里容易漏项（如批量打标签不投索引、
 * 移入回收站不重算相册计数）。相册计数与详情列表都以「活动照片」为准：照片进回收站不删
 * 相册关联条目，不在此重算就会让卡片数量长期高于点开后的实际数量。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class PhotoChangeSideEffects {

    private static final String DASHBOARD_CACHE_KEY = "omninest:dashboard:photo:";

    private final PhotoAlbumRepository albumRepository;
    private final PhotoAlbumItemRepository albumItemRepository;
    private final PhotoIndexTaskService photoIndexTaskService;
    private final MediaSyncEventService syncEventService;
    private final ReadThroughCache readThroughCache;

    /**
     * 记录单张照片的同步事件，供跨端资料同步刷新。
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoId 照片 ID
     * @param action 变更动作
     * @param version 资源版本，可为空
     * @param hints 非敏感刷新提示
     */
    public void recordPhotoEvent(
            UUID ownerUserId,
            UUID photoId,
            SyncAction action,
            Long version,
            Map<String, Object> hints
    ) {
        syncEventService.record(
                ownerUserId,
                SyncScope.PHOTOS,
                "PHOTO_ITEM",
                photoId.toString(),
                action,
                version,
                hints
        );
    }

    /**
     * 失效当前用户的相册看板缓存。
     *
     * @param ownerUserId 所有者用户 ID
     */
    public void invalidateDashboardCache(UUID ownerUserId) {
        readThroughCache.invalidate(DASHBOARD_CACHE_KEY + ownerUserId);
    }

    /**
     * 重算包含指定照片的相册计数。
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoIds 变更涉及的照片 ID
     */
    public void refreshAlbumCountsForPhotos(UUID ownerUserId, List<UUID> photoIds) {
        if (photoIds.isEmpty()) {
            return;
        }
        List<UUID> albumIds = albumItemRepository.findAlbumIdsByPhotoIdIn(photoIds);
        if (albumIds.isEmpty()) {
            return;
        }
        List<PhotoAlbum> albums = albumRepository.findAllByIdInAndOwnerUserId(albumIds, ownerUserId);
        Map<UUID, Long> counts = albumItemRepository.countActivePhotosByAlbumIds(albumIds).stream()
                .collect(Collectors.toMap(row -> (UUID) row[0], row -> (Long) row[1]));
        for (PhotoAlbum album : albums) {
            album.setPhotoCount(counts.getOrDefault(album.getId(), 0L).intValue());
        }
        if (!albums.isEmpty()) {
            albumRepository.saveAll(albums);
        }
    }

    /**
     * 照片集合被移入或移出回收站后的成组收尾：相册计数、同步事件、索引刷新与看板失效。
     *
     * <p>索引刷新按照片逐个投递，由单写进程消费；看板缓存整批只失效一次。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param photoIds 变更后的照片 ID
     * @param action 同步动作
     * @param hints 非敏感刷新提示
     */
    public void afterTrashChange(
            UUID ownerUserId,
            List<UUID> photoIds,
            SyncAction action,
            Map<String, Object> hints
    ) {
        if (photoIds.isEmpty()) {
            return;
        }
        refreshAlbumCountsForPhotos(ownerUserId, photoIds);
        photoIds.forEach(photoId -> recordPhotoEvent(ownerUserId, photoId, action, null, hints));
        photoIds.forEach(photoId -> photoIndexTaskService.scheduleIndexAfterCommit(ownerUserId, photoId));
        invalidateDashboardCache(ownerUserId);
    }
}
