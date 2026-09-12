package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.ResourceShareLinkDto;
import com.omninest.modules.file.dto.ShareAccessSessionDto;
import com.omninest.modules.file.service.ResourceShareLinkService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.domain.PhotoAlbum;
import com.omninest.modules.photos.domain.PhotoAlbumItem;
import com.omninest.modules.photos.dto.PhotoDtos.CreateAlbumRequest;
import com.omninest.modules.photos.dto.PhotoDtos.CreateAlbumShareRequest;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoAlbumDetailDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoAlbumDto;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoItemDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoShareLinkDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoSharedAlbumDto;
import com.omninest.modules.photos.repository.PhotoAlbumItemRepository;
import com.omninest.modules.photos.repository.PhotoAlbumRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 照片相册服务，提供相册增删改查及照片管理功能。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoAlbumService {

    private static final int DEFAULT_PAGE_SIZE = 50;
    private static final int MAX_PAGE_SIZE = 100;

    private final PhotoAlbumRepository albumRepository;
    private final PhotoAlbumItemRepository albumItemRepository;
    private final PhotoItemRepository photoItemRepository;
    private final PhotoLibraryService libraryService;
    private final ResourceShareLinkService resourceShareLinkService;
    private final MediaSyncEventService syncEventService;

    /**
     * 查询用户所有相册，按更新时间倒序
     */
    @Transactional(readOnly = true)
    public List<PhotoAlbumDto> listAlbums(UUID ownerUserId) {
        return albumRepository.findByOwnerUserIdOrderByUpdatedAtDesc(ownerUserId)
                .stream()
                .map(this::toDto)
                .toList();
    }

    /**
     * 创建新相册
     */
    @Transactional(rollbackFor = Exception.class)
    public PhotoAlbumDto createAlbum(UUID ownerUserId, CreateAlbumRequest request) {
        PhotoAlbum album = new PhotoAlbum();
        album.setOwnerUserId(ownerUserId);
        album.setName(request.name().trim());
        album.setDescription(request.description());
        PhotoAlbum saved = albumRepository.save(album);
        recordAlbumEvent(ownerUserId, saved, SyncAction.CREATED);
        return toDto(saved);
    }

    /**
     * 更新相册名称和描述
     */
    @Transactional(rollbackFor = Exception.class)
    public PhotoAlbumDto updateAlbum(UUID ownerUserId, UUID albumId, CreateAlbumRequest request) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        album.setName(request.name().trim());
        album.setDescription(request.description());
        PhotoAlbum saved = albumRepository.save(album);
        recordAlbumEvent(ownerUserId, saved, SyncAction.UPDATED);
        return toDto(saved);
    }

    /**
     * 删除相册及其所有关联条目
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteAlbum(UUID ownerUserId, UUID albumId) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        List<PhotoAlbumItem> items = albumItemRepository.findByOwnerUserIdAndAlbumIdOrderBySortOrderAsc(ownerUserId, albumId);
        albumItemRepository.deleteAll(items);
        albumRepository.delete(album);
        recordAlbumEvent(ownerUserId, album, SyncAction.DELETED);
    }

    /**
     * 查询相册详情：相册元信息 + 首页照片（默认 50 张）。
     *
     * 大相册不再一次加载全量；后续页走 {@link #albumPhotosPage}。
     */
    @Transactional(readOnly = true)
    public PhotoAlbumDetailDto albumDetail(UUID ownerUserId, UUID albumId) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        List<UUID> photoIds = albumItemRepository.findPhotoIdsByAlbumId(
                albumId, PageRequest.of(0, DEFAULT_PAGE_SIZE));
        List<PhotoItemDto> photos = libraryService.listPhotosByIds(ownerUserId, photoIds);
        PhotoAlbumDto albumDto = toDto(album);
        return new PhotoAlbumDetailDto(albumDto, photos);
    }

    /**
     * 分页查询相册内照片，按相册排序序号升序。
     */
    @Transactional(readOnly = true)
    public Page<PhotoItemDto> albumPhotosPage(UUID ownerUserId, UUID albumId, int page, int size) {
        requireAlbum(ownerUserId, albumId);
        int safePage = Math.max(0, page);
        int safeSize = Math.min(Math.max(1, size), MAX_PAGE_SIZE);
        long total = albumItemRepository.countByAlbumId(albumId);
        List<UUID> photoIds = albumItemRepository.findPhotoIdsByAlbumId(
                albumId, PageRequest.of(safePage, safeSize));
        Map<UUID, PhotoItemDto> byId = libraryService.listPhotosByIds(ownerUserId, photoIds)
                .stream()
                .collect(Collectors.toMap(PhotoItemDto::id, photo -> photo));
        List<PhotoItemDto> content = photoIds.stream()
                .map(byId::get)
                .filter(Objects::nonNull)
                .toList();
        return new PageImpl<>(content, PageRequest.of(safePage, safeSize), total);
    }

    /**
     * 向相册添加照片，自动去重
     */
    @Transactional(rollbackFor = Exception.class)
    public void addPhotos(UUID ownerUserId, UUID albumId, List<UUID> photoIds) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        for (UUID photoId : photoIds) {
            if (albumItemRepository.existsByAlbumIdAndPhotoId(albumId, photoId)) {
                continue;
            }
            PhotoAlbumItem item = new PhotoAlbumItem();
            item.setOwnerUserId(ownerUserId);
            item.setAlbumId(albumId);
            item.setPhotoId(photoId);
            albumItemRepository.save(item);
        }
        refreshPhotoCount(albumId);
        recordAlbumEvent(ownerUserId, album, SyncAction.UPDATED);
    }

    /**
     * 从相册移除单张照片
     */
    @Transactional(rollbackFor = Exception.class)
    public void removePhoto(UUID ownerUserId, UUID albumId, UUID photoId) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        albumItemRepository.deleteByAlbumIdAndPhotoId(albumId, photoId);
        refreshPhotoCount(albumId);
        recordAlbumEvent(ownerUserId, album, SyncAction.UPDATED);
    }

    /**
     * 刷新相册照片计数
     */
    private void refreshPhotoCount(UUID albumId) {
        albumRepository.findById(albumId).ifPresent(album -> {
            album.setPhotoCount((int) albumItemRepository.countByAlbumId(albumId));
            albumRepository.save(album);
        });
    }

    /**
     * 查询相册并校验所有权，不存在则抛出异常
     */
    private PhotoAlbum requireAlbum(UUID ownerUserId, UUID albumId) {
        return albumRepository.findByOwnerUserIdAndId(ownerUserId, albumId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "相册不存在"));
    }

    // ─── 相册分享 ───

    /**
     * 创建相册分享链接。
     */
    @Transactional(rollbackFor = Exception.class)
    public PhotoShareLinkDto createAlbumShare(UUID ownerUserId, UUID albumId, CreateAlbumShareRequest request) {
        requireAlbum(ownerUserId, albumId);
        return toShareDto(resourceShareLinkService.create(
                ownerUserId,
                "PHOTO_ALBUM",
                albumId,
                request.password(),
                request.expiresAt(),
                request.maxAccessCount(),
                request.includeLocation() == null || request.includeLocation(),
                request.originalQuality() == null || request.originalQuality()
        ));
    }

    /**
     * 列出相册的所有分享链接。
     */
    @Transactional(readOnly = true)
    public List<PhotoShareLinkDto> listAlbumShares(UUID ownerUserId, UUID albumId) {
        requireAlbum(ownerUserId, albumId);
        return resourceShareLinkService.list(ownerUserId, albumId)
                .stream()
                .map(this::toShareDto)
                .toList();
    }

    /**
     * 撤销分享链接。
     */
    @Transactional(rollbackFor = Exception.class)
    public void revokeAlbumShare(UUID ownerUserId, UUID shareId) {
        resourceShareLinkService.revoke(ownerUserId, shareId);
    }

    /**
     * 创建单张照片分享链接。
     */
    @Transactional(rollbackFor = Exception.class)
    public PhotoShareLinkDto createPhotoShare(UUID ownerUserId, UUID photoId, CreateAlbumShareRequest request) {
        requirePhoto(ownerUserId, photoId);
        return toShareDto(resourceShareLinkService.create(
                ownerUserId,
                "PHOTO_ITEM",
                photoId,
                request.password(),
                request.expiresAt(),
                request.maxAccessCount(),
                request.includeLocation() == null || request.includeLocation(),
                request.originalQuality() == null || request.originalQuality()
        ));
    }

    /**
     * 列出单张照片的所有分享链接。
     */
    @Transactional(readOnly = true)
    public List<PhotoShareLinkDto> listPhotoShares(UUID ownerUserId, UUID photoId) {
        requirePhoto(ownerUserId, photoId);
        return resourceShareLinkService.list(ownerUserId, photoId)
                .stream()
                .map(this::toShareDto)
                .toList();
    }

    /**
     * 通过公开链接发起共享单张照片会话。
     */
    @Transactional(rollbackFor = Exception.class)
    public ShareAccessSessionDto issueSharedPhotoSession(
            String rawToken,
            String password,
            String clientAddress
    ) {
        return resourceShareLinkService.issueConsumedSession(
                rawToken, password, "PHOTO_ITEM", clientAddress);
    }

    /**
     * 通过短期分享会话访问共享单张照片。
     */
    @Transactional(rollbackFor = Exception.class)
    public PhotoItemDto accessSharedPhoto(String rawToken, String sessionToken) {
        ResourceShareLinkDto link = resourceShareLinkService.requireSession(
                rawToken, sessionToken, "PHOTO_ITEM");
        PhotoItem photo = photoItemRepository.findById(link.resourceId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "图片不存在"));
        // 使用详情路径以支持原图签发，再按分享策略裁剪。
        PhotoItemDto dto = libraryService.photo(photo.getOwnerUserId(), photo.getId());
        return applySharePolicy(dto, link.includeLocation(), link.originalQuality());
    }

    /**
     * 按分享策略裁剪公开照片 DTO：关闭位置时剥离 GPS；关闭原图时不签发 sourceUrl。
     */
    static PhotoItemDto applySharePolicy(
            PhotoItemDto dto,
            boolean includeLocation,
            boolean originalQuality
    ) {
        if (includeLocation && originalQuality) {
            return dto;
        }
        return new PhotoItemDto(
                dto.id(),
                dto.fileNodeId(),
                dto.title(),
                dto.description(),
                dto.width(),
                dto.height(),
                dto.orientation(),
                dto.dateTaken(),
                dto.cameraMake(),
                dto.cameraModel(),
                dto.aperture(),
                dto.shutterSpeed(),
                dto.iso(),
                dto.focalLength(),
                dto.flash(),
                dto.whiteBalance(),
                dto.meteringMode(),
                dto.lensModel(),
                includeLocation ? dto.gpsLatitude() : null,
                includeLocation ? dto.gpsLongitude() : null,
                includeLocation ? dto.gpsLocation() : null,
                dto.format(),
                dto.fileSize(),
                dto.coverUrl(),
                originalQuality ? dto.sourceUrl() : null,
                dto.metadataStatus(),
                dto.favorite(),
                dto.createdAt(),
                dto.tags(),
                dto.providerMetadata(),
                dto.contentAnalysis(),
                dto.motionState(),
                originalQuality ? dto.motionVideoUrl() : null
        );
    }

    private PhotoItem requirePhoto(UUID ownerUserId, UUID photoId) {
        return photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "图片不存在"));
    }

    /**
     * 通过公开链接访问共享相册。
     */
    @Transactional(rollbackFor = Exception.class)
    public ShareAccessSessionDto issueSharedAlbumSession(
            String rawToken,
            String password,
            String clientAddress
    ) {
        return resourceShareLinkService.issueConsumedSession(
                rawToken, password, "PHOTO_ALBUM", clientAddress);
    }

    /** 分页访问公开相册，并在授权成功后消费一次分享访问次数。 */
    @Transactional(rollbackFor = Exception.class)
    public PhotoSharedAlbumDto accessSharedAlbum(
            String rawToken,
            String sessionToken,
            int page,
            int size
    ) {
        ResourceShareLinkDto link = resourceShareLinkService.requireSession(
                rawToken, sessionToken, "PHOTO_ALBUM");
        UUID albumId = link.resourceId();
        PhotoAlbum album = albumRepository.findById(albumId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "相册不存在"));
        int safePage = Math.max(0, page);
        int safeSize = Math.min(Math.max(1, size), 100);
        List<UUID> photoIds = albumItemRepository.findPhotoIdsByAlbumId(
                albumId, PageRequest.of(safePage, safeSize));
        List<PhotoItemDto> photos = libraryService.listPhotosByIds(album.getOwnerUserId(), photoIds)
                .stream()
                .map(photo -> applySharePolicy(photo, link.includeLocation(), link.originalQuality()))
                .toList();
        return new PhotoSharedAlbumDto(
                album.getName(), album.getDescription(), photos,
                safePage, safeSize, albumItemRepository.countByAlbumId(albumId));
    }

    private PhotoShareLinkDto toShareDto(ResourceShareLinkDto share) {
        return new PhotoShareLinkDto(
                share.id(),
                share.token(),
                share.resourceType(),
                share.resourceId(),
                share.expiresAt(),
                share.maxAccessCount(),
                share.accessCount(),
                share.includeLocation(),
                share.originalQuality(),
                share.createdAt()
        );
    }

    /**
     * 将相册实体转换为DTO，自动解析封面图片URL
     */
    private PhotoAlbumDto toDto(PhotoAlbum album) {
        String coverUrl = resolveAlbumCoverUrl(album);
        return new PhotoAlbumDto(
                album.getId(),
                album.getName(),
                album.getDescription(),
                coverUrl,
                album.getPhotoCount(),
                album.getCreatedAt(),
                album.getUpdatedAt()
        );
    }

    /**
     * 解析相册封面URL：优先使用相册自身封面，否则取第一张照片的缩略图
     */
    private String resolveAlbumCoverUrl(PhotoAlbum album) {
        if (album.getCoverFileId() != null) {
            try {
                return libraryService.resolveCoverUrl(album.getOwnerUserId(), album.getCoverFileId());
            } catch (Exception ex) {
                log.warn("相册封面解析失败，尝试从第一张照片获取: albumId={}, error={}", album.getId(), ex.getMessage());
            }
        }
        List<UUID> photoIds = albumItemRepository.findPhotoIdsByAlbumId(album.getId());
        if (!photoIds.isEmpty()) {
            try {
                PhotoItem firstPhoto = libraryService.findPhotoById(photoIds.get(0));
                if (firstPhoto != null && firstPhoto.getCoverFileId() != null) {
                    return libraryService.resolveCoverUrl(firstPhoto.getOwnerUserId(), firstPhoto.getCoverFileId());
                }
            } catch (Exception ex) {
                log.warn("相册第一张照片封面解析失败: albumId={}, error={}", album.getId(), ex.getMessage());
            }
        }
        return null;
    }

    private void recordAlbumEvent(UUID ownerUserId, PhotoAlbum album, SyncAction action) {
        syncEventService.record(
                ownerUserId,
                SyncScope.PHOTOS,
                "PHOTO_ALBUM",
                album.getId() == null ? null : album.getId().toString(),
                action,
                album.getVersion(),
                Map.of()
        );
    }
}
