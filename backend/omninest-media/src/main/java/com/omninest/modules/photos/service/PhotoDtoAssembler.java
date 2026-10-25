package com.omninest.modules.photos.service;

import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoItemDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoListItemDto;
import com.omninest.modules.photos.repository.PhotoActiveFileProjection;
import com.omninest.modules.photos.repository.PhotoFavoriteRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoListItemProjection;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 照片 DTO 组装：把列表投影与实体批量映射为对外对象，并统一签发媒体地址。
 *
 * <p>从 {@link PhotoLibraryService} 拆出后，浏览、相册与搜索共用同一份字段口径，
 * 也避免单文件继续膨胀。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class PhotoDtoAssembler {

    private final PhotoItemRepository photoItemRepository;
    private final PhotoFavoriteRepository favoriteRepository;
    private final PhotoTagRepository photoTagRepository;
    private final FileQueryService fileQueryService;

    /**
     * 批量映射照片实体为完整 DTO，避免循环查询标签与封面 URL。
     */
    public List<PhotoItemDto> mapPhotoItemDtos(
            UUID ownerUserId,
            List<PhotoItem> items,
            Set<UUID> favoriteIds
    ) {
        if (items == null || items.isEmpty()) {
            return List.of();
        }
        List<UUID> ids = items.stream().map(PhotoItem::getId).toList();
        Map<UUID, List<String>> tagsByPhoto = photoTagRepository
                .findByOwnerUserIdAndPhotoIdIn(ownerUserId, ids)
                .stream()
                .collect(Collectors.groupingBy(
                        PhotoTag::getPhotoId,
                        Collectors.mapping(PhotoTag::getTag, Collectors.toList())
                ));
        Map<UUID, String> coverUrls = resolveDownloadUrls(
                ownerUserId,
                items.stream()
                        .map(PhotoItem::getCoverFileId)
                        .filter(Objects::nonNull)
                        .toList());
        // 完整 DTO 的调用方（标签分页、仪表盘、收藏、公开相册）拿到的是同一个对象契约，
        // 原图与动态视频地址不能只在详情接口出现。
        Map<UUID, String> sourceUrls = resolveSourceUrls(ownerUserId, items);
        Map<UUID, String> motionVideoUrls = resolveMotionVideoUrls(ownerUserId, items);
        return items.stream()
                .map(item -> PhotoItemDto.fromEntity(
                        item,
                        urlOrNull(coverUrls, item.getCoverFileId()),
                        favoriteIds.contains(item.getId()),
                        tagsByPhoto.getOrDefault(item.getId(), List.of()),
                        urlOrNull(sourceUrls, item.activeOrSourceFileId()),
                        null,
                        urlOrNull(motionVideoUrls, item.getMotionVideoFileNodeId())
                ))
                .toList();
    }

    /**
     * 批量映射列表投影：标签、收藏、封面与原图地址各查一次，不随行数放大。
     */
    public List<PhotoListItemDto> mapListItems(
            UUID ownerUserId,
            List<? extends PhotoListItemProjection> projections,
            boolean favoritePage
    ) {
        List<UUID> photoIds = projections.stream()
                .map(PhotoListItemProjection::getId)
                .toList();
        Set<UUID> favoriteIds = favoritePage || photoIds.isEmpty()
                ? Set.copyOf(photoIds)
                : Set.copyOf(favoriteRepository.findPhotoIdsByOwnerUserIdAndPhotoIdIn(ownerUserId, photoIds));
        Map<UUID, List<String>> tagsByPhoto = photoIds.isEmpty()
                ? Map.of()
                : photoTagRepository.findByOwnerUserIdAndPhotoIdIn(ownerUserId, photoIds).stream()
                        .collect(Collectors.groupingBy(
                                PhotoTag::getPhotoId,
                                Collectors.mapping(PhotoTag::getTag, Collectors.toList())
                        ));
        Map<UUID, String> coverUrls = resolveDownloadUrls(
                ownerUserId,
                projections.stream()
                        .map(PhotoListItemProjection::getCoverFileId)
                        .filter(Objects::nonNull)
                        .toList());
        // 原图地址同样批量签发：逐行 createDownloadUrl 每张照片都要两次单行查询加一次
        // 签名运算，一屏 200 张就是数百次往返，而列表接口与详情共用同一份投影。
        // 已编辑的照片要把地址指向编辑产物，否则详情页与幻灯片的「大图」仍是未编辑原图。
        Map<UUID, UUID> activeFileByPhoto = photoIds.isEmpty()
                ? Map.of()
                : photoItemRepository.findActiveFileIds(ownerUserId, photoIds).stream()
                        .collect(Collectors.toMap(
                                PhotoActiveFileProjection::getPhotoId,
                                PhotoActiveFileProjection::getActiveFileId
                        ));
        Map<UUID, String> sourceUrls = resolveDownloadUrls(
                ownerUserId,
                projections.stream()
                        .map(item -> {
                            UUID activeFileId = activeFileByPhoto.get(item.getId());
                            return activeFileId != null ? activeFileId : item.getFileNodeId();
                        })
                        .filter(Objects::nonNull)
                        .toList());
        return projections.stream().map(item -> new PhotoListItemDto(
                item.getId(),
                item.getFileNodeId(),
                item.getTitle(),
                item.getDescription(),
                item.getWidth(),
                item.getHeight(),
                item.getOrientation(),
                item.getDateTaken(),
                item.getGpsLatitude() == null ? null : item.getGpsLatitude().doubleValue(),
                item.getGpsLongitude() == null ? null : item.getGpsLongitude().doubleValue(),
                item.getGpsLocation(),
                item.getFormat(),
                item.getFileSize(),
                urlOrNull(coverUrls, item.getCoverFileId()),
                urlOrNull(sourceUrls, activeFileByPhoto.getOrDefault(item.getId(), item.getFileNodeId())),
                item.getMetadataStatus(),
                favoriteIds.contains(item.getId()),
                item.getCreatedAt(),
                tagsByPhoto.getOrDefault(item.getId(), List.of()),
                item.getMotionState()
        )).toList();
    }

    /**
     * 将轻量列表投影转为兼容旧接口的完整照片对象。
     */
    public PhotoItemDto toLegacyPhotoItem(PhotoListItemDto item) {
        return new PhotoItemDto(
                item.id(),
                item.fileNodeId(),
                item.title(),
                item.description(),
                item.width(),
                item.height(),
                item.orientation(),
                item.dateTaken(),
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                item.gpsLatitude(),
                item.gpsLongitude(),
                item.gpsLocation(),
                item.format(),
                item.fileSize(),
                item.coverUrl(),
                null,
                item.metadataStatus(),
                item.favorite(),
                item.createdAt(),
                item.tags(),
                Map.of(),
                null,
                item.motionState(),
                null,
                false
        );
    }

    public Set<UUID> favoriteIdsFor(UUID ownerUserId, List<UUID> photoIds) {
        if (photoIds == null || photoIds.isEmpty()) {
            return Set.of();
        }
        return Set.copyOf(
                favoriteRepository.findPhotoIdsByOwnerUserIdAndPhotoIdIn(ownerUserId, photoIds));
    }

    /**
     * 批量解析文件下载地址，避免列表场景逐行回查文件节点与签名。
     *
     * <p>批量签发会跳过缺失、已删除或非文件节点，未命中即无地址。</p>
     */
    public Map<UUID, String> resolveDownloadUrls(UUID ownerUserId, Collection<UUID> fileIds) {
        if (fileIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, String> result = new LinkedHashMap<>();
        fileQueryService
                .createDownloadUrls(ownerUserId, fileIds)
                .forEach((fileId, dto) -> result.put(fileId, dto.downloadUrl()));
        return result;
    }

    /**
     * 批量签发原图地址：已编辑照片指向编辑产物，未编辑照片指向原文件。
     */
    Map<UUID, String> resolveSourceUrls(UUID ownerUserId, List<PhotoItem> items) {
        return resolveDownloadUrls(
                ownerUserId,
                items.stream()
                        .map(PhotoItem::activeOrSourceFileId)
                        .filter(Objects::nonNull)
                        .toList());
    }

    /**
     * 批量签发动态照片的运动视频地址；仅 READY 状态持有派生节点。
     */
    Map<UUID, String> resolveMotionVideoUrls(UUID ownerUserId, List<PhotoItem> items) {
        return resolveDownloadUrls(
                ownerUserId,
                items.stream()
                        .filter(item -> PhotoMotionVideoService.STATE_READY.equals(item.getMotionState()))
                        .map(PhotoItem::getMotionVideoFileNodeId)
                        .filter(Objects::nonNull)
                        .toList());
    }

    /// 文件 ID 为空（封面派生未完成/失败）或映射未命中时返回 null；
    /// Map.of() 不可变映射对 null 键 get() 直接抛 NPE（D-012）。
    private String urlOrNull(Map<UUID, String> urls, UUID fileId) {
        if (fileId == null) {
            return null;
        }
        return urls.get(fileId);
    }
}
