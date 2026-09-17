package com.omninest.modules.photos.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.service.FileBusinessReference;
import com.omninest.modules.file.service.FilePurgeParticipant;
import com.omninest.modules.file.service.PurgeContext;
import com.omninest.modules.file.service.PurgeContributionWriter;
import com.omninest.modules.media.service.MediaFileVisibilitySyncParticipant;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.domain.PhotoAlbum;
import com.omninest.modules.photos.domain.PhotoEditVersion;
import com.omninest.modules.photos.domain.PhotoFace;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.repository.PhotoAlbumItemRepository;
import com.omninest.modules.photos.repository.PhotoAlbumRepository;
import com.omninest.modules.photos.repository.PhotoEditVersionRepository;
import com.omninest.modules.photos.repository.PhotoFaceRepository;
import com.omninest.modules.photos.repository.PhotoFavoriteRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件删除触发的照片业务数据清理服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoFileCleanupService implements
        FilePurgeParticipant,
        MediaFileVisibilitySyncParticipant {
    private static final String MODULE = "PHOTOS";
    private static final String RESOURCE_TYPE = "PHOTO_ITEM";
    private final PhotoItemRepository itemRepository;
    private final PhotoAlbumItemRepository albumItemRepository;
    private final PhotoFavoriteRepository favoriteRepository;
    private final PhotoAlbumRepository albumRepository;
    private final PhotoTagRepository tagRepository;
    private final PhotoEditVersionRepository editVersionRepository;
    private final PhotoFaceRepository faceRepository;
    private final PhotoSearchIndexService photoSearchIndexService;
    private final MediaSyncEventService syncEventService;
    private final ReadThroughCache readThroughCache;
    private final PhotoFaceClusterMaintenanceService clusterMaintenanceService;

    /**
     * 查询目标文件的照片条目引用。
     *
     * @param context 删除上下文
     * @return 照片条目引用
     */
    @Override
    @Transactional(readOnly = true)
    public List<FileBusinessReference> findBusinessReferences(PurgeContext context) {
        return itemRepository
                .findByFileNodeIdIn(context.fileNodeIds())
                .stream()
                .map(photo -> new FileBusinessReference(
                        MODULE,
                        RESOURCE_TYPE,
                        photo.getId(),
                        photo.getFileNodeId()
                ))
                .toList();
    }

    /**
     * 贡献照片封面和全部非破坏性编辑版本文件。
     *
     * @param context 删除上下文
     * @param writer 资源写入器
     */
    @Override
    @Transactional(readOnly = true)
    public void contribute(PurgeContext context, PurgeContributionWriter writer) {
        List<PhotoItem> photos = itemRepository
                .findByFileNodeIdIn(context.fileNodeIds());
        if (photos.isEmpty()) {
            return;
        }
        List<UUID> photoIds = photos.stream().map(PhotoItem::getId).toList();
        writer.addFileNodeIds(photos.stream()
                .map(PhotoItem::getCoverFileId)
                .filter(Objects::nonNull)
                .toList());
        writer.addFileNodeIds(editVersionRepository.findByPhotoIdIn(photoIds).stream()
                .map(PhotoEditVersion::getFileId)
                .toList());
    }

    /**
     * 幂等清理照片业务记录并保留空相册。
     *
     * @param context 删除上下文
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void finalizePurge(PurgeContext context) {
        List<UUID> fileNodeIds = List.copyOf(context.fileNodeIds());
        Map<UUID, List<PhotoItem>> photosByOwner = itemRepository.findByFileNodeIdIn(fileNodeIds).stream()
                .collect(Collectors.groupingBy(
                        PhotoItem::getOwnerUserId,
                        LinkedHashMap::new,
                        Collectors.toList()
                ));
        photosByOwner.forEach(this::deletePhotoRows);
        clearDanglingFileReferences(fileNodeIds);
    }

    /**
     * 处理文件移入回收站事件。
     *
     * @param event 文件节点软删除事件
     */
    @EventListener
    @Transactional(rollbackFor = Exception.class)
    public void handleFileNodesSoftDeleted(FileNodesSoftDeletedEvent event) {
        if (event.fileNodeIds() == null || event.fileNodeIds().isEmpty()) {
            return;
        }
        log.debug("文件移入回收站，保留照片业务数据: ownerUserId={}, fileNodeCount={}",
                event.ownerUserId(), event.fileNodeIds().size());
    }

    /**
     * 使引用指定文件节点的照片库缓存失效。
     *
     * @param fileNodeIds 文件节点 ID
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void invalidateFileVisibility(Collection<UUID> fileNodeIds) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return;
        }
        itemRepository.findByFileNodeIdIn(fileNodeIds).stream()
                .map(PhotoItem::getOwnerUserId)
                .filter(Objects::nonNull)
                .collect(Collectors.toCollection(LinkedHashSet::new))
                .forEach(ownerUserId -> syncEventService.invalidate(
                        ownerUserId,
                        SyncScope.PHOTOS,
                        "PHOTO_LIBRARY",
                        Map.of("reason", "FILE_VISIBILITY_CHANGED")
                ));
    }

    private void deletePhotoRows(UUID ownerUserId, List<PhotoItem> photos) {
        if (photos.isEmpty()) {
            return;
        }
        List<UUID> photoIds = photos.stream().map(PhotoItem::getId).toList();
        tagRepository.deleteByOwnerUserIdAndPhotoIdIn(ownerUserId, photoIds);
        editVersionRepository.deleteByPhotoIdIn(photoIds);
        List<PhotoFace> removedFaces = faceRepository.findByPhotoIdIn(photoIds);
        faceRepository.deleteAll(removedFaces);
        clusterMaintenanceService.onFacesRemoved(ownerUserId, removedFaces);
        List<UUID> affectedAlbumIds = albumItemRepository.findAlbumIdsByPhotoIdIn(photoIds);
        albumItemRepository.deleteByPhotoIdIn(photoIds);
        favoriteRepository.deleteByPhotoIdIn(photoIds);
        photoSearchIndexService.deletePhotos(photoIds);
        itemRepository.deleteAllInBatch(photos);
        readThroughCache.invalidate("omninest:dashboard:photo:" + ownerUserId);
        refreshAffectedAlbums(ownerUserId, affectedAlbumIds);
        for (PhotoItem photo : photos) {
            syncEventService.record(
                    ownerUserId,
                    SyncScope.PHOTOS,
                    "PHOTO_ITEM",
                    photo.getId().toString(),
                    SyncAction.DELETED,
                    photo.getVersion(),
                    Map.of()
            );
        }
    }

    private void refreshAffectedAlbums(UUID ownerUserId, List<UUID> affectedAlbumIds) {
        if (affectedAlbumIds.isEmpty()) {
            return;
        }
        List<PhotoAlbum> albums = albumRepository
                .findAllByIdInAndOwnerUserId(affectedAlbumIds, ownerUserId);
        for (PhotoAlbum album : albums) {
            long count = albumItemRepository.countByAlbumId(album.getId());
            album.setPhotoCount((int) count);
        }
        if (!albums.isEmpty()) {
            albumRepository.saveAll(albums);
        }
    }

    private void clearDanglingFileReferences(List<UUID> deletedFileIds) {
        Set<UUID> fileIds = new HashSet<>(deletedFileIds);
        itemRepository.findByCoverFileIdIn(fileIds)
                .forEach(photo -> photo.setCoverFileId(null));
    }
}
