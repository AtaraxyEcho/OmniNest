package com.omninest.modules.photos.service;

import com.omninest.common.api.PageClamps;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.ratelimit.RateLimitService;
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
import com.omninest.modules.photos.dto.PhotoDtos.UpdatePhotoShareRequest;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoSharedAlbumDto;
import com.omninest.modules.photos.repository.PhotoAlbumFirstCoverProjection;
import com.omninest.modules.photos.repository.PhotoAlbumItemRepository;
import com.omninest.modules.photos.repository.PhotoAlbumRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
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
    private static final int LEGACY_LIST_LIMIT = 2000;
    private static final int IN_BATCH_SIZE = 500;

    private final PhotoAlbumRepository albumRepository;
    private final PhotoAlbumItemRepository albumItemRepository;
    private final PhotoItemRepository photoItemRepository;
    private final PhotoLibraryService libraryService;
    private final PhotoDtoAssembler photoDtoAssembler;
    private final ResourceShareLinkService resourceShareLinkService;
    private final MediaSyncEventService syncEventService;
    private final RateLimitService rateLimitService;

    @Transactional(readOnly = true)
    public List<PhotoAlbumDto> listAlbums(UUID ownerUserId) {
        return toDtos(albumRepository
                .findByOwnerUserIdOrderByUpdatedAtDesc(ownerUserId, PageRequest.of(0, LEGACY_LIST_LIMIT))
                .getContent());
    }

    @Transactional(readOnly = true)
    public Page<PhotoAlbumDto> listAlbumsPage(UUID ownerUserId, int page, int size) {
        Page<PhotoAlbum> result = albumRepository.findByOwnerUserIdOrderByUpdatedAtDesc(
                ownerUserId, PageRequest.of(PageClamps.safePage(page), PageClamps.safeSize(size)));
        return new PageImpl<>(
                toDtos(result.getContent()),
                result.getPageable(),
                result.getTotalElements()
        );
    }

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

    @Transactional(rollbackFor = Exception.class)
    public PhotoAlbumDto updateAlbum(UUID ownerUserId, UUID albumId, CreateAlbumRequest request) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        album.setName(request.name().trim());
        album.setDescription(request.description());
        PhotoAlbum saved = albumRepository.save(album);
        recordAlbumEvent(ownerUserId, saved, SyncAction.UPDATED);
        return toDto(saved);
    }

    @Transactional(rollbackFor = Exception.class)
    public void deleteAlbum(UUID ownerUserId, UUID albumId) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        resourceShareLinkService.revokeAll(albumId);
        List<PhotoAlbumItem> items = albumItemRepository.findByOwnerUserIdAndAlbumIdOrderBySortOrderAsc(ownerUserId, albumId);
        albumItemRepository.deleteAll(items);
        albumRepository.delete(album);
        recordAlbumEvent(ownerUserId, album, SyncAction.DELETED);
    }

    @Transactional(readOnly = true)
    public PhotoAlbumDetailDto albumDetail(UUID ownerUserId, UUID albumId) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        List<UUID> photoIds = albumItemRepository.findActivePhotoIdsByAlbumId(
                albumId, PageRequest.of(0, DEFAULT_PAGE_SIZE));
        List<PhotoItemDto> photos = libraryService.listPhotosByIds(ownerUserId, photoIds);
        PhotoAlbumDto albumDto = toDto(album);
        return new PhotoAlbumDetailDto(albumDto, photos);
    }

    @Transactional(readOnly = true)
    public Page<PhotoItemDto> albumPhotosPage(UUID ownerUserId, UUID albumId, int page, int size) {
        requireAlbum(ownerUserId, albumId);
        int safePage = Math.max(0, page);
        int safeSize = PageClamps.safeSize(size);
        long total = albumItemRepository.countActivePhotosByAlbumId(albumId);
        List<UUID> photoIds = albumItemRepository.findActivePhotoIdsByAlbumId(
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
     * 向相册添加照片，自动去重并按 maxSortOrder + 1 递增分配排序序号。
     */
    @Transactional(rollbackFor = Exception.class)
    public void addPhotos(UUID ownerUserId, UUID albumId, List<UUID> photoIds) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        if (photoIds == null || photoIds.isEmpty()) {
            return;
        }
        Set<UUID> activePhotoIds = findActivePhotoIdsInBatches(ownerUserId, photoIds);
        List<UUID> candidates = photoIds.stream()
                .filter(Objects::nonNull)
                .distinct()
                .filter(activePhotoIds::contains)
                .toList();
        List<PhotoAlbumItem> currentItems =
                albumItemRepository.findByOwnerUserIdAndAlbumIdOrderBySortOrderAsc(ownerUserId, albumId);
        int nextSortOrder = currentItems.stream()
                .mapToInt(PhotoAlbumItem::getSortOrder)
                .max()
                .orElse(-1) + 1;
        Set<UUID> existing = findExistingPhotoIdsInBatches(albumId, candidates);
        List<PhotoAlbumItem> items = new ArrayList<>();
        for (UUID photoId : candidates) {
            if (existing.add(photoId)) {
                PhotoAlbumItem item = new PhotoAlbumItem();
                item.setOwnerUserId(ownerUserId);
                item.setAlbumId(albumId);
                item.setPhotoId(photoId);
                item.setSortOrder(nextSortOrder++);
                items.add(item);
            }
        }
        if (!items.isEmpty()) {
            albumItemRepository.saveAll(items);
        }
        refreshPhotoCount(albumId);
        recordAlbumEvent(ownerUserId, album, SyncAction.UPDATED);
    }

    /**
     * 批量重排相册内照片顺序：按传入 photoIds 顺序从 0 起递增赋 sortOrder，
     * 未包含在列表中的既有条目保持相对顺序追加在末尾。
     */
    @Transactional(rollbackFor = Exception.class)
    public void reorderAlbumItems(UUID ownerUserId, UUID albumId, List<UUID> orderedPhotoIds) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        List<PhotoAlbumItem> currentItems =
                albumItemRepository.findByOwnerUserIdAndAlbumIdOrderBySortOrderAsc(ownerUserId, albumId);
        if (currentItems.isEmpty()) {
            return;
        }
        Map<UUID, PhotoAlbumItem> byPhotoId = new LinkedHashMap<>();
        for (PhotoAlbumItem item : currentItems) {
            byPhotoId.put(item.getPhotoId(), item);
        }
        List<PhotoAlbumItem> reordered = new ArrayList<>(currentItems.size());
        Set<UUID> placed = new HashSet<>();
        if (orderedPhotoIds != null) {
            for (UUID photoId : orderedPhotoIds) {
                if (photoId == null || !placed.add(photoId)) {
                    continue;
                }
                PhotoAlbumItem item = byPhotoId.get(photoId);
                if (item != null) {
                    reordered.add(item);
                }
            }
        }
        for (PhotoAlbumItem item : currentItems) {
            if (placed.add(item.getPhotoId())) {
                reordered.add(item);
            }
        }
        for (int index = 0; index < reordered.size(); index++) {
            reordered.get(index).setSortOrder(index);
        }
        albumItemRepository.saveAll(reordered);
        recordAlbumEvent(ownerUserId, album, SyncAction.UPDATED);
    }

    /**
     * 重置相册内照片的自定义排序，按加入相册时间（createdAt 升序、id 升序）恢复默认顺序。
     */
    @Transactional(rollbackFor = Exception.class)
    public void resetAlbumItemsOrder(UUID ownerUserId, UUID albumId) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        List<PhotoAlbumItem> currentItems =
                albumItemRepository.findByOwnerUserIdAndAlbumIdOrderBySortOrderAsc(ownerUserId, albumId);
        if (currentItems.isEmpty()) {
            return;
        }
        List<PhotoAlbumItem> sorted = new ArrayList<>(currentItems);
        sorted.sort(Comparator.comparing(
                        PhotoAlbumItem::getCreatedAt,
                        Comparator.nullsLast(Comparator.naturalOrder()))
                .thenComparing(PhotoAlbumItem::getId, Comparator.nullsLast(Comparator.naturalOrder())));
        for (int index = 0; index < sorted.size(); index++) {
            sorted.get(index).setSortOrder(index);
        }
        albumItemRepository.saveAll(sorted);
        recordAlbumEvent(ownerUserId, album, SyncAction.UPDATED);
    }

    @Transactional(rollbackFor = Exception.class)
    public void removePhoto(UUID ownerUserId, UUID albumId, UUID photoId) {
        PhotoAlbum album = requireAlbum(ownerUserId, albumId);
        albumItemRepository.deleteByAlbumIdAndPhotoId(albumId, photoId);
        refreshPhotoCount(albumId);
        recordAlbumEvent(ownerUserId, album, SyncAction.UPDATED);
    }

    private void refreshPhotoCount(UUID albumId) {
        albumRepository.findById(albumId).ifPresent(album -> {
            album.setPhotoCount((int) albumItemRepository.countActivePhotosByAlbumId(albumId));
            albumRepository.save(album);
        });
    }

    private PhotoAlbum requireAlbum(UUID ownerUserId, UUID albumId) {
        return albumRepository.findByOwnerUserIdAndId(ownerUserId, albumId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "相册不存在"));
    }

    // ─── 相册分享 ───

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

    @Transactional(readOnly = true)
    public List<PhotoShareLinkDto> listAlbumShares(UUID ownerUserId, UUID albumId) {
        requireAlbum(ownerUserId, albumId);
        return resourceShareLinkService.list(ownerUserId, albumId)
                .stream()
                .map(this::toShareDto)
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public void revokeAlbumShare(UUID ownerUserId, UUID shareId) {
        resourceShareLinkService.revoke(ownerUserId, shareId);
    }

    public PhotoShareLinkDto updatePhotoShare(
            UUID ownerUserId,
            UUID shareId,
            UpdatePhotoShareRequest request) {
        if (request.includeLocation() == null || request.originalQuality() == null) {
            throw new BusinessException(
                    ErrorCode.PARAM_ERROR,
                    "includeLocation 与 originalQuality 必须显式传值"
            );
        }
        return toShareDto(resourceShareLinkService.update(
                ownerUserId,
                shareId,
                request.password(),
                request.expiresAt(),
                request.maxAccessCount(),
                request.includeLocation(),
                request.originalQuality()
        ));
    }

    @Transactional(rollbackFor = Exception.class)
    public int revokeAllAlbumShares(UUID ownerUserId, UUID albumId) {
        requireAlbum(ownerUserId, albumId);
        return resourceShareLinkService.revokeAll(albumId);
    }

    @Transactional(rollbackFor = Exception.class)
    public int revokeAllPhotoShares(UUID ownerUserId, UUID photoId) {
        requirePhoto(ownerUserId, photoId);
        return resourceShareLinkService.revokeAll(photoId);
    }

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

    @Transactional(readOnly = true)
    public List<PhotoShareLinkDto> listPhotoShares(UUID ownerUserId, UUID photoId) {
        requirePhoto(ownerUserId, photoId);
        return resourceShareLinkService.list(ownerUserId, photoId)
                .stream()
                .map(this::toShareDto)
                .toList();
    }

    public ShareAccessSessionDto issueSharedPhotoSession(
            String rawToken,
            String password,
            String clientAddress
    ) {
        ResourceShareLinkService.ShareTarget target =
                resourceShareLinkService.resolveTarget(rawToken, "PHOTO_ITEM");
        photoItemRepository.findByOwnerUserIdAndId(target.ownerUserId(), target.resourceId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "图片不存在"));
        return resourceShareLinkService.issueConsumedSession(
                rawToken, password, "PHOTO_ITEM", clientAddress);
    }

    @Transactional(rollbackFor = Exception.class)
    public PhotoItemDto accessSharedPhoto(String rawToken, String sessionToken, String clientAddress) {
        requirePhotoShareRateLimit(rawToken, clientAddress);
        ResourceShareLinkDto link = resourceShareLinkService.requireSession(
                rawToken, sessionToken, "PHOTO_ITEM");
        PhotoItem photo = photoItemRepository.findById(link.resourceId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "图片不存在"));
        PhotoItemDto dto = libraryService.photo(photo.getOwnerUserId(), photo.getId());
        return applySharePolicy(dto, link.includeLocation(), link.originalQuality());
    }

    static PhotoItemDto applySharePolicy(
            PhotoItemDto dto,
            boolean includeLocation,
            boolean originalQuality
    ) {
        if (includeLocation && originalQuality) {
            return dto;
        }
        boolean coverIsOriginal = dto.coverFileId() == null
                || dto.coverFileId().equals(dto.fileNodeId());
        String coverUrl = (!includeLocation && coverIsOriginal) ? null : dto.coverUrl();
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
                coverUrl,
                includeLocation && originalQuality ? dto.sourceUrl() : null,
                dto.metadataStatus(),
                dto.favorite(),
                dto.createdAt(),
                dto.tags(),
                includeLocation ? dto.providerMetadata() : stripLocationMetadata(dto.providerMetadata()),
                dto.contentAnalysis(),
                dto.motionState(),
                includeLocation && originalQuality ? dto.motionVideoUrl() : null,
                dto.edited(),
                dto.coverFileId()
        );
    }

    private static final Set<String> LOCATION_METADATA_KEYS = Set.of(
            "gps", "gpslatitude", "gpslongitude", "location", "address",
            "latitude", "longitude", "lat", "lon", "rawexifgps"
    );

    private static Map<String, Object> stripLocationMetadata(Map<String, Object> metadata) {
        if (metadata == null || metadata.isEmpty()) {
            return metadata;
        }
        Map<String, Object> filtered = new HashMap<>();
        for (Map.Entry<String, Object> entry : metadata.entrySet()) {
            String normalized = entry.getKey() == null
                    ? ""
                    : entry.getKey().replace("_", "").replace("-", "").toLowerCase(Locale.ROOT);
            if (normalized.contains("gps") || LOCATION_METADATA_KEYS.contains(normalized)) {
                continue;
            }
            filtered.put(entry.getKey(), entry.getValue());
        }
        return filtered;
    }

    private void requirePhotoShareRateLimit(String rawToken, String clientAddress) {
        String tokenHash = sha256(rawToken);
        if (clientAddress != null && !rateLimitService.tryAcquire(
                "photo-share:ip:" + sha256(clientAddress) + ":" + tokenHash,
                30,
                Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
        if (!rateLimitService.tryAcquire("photo-share:" + tokenHash, 300, Duration.ofMinutes(1))) {
            throw new BusinessException(ErrorCode.RATE_LIMITED, "访问过于频繁，请稍后再试");
        }
    }

    private static String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 不可用", exception);
        }
    }

    private PhotoItem requirePhoto(UUID ownerUserId, UUID photoId) {
        return photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "图片不存在"));
    }

    public ShareAccessSessionDto issueSharedAlbumSession(
            String rawToken,
            String password,
            String clientAddress
    ) {
        return resourceShareLinkService.issueConsumedSession(
                rawToken, password, "PHOTO_ALBUM", clientAddress);
    }

    @Transactional(rollbackFor = Exception.class)
    public PhotoSharedAlbumDto accessSharedAlbum(
            String rawToken,
            String sessionToken,
            String clientAddress,
            int page,
            int size
    ) {
        requirePhotoShareRateLimit(rawToken, clientAddress);
        ResourceShareLinkDto link = resourceShareLinkService.requireSession(
                rawToken, sessionToken, "PHOTO_ALBUM");
        UUID albumId = link.resourceId();
        PhotoAlbum album = albumRepository.findById(albumId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "相册不存在"));
        int safePage = Math.max(0, page);
        int safeSize = Math.min(Math.max(1, size), 100);
        List<UUID> photoIds = albumItemRepository.findActivePhotoIdsByAlbumId(
                albumId, PageRequest.of(safePage, safeSize));
        List<PhotoItemDto> photos = libraryService.listPhotosByIds(album.getOwnerUserId(), photoIds)
                .stream()
                .map(photo -> applySharePolicy(photo, link.includeLocation(), link.originalQuality()))
                .toList();
        return new PhotoSharedAlbumDto(
                album.getName(), album.getDescription(), photos,
                safePage, safeSize, albumItemRepository.countActivePhotosByAlbumId(albumId));
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
                share.passwordProtected(),
                share.includeLocation(),
                share.originalQuality(),
                share.createdAt()
        );
    }

    private PhotoAlbumDto toDto(PhotoAlbum album) {
        return toDtos(List.of(album)).getFirst();
    }

    private List<PhotoAlbumDto> toDtos(List<PhotoAlbum> albums) {
        if (albums.isEmpty()) {
            return List.of();
        }
        Map<UUID, UUID> coverFileIdByAlbum = new HashMap<>();
        for (PhotoAlbum album : albums) {
            if (album.getCoverFileId() != null) {
                coverFileIdByAlbum.put(album.getId(), album.getCoverFileId());
            }
        }
        Map<UUID, String> coverUrls = new HashMap<>(signCoversByOwner(albums, coverFileIdByAlbum));
        List<PhotoAlbum> fallbackAlbums = albums.stream()
                .filter(album -> !coverUrls.containsKey(album.getId()))
                .toList();
        if (!fallbackAlbums.isEmpty()) {
            Map<UUID, UUID> fallbackCoverFileIds = findFirstActiveCoverFileIdsInBatches(
                    fallbackAlbums.stream().map(PhotoAlbum::getId).toList());
            Map<UUID, String> fallbackUrls = signCoversByOwner(fallbackAlbums, fallbackCoverFileIds);
            coverUrls.putAll(fallbackUrls);
        }
        return albums.stream()
                .map(album -> new PhotoAlbumDto(
                        album.getId(),
                        album.getName(),
                        album.getDescription(),
                        coverUrls.get(album.getId()),
                        album.getPhotoCount(),
                        album.getCreatedAt(),
                        album.getUpdatedAt()
                ))
                .toList();
    }

    private Map<UUID, String> signCoversByOwner(List<PhotoAlbum> albums, Map<UUID, UUID> coverFileIdByAlbum) {
        Map<UUID, List<UUID>> fileIdsByOwner = new HashMap<>();
        for (PhotoAlbum album : albums) {
            UUID coverFileId = coverFileIdByAlbum.get(album.getId());
            if (coverFileId == null) {
                continue;
            }
            fileIdsByOwner
                    .computeIfAbsent(album.getOwnerUserId(), key -> new ArrayList<>())
                    .add(coverFileId);
        }
        if (fileIdsByOwner.isEmpty()) {
            return Map.of();
        }
        Map<UUID, String> coverUrls = new HashMap<>();
        fileIdsByOwner.forEach((ownerUserId, fileIds) -> {
            Map<UUID, String> signed = photoDtoAssembler.resolveDownloadUrls(ownerUserId, fileIds);
            for (PhotoAlbum album : albums) {
                UUID coverFileId = coverFileIdByAlbum.get(album.getId());
                if (coverFileId == null || !ownerUserId.equals(album.getOwnerUserId())) {
                    continue;
                }
                String url = signed.get(coverFileId);
                if (url != null) {
                    coverUrls.put(album.getId(), url);
                }
            }
        });
        return coverUrls;
    }

    private Set<UUID> findActivePhotoIdsInBatches(UUID ownerUserId, List<UUID> photoIds) {
        if (photoIds.size() <= IN_BATCH_SIZE) {
            return photoItemRepository.findActiveByOwnerUserIdAndIdIn(ownerUserId, photoIds)
                    .stream()
                    .map(PhotoItem::getId)
                    .collect(Collectors.toSet());
        }
        Set<UUID> result = new HashSet<>();
        for (int start = 0; start < photoIds.size(); start += IN_BATCH_SIZE) {
            int end = Math.min(start + IN_BATCH_SIZE, photoIds.size());
            for (PhotoItem item : photoItemRepository.findActiveByOwnerUserIdAndIdIn(
                    ownerUserId, photoIds.subList(start, end))) {
                result.add(item.getId());
            }
        }
        return result;
    }

    private Set<UUID> findExistingPhotoIdsInBatches(UUID albumId, List<UUID> candidates) {
        if (candidates.isEmpty()) {
            return new HashSet<>();
        }
        if (candidates.size() <= IN_BATCH_SIZE) {
            return new HashSet<>(albumItemRepository.findExistingPhotoIds(albumId, candidates));
        }
        Set<UUID> result = new HashSet<>();
        for (int start = 0; start < candidates.size(); start += IN_BATCH_SIZE) {
            int end = Math.min(start + IN_BATCH_SIZE, candidates.size());
            result.addAll(albumItemRepository.findExistingPhotoIds(albumId, candidates.subList(start, end)));
        }
        return result;
    }

    private Map<UUID, UUID> findFirstActiveCoverFileIdsInBatches(List<UUID> albumIds) {
        Map<UUID, UUID> result = new HashMap<>();
        for (int start = 0; start < albumIds.size(); start += IN_BATCH_SIZE) {
            List<UUID> batch = albumIds.size() <= IN_BATCH_SIZE
                    ? albumIds
                    : albumIds.subList(start, Math.min(start + IN_BATCH_SIZE, albumIds.size()));
            for (PhotoAlbumFirstCoverProjection projection :
                    albumItemRepository.findFirstActiveCoverFileIdsByAlbumIds(batch)) {
                result.putIfAbsent(projection.getAlbumId(), projection.getCoverFileId());
            }
        }
        return result;
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
