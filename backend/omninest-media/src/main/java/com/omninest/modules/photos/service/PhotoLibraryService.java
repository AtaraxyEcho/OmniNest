package com.omninest.modules.photos.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.api.PageClamps;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FilePurgeOrigin;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.user.service.SystemInstanceConfigService;
import com.omninest.modules.photos.domain.PhotoAlbumItem;
import com.omninest.modules.photos.domain.PhotoFavorite;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.dto.GroupBy;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoDashboardDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoGroupDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoItemDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoListItemDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoMonthGroup;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoTrashResultDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoTimelineDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoTimelineMonthDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoYearGroup;
import com.omninest.modules.photos.repository.PhotoAlbumRepository;
import com.omninest.modules.photos.repository.PhotoFavoriteRepository;
import com.omninest.modules.photos.repository.PhotoGroupPreviewProjection;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoListItemProjection;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.modules.photos.repository.PhotoTimelinePreviewProjection;
import com.omninest.modules.photos.search.PhotoSearchIndexService;
import java.time.Duration;
import java.time.Instant;
import java.time.YearMonth;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
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
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 照片库服务，提供浏览、搜索、收藏和删除功能。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoLibraryService {

    /** 全文索引单次检索上限；相关性分页在内存中完成，必须有界。 */
    private static final int SEARCH_INDEX_LIMIT = 500;
    /** 时间线/分组预览页上限：卡片预览不宜一次拉过多。 */
    private static final int PREVIEW_PAGE_MAX = 100;
    /** 单个永久删除任务承载的照片上限：任务载荷与单事务行数都必须有界。 */
    private static final int TRASH_PURGE_BATCH_SIZE = 200;
    private static final Map<String, String> SORT_FIELDS = Map.of(
            "createdAt", "createdAt",
            "dateTaken", "dateTaken",
            "title", "title",
            "fileSize", "fileSize"
    );

    private final PhotoItemRepository photoItemRepository;
    private final PhotoFavoriteRepository favoriteRepository;
    private final PhotoAlbumRepository albumRepository;
    private final PhotoChangeSideEffects sideEffects;
    private final PhotoTagRepository photoTagRepository;
    private final PhotoSearchIndexService photoSearchIndexService;
    private final FileDeletionService fileDeletionService;
    private final FileQueryService fileQueryService;
    private final ReadThroughCache readThroughCache;
    private final PhotoContentAnalysisService contentAnalysisService;
    private final PhotoGeoService photoGeoService;
    private final PhotoIndexTaskService photoIndexTaskService;
    private final SystemInstanceConfigService systemInstanceConfigService;
    private final PhotosRuntimeConfigService photosRuntimeConfigService;
    private final PhotoDtoAssembler photoDtoAssembler;

    /**
     * 照片仪表盘，返回统计数据和近期/收藏照片（缓存 3 分钟）。
     */
    @Transactional(readOnly = true)
    public PhotoDashboardDto dashboard(UUID ownerUserId) {
        String cacheKey = "omninest:dashboard:photo:" + ownerUserId;
        return readThroughCache.getOrLoad(cacheKey, Duration.ofMinutes(3),
                () -> loadDashboard(ownerUserId),
                PhotoDashboardDto.class);
    }

    /**
     * 从数据库加载照片仪表盘数据。
     */
    private PhotoDashboardDto loadDashboard(UUID ownerUserId) {
        long totalPhotos = photoItemRepository.countByOwnerUserId(ownerUserId);
        long totalAlbums = albumRepository.countByOwnerUserId(ownerUserId);
        long trashCount = photoItemRepository.countByOwnerUserIdAndDeletedAtIsNotNull(ownerUserId);
        long totalFavorites = favoriteRepository.countByOwnerUserId(ownerUserId);

        List<PhotoItem> recent = photoItemRepository.findTopNByOwnerUserIdOrderByCreatedAtDesc(ownerUserId, 12);
        List<UUID> recentIds = recent.stream().map(PhotoItem::getId).toList();
        Set<UUID> recentFavoriteIds = recentIds.isEmpty()
                ? Set.of()
                : Set.copyOf(favoriteRepository.findPhotoIdsByOwnerUserIdAndPhotoIdIn(ownerUserId, recentIds));

        // 仅取最近 12 条收藏，避免为计数与预览加载全表收藏。
        List<UUID> favoritePreviewIds = favoriteRepository
                .findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId, PageRequest.of(0, 12))
                .stream()
                .map(PhotoFavorite::getPhotoId)
                .toList();
        Map<UUID, PhotoItem> favoriteItems = favoritePreviewIds.isEmpty()
                ? Map.of()
                : photoItemRepository.findActiveByOwnerUserIdAndIdIn(ownerUserId, favoritePreviewIds)
                        .stream()
                        .collect(Collectors.toMap(PhotoItem::getId, p -> p));
        List<PhotoItem> favorites = favoritePreviewIds.stream()
                .map(favoriteItems::get)
                .filter(Objects::nonNull)
                .toList();

        Set<UUID> favoriteItemIds = favorites.stream()
                .map(PhotoItem::getId)
                .collect(Collectors.toSet());
        return new PhotoDashboardDto(
                totalPhotos,
                totalAlbums,
                totalFavorites,
                trashCount,
                photoDtoAssembler.mapPhotoItemDtos(ownerUserId, recent, recentFavoriteIds),
                photoDtoAssembler.mapPhotoItemDtos(ownerUserId, favorites, favoriteItemIds)
        );
    }

    /**
     * 分页查询用户照片列表。
     *
     * @param ownerUserId 用户标识
     * @param page 页码，从零开始
     * @param size 每页条数
     * @param sort 排序表达式，格式为字段和方向
     * @param query 标题或描述筛选词
     * @return 照片轻量列表分页
     */
    @Transactional(readOnly = true)
    public Page<PhotoListItemDto> listPhotosPage(
            UUID ownerUserId,
            int page,
            int size,
            String sort,
            String query
    ) {
        Pageable pageable = photoPageable(page, size, sort);
        String trimmedQuery = query == null ? null : query.trim();
        if (trimmedQuery == null || trimmedQuery.isEmpty()) {
            return mapListPage(ownerUserId, photoItemRepository.findListPage(ownerUserId, pageable), false);
        }
        Page<PhotoListItemDto> indexed = searchIndexedPhotosPage(ownerUserId, trimmedQuery, pageable);
        if (indexed != null) {
            return indexed;
        }
        return mapListPage(
                ownerUserId,
                photoItemRepository.searchListPage(ownerUserId, normalizeQuery(trimmedQuery), pageable),
                false
        );
    }

    /**
     * 先用 Lucene 取按相关性排序的命中 ID，再按 ID 取回展示投影并切片。
     *
     * <p>索引未建立、无命中或命中的文档已全部失效时返回 null，由调用方回退到 SQL。
     * 命中总数以索引上限为界：搜索结果不做无限翻页，避免一次搜索把整库拉进内存。</p>
     */
    private Page<PhotoListItemDto> searchIndexedPhotosPage(
            UUID ownerUserId,
            String query,
            Pageable pageable
    ) {
        List<UUID> luceneIds = photoSearchIndexService.search(ownerUserId, query, SEARCH_INDEX_LIMIT);
        if (luceneIds.isEmpty()) {
            return null;
        }
        Map<UUID, PhotoListItemProjection> projectionsById = photoItemRepository
                .findListByIds(ownerUserId, luceneIds)
                .stream()
                .collect(Collectors.toMap(PhotoListItemProjection::getId, item -> item, (left, right) -> left));
        List<PhotoListItemProjection> ordered = luceneIds.stream()
                .map(projectionsById::get)
                .filter(Objects::nonNull)
                .toList();
        if (ordered.isEmpty()) {
            return null;
        }
        int from = (int) Math.min(pageable.getOffset(), ordered.size());
        int to = Math.min(from + pageable.getPageSize(), ordered.size());
        List<PhotoListItemDto> content = photoDtoAssembler.mapListItems(ownerUserId, ordered.subList(from, to), false);
        return new PageImpl<>(content, pageable, ordered.size());
    }

    /**
     * 分页查询用户收藏照片列表。
     *
     * @param ownerUserId 用户标识
     * @param page 页码，从零开始
     * @param size 每页条数
     * @param sort 排序表达式，格式为字段和方向
     * @param query 标题或描述筛选词
     * @return 收藏照片轻量列表分页
     */
    @Transactional(readOnly = true)
    public Page<PhotoListItemDto> listFavoritesPage(
            UUID ownerUserId,
            int page,
            int size,
            String sort,
            String query
    ) {
        Pageable pageable = photoPageable(page, size, sort);
        String normalizedQuery = normalizeQuery(query);
        Page<PhotoListItemProjection> result = normalizedQuery == null
                ? photoItemRepository.findFavoriteListPage(ownerUserId, pageable)
                : photoItemRepository.searchFavoriteListPage(ownerUserId, normalizedQuery, pageable);
        return mapListPage(ownerUserId, result, true);
    }

    /**
     * 查询单张照片详情
     */
    @Transactional(readOnly = true)
    public PhotoItemDto photo(UUID ownerUserId, UUID photoId) {
        PhotoItem item = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "图片不存在"));
        boolean favorite = favoriteRepository.existsByOwnerUserIdAndPhotoId(ownerUserId, photoId);
        return toDto(item, favorite, true);
    }

    /**
     * 按指定顺序批量查询用户拥有的活动照片，供公开相册分页使用。 */
    @Transactional(readOnly = true)
    public List<PhotoItemDto> listPhotosByIds(UUID ownerUserId, List<UUID> photoIds) {
        if (photoIds == null || photoIds.isEmpty()) {
            return List.of();
        }
        Set<UUID> favoriteIds = Set.copyOf(
                favoriteRepository.findPhotoIdsByOwnerUserIdAndPhotoIdIn(ownerUserId, photoIds));
        Map<UUID, PhotoItem> itemsById = photoItemRepository
                .findActiveByOwnerUserIdAndIdIn(ownerUserId, photoIds)
                .stream()
                .collect(Collectors.toMap(PhotoItem::getId, item -> item));
        List<PhotoItem> orderedItems = photoIds.stream()
                .map(itemsById::get)
                .filter(Objects::nonNull)
                .toList();
        // 公开相册开启原图质量时依赖 sourceUrl/motionVideoUrl，批量签名由组装器统一补齐。
        return photoDtoAssembler.mapPhotoItemDtos(ownerUserId, orderedItems, favoriteIds);
    }

    /**
     * 将照片移入回收站（软删除，保留 30 天，可恢复或手动永久删除）。
     *
     * @param ownerUserId 当前用户 ID
     * @param photoId 照片 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void movePhotoToTrash(UUID ownerUserId, UUID photoId) {
        PhotoTrashResultDto result = movePhotosToTrash(ownerUserId, List.of(photoId)).getFirst();
        if (!result.success()) {
            throw new BusinessException(ErrorCode.NOT_FOUND, result.message());
        }
    }

    /**
     * 批量将照片移入回收站，返回逐项处理结果。
     *
     * <p>一次批量读、一次批量写、一次相册重算与看板失效：逐张调用会把这三项放大成 N 倍。
     * 照片进回收站不删相册关联条目，也不在请求进程写索引，统一投递给单写进程消费。</p>
     *
     * @param ownerUserId 当前用户 ID
     * @param photoIds 照片 ID 列表
     * @return 逐项结果
     */
    @Transactional(rollbackFor = Exception.class)
    public List<PhotoTrashResultDto> movePhotosToTrash(UUID ownerUserId, List<UUID> photoIds) {
        List<UUID> distinctPhotoIds = photoIds == null
                ? List.of()
                : photoIds.stream().distinct().toList();
        if (distinctPhotoIds.isEmpty()) {
            return List.of();
        }
        Map<UUID, PhotoItem> itemsById = photoItemRepository.findByOwnerUserIdAndIdIn(ownerUserId, distinctPhotoIds)
                .stream()
                .collect(Collectors.toMap(PhotoItem::getId, item -> item));
        Instant trashedAt = Instant.now();
        List<PhotoItem> changed = new ArrayList<>();
        List<PhotoTrashResultDto> results = new ArrayList<>();
        for (UUID photoId : distinctPhotoIds) {
            PhotoItem item = itemsById.get(photoId);
            if (item == null) {
                results.add(new PhotoTrashResultDto(photoId, false, "图片不存在"));
                continue;
            }
            if (item.getDeletedAt() == null) {
                item.setDeletedAt(trashedAt);
                changed.add(item);
            }
            results.add(new PhotoTrashResultDto(photoId, true, null));
        }
        if (changed.isEmpty()) {
            return results;
        }
        photoItemRepository.saveAll(changed);
        sideEffects.afterTrashChange(ownerUserId,
                changed.stream().map(PhotoItem::getId).toList(),
                SyncAction.DELETED, Map.of("trashed", true));
        return results;
    }

    /**
     * 分页查询回收站照片。
     *
     * @param ownerUserId 当前用户 ID
     * @param page 页码，从零开始
     * @param size 每页条数
     * @return 回收站照片轻量列表分页
     */
    @Transactional(readOnly = true)
    public Page<PhotoListItemDto> listTrashPage(UUID ownerUserId, int page, int size) {
        Pageable pageable = PageRequest.of(
                Math.max(page, 0),
                PageClamps.safeSize(size),
                Sort.by(Sort.Direction.DESC, "deletedAt")
        );
        return mapListPage(ownerUserId, photoItemRepository.findTrashPage(ownerUserId, pageable), false);
    }

    /**
     * 统计用户回收站中的照片数量。
     *
     * @param ownerUserId 当前用户 ID
     * @return 回收站照片数量
     */
    @Transactional(readOnly = true)
    public long countTrash(UUID ownerUserId) {
        return photoItemRepository.countByOwnerUserIdAndDeletedAtIsNotNull(ownerUserId);
    }

    /**
     * 从回收站恢复照片。
     *
     * @param ownerUserId 当前用户 ID
     * @param photoId 照片 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void restorePhotoFromTrash(UUID ownerUserId, UUID photoId) {
        PhotoItem item = photoItemRepository.findTrashedByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "回收站中不存在该图片"));
        item.setDeletedAt(null);
        photoItemRepository.save(item);
        sideEffects.afterTrashChange(ownerUserId, List.of(photoId),
                SyncAction.RESTORED, Map.of("trashed", false));
        log.info("照片已从回收站恢复: photoId={}, userId={}", photoId, ownerUserId);
    }

    /**
     * 永久删除回收站中的照片及其源文件。
     *
     * @param ownerUserId 当前用户 ID
     * @param photoId 照片 ID
     * @param cascade 是否允许级联清理其他业务引用
     * @return 永久删除任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID purgePhotoFromTrash(UUID ownerUserId, UUID photoId, boolean cascade) {
        PhotoItem item = photoItemRepository.findTrashedByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "回收站中不存在该图片"));
        UUID taskId = fileDeletionService.deletePermanently(
                ownerUserId,
                item.getFileNodeId(),
                cascade,
                new FilePurgeOrigin("PHOTOS", photoId),
                null
        );
        log.info("回收站照片永久删除任务已创建: taskId={}, photoId={}, userId={}", taskId, photoId, ownerUserId);
        return taskId;
    }

    /**
     * 清空回收站：对回收站内全部照片创建一个批量永久删除任务。
     *
     * @param ownerUserId 当前用户 ID
     * @return 永久删除任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID purgeTrash(UUID ownerUserId) {
        List<UUID> taskIds = purgeTrashInBatches(ownerUserId, Instant.now());
        if (taskIds.isEmpty()) {
            throw new BusinessException(ErrorCode.NOT_FOUND, "回收站为空");
        }
        log.info("回收站清空任务已创建: taskId={}, taskCount={}, userId={}",
                taskIds.getFirst(), taskIds.size(), ownerUserId);
        return taskIds.getFirst();
    }

    /**
     * 按固定批次把截止时间前的回收站照片拆成多个永久删除任务。
     *
     * <p>每一批独立成任务：删除任务载荷里的根节点列表有 64KB 上限，单事务里
     * 逐行加锁与软删也会随照片数线性变长。批次提交后照片从回收站查询中消失，
     * 循环条件因此自然收敛。</p>
     */
    private List<UUID> purgeTrashInBatches(UUID ownerUserId, Instant cutoff) {
        List<UUID> taskIds = new ArrayList<>();
        while (true) {
            List<PhotoItem> items = photoItemRepository.findTrashBatch(
                    ownerUserId,
                    cutoff,
                    PageRequest.of(0, TRASH_PURGE_BATCH_SIZE)
            );
            if (items.isEmpty()) {
                return taskIds;
            }
            taskIds.add(fileDeletionService.deletePermanentlyBatch(
                    ownerUserId,
                    items.stream().map(PhotoItem::getFileNodeId).toList(),
                    false,
                    items.stream().map(item -> new FilePurgeOrigin("PHOTOS", item.getId())).toList()
            ));
        }
    }

    /**
     * 为有 GPS 坐标但缺少地名信息的照片补充逆地理编码结果。
     *
     * <p>导入时的逆地理编码可能因限流或网络失败而缺失，此方法用于按需回填。</p>
     *
     * <p>刻意不加方法级事务：在线回退会等分布式限流并同步请求外部服务（超时 10 秒），
     * 包在事务里就是让这段外呼一直占着数据库连接。读取、外呼与单行写回各自成事务即可。</p>
     *
     * @param ownerUserId 当前用户 ID
     * @param photoId 照片 ID
     */
    public void backfillPhotoGeocode(UUID ownerUserId, UUID photoId) {
        PhotoItem item = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "图片不存在"));
        if (item.getGpsLatitude() == null || item.getGpsLongitude() == null) {
            return;
        }
        Map<String, Object> existing = item.getGpsLocation();
        if (existing != null
                && (existing.containsKey("city") || existing.containsKey("displayName"))) {
            return;
        }
        Map<String, Object> geoInfo = photoGeoService.reverseGeocode(
                item.getGpsLatitude(),
                item.getGpsLongitude()
        );
        if (geoInfo.isEmpty()) {
            return;
        }
        item.setGpsLocation(geoInfo);
        photoItemRepository.save(item);
        log.info("照片位置地名回填完成: photoId={}, userId={}", photoId, ownerUserId);
    }

    /**
     * 清理指定用户回收站中超过保留期的照片（调度入口）。
     *
     * @param ownerUserId 用户 ID
     * @param cutoff 保留期截止时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void purgeExpiredTrashForOwner(UUID ownerUserId, Instant cutoff) {
        List<UUID> taskIds = purgeTrashInBatches(ownerUserId, cutoff);
        if (taskIds.isEmpty()) {
            return;
        }
        log.info("回收站过期照片清理任务已创建: taskCount={}, userId={}", taskIds.size(), ownerUserId);
    }

    /**
     * 添加照片收藏
     */
    @Transactional(rollbackFor = Exception.class)
    public void addFavorite(UUID ownerUserId, UUID photoId) {
        photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "图片不存在"));
        if (favoriteRepository.existsByOwnerUserIdAndPhotoId(ownerUserId, photoId)) {
            return;
        }
        PhotoFavorite fav = new PhotoFavorite();
        fav.setOwnerUserId(ownerUserId);
        fav.setPhotoId(photoId);
        favoriteRepository.save(fav);
        sideEffects.invalidateDashboardCache(ownerUserId);
        sideEffects.recordPhotoEvent(ownerUserId, photoId, SyncAction.UPDATED, null, Map.of("favorite", true));
    }

    /**
     * 移除照片收藏
     */
    @Transactional(rollbackFor = Exception.class)
    public void removeFavorite(UUID ownerUserId, UUID photoId) {
        favoriteRepository.deleteByOwnerUserIdAndPhotoId(ownerUserId, photoId);
        sideEffects.invalidateDashboardCache(ownerUserId);
        sideEffects.recordPhotoEvent(ownerUserId, photoId, SyncAction.UPDATED, null, Map.of("favorite", false));
    }

    /**
     * 查询用户收藏照片列表
     */
    @Transactional(readOnly = true)
    public List<PhotoItemDto> listFavorites(UUID ownerUserId) {
        List<PhotoItem> photos = findFavoritePhotos(ownerUserId, 0);
        Set<UUID> favoriteIds = photos.stream().map(PhotoItem::getId).collect(Collectors.toSet());
        return photoDtoAssembler.mapPhotoItemDtos(ownerUserId, photos, favoriteIds);
    }

    /**
     * 批量加载收藏照片，避免N+1查询
     */
    private List<PhotoItem> findFavoritePhotos(UUID ownerUserId, int limit) {
        List<UUID> photoIds = favoriteRepository.findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId)
                .stream()
                .map(PhotoFavorite::getPhotoId)
                .toList();
        if (photoIds.isEmpty()) {
            return List.of();
        }
        List<UUID> limited = limit > 0 ? photoIds.subList(0, Math.min(limit, photoIds.size())) : photoIds;
        Map<UUID, PhotoItem> items = photoItemRepository
                .findActiveByOwnerUserIdAndIdIn(ownerUserId, limited).stream()
                .collect(Collectors.toMap(PhotoItem::getId, p -> p));
        return limited.stream().map(items::get).filter(Objects::nonNull).toList();
    }

    private List<UUID> photoIds(List<PhotoItem> items) {
        return items.stream().map(PhotoItem::getId).toList();
    }

    /**
     * 根据ID查询照片实体，不存在返回null
     */
    PhotoItem findPhotoById(UUID photoId) {
        return photoItemRepository.findById(photoId).orElse(null);
    }

    /**
     * 时间线视图，按年→月分组，每月返回照片数和前4张预览。
     * 旧版接口最多返回最近一百个月。
     *
     * @param ownerUserId 用户标识
     * @return 有界时间线
     */
    @Transactional(readOnly = true)
    public PhotoTimelineDto timeline(UUID ownerUserId) {
        return timeline(ownerUserId, PREVIEW_PAGE_MAX);
    }

    /**
     * 返回受月份数量上限约束的兼容版照片时间线。
     *
     * @param ownerUserId 用户标识
     * @param maxMonths 最多返回的月份数量
     * @return 有界时间线
     */
    @Transactional(readOnly = true)
    public PhotoTimelineDto timeline(UUID ownerUserId, int maxMonths) {
        Page<PhotoTimelineMonthDto> page = timelinePage(ownerUserId, 0, maxMonths);
        Map<Integer, List<PhotoMonthGroup>> monthsByYear = new LinkedHashMap<>();
        for (PhotoTimelineMonthDto month : page.getContent()) {
            List<PhotoMonthGroup> months = monthsByYear.computeIfAbsent(month.year(), ignored -> new ArrayList<>());
            months.add(new PhotoMonthGroup(
                    month.month(),
                    month.photoCount(),
                    month.previewPhotos().stream().map(photoDtoAssembler::toLegacyPhotoItem).toList()
            ));
        }
        List<PhotoYearGroup> years = monthsByYear.entrySet().stream()
                .map(entry -> new PhotoYearGroup(entry.getKey(), List.copyOf(entry.getValue())))
                .toList();
        return new PhotoTimelineDto(years);
    }

    /**
     * 按月份分页查询照片时间线，每个月只返回最多四张轻量预览。
     *
     * @param ownerUserId 用户标识
     * @param page 页码，从零开始
     * @param size 每页月份数量
     * @return 时间线月份分页
     */
    @Transactional(readOnly = true)
    public Page<PhotoTimelineMonthDto> timelinePage(UUID ownerUserId, int page, int size) {
        int safePage = Math.max(0, page);
        int safeSize = boundedPageSize(size);
        String zoneId = systemInstanceConfigService.timeZone().getId();
        List<PhotoTimelinePreviewProjection> rows = photoItemRepository.findTimelinePreviewPage(
                ownerUserId,
                zoneId,
                Math.multiplyFull(safePage, safeSize),
                safeSize
        );
        long totalMonths = photoItemRepository.countTimelineMonths(ownerUserId, zoneId);
        List<PhotoTimelineMonthDto> months = mapTimelineMonths(ownerUserId, rows);
        return new PageImpl<>(months, PageRequest.of(safePage, safeSize), totalMonths);
    }

    /**
     * 按年月分页查询照片轻量列表，时间口径与时间线一致。
     *
     * <p>分组键为拍摄时间缺失时回退创建时间，区间按系统默认时区换算，左闭右开避免跨月边界重复。</p>
     *
     * @param ownerUserId 用户标识
     * @param year 年份
     * @param month 月份（1-12）
     * @param page 页码，从零开始
     * @param size 每页条数
     * @param sort 排序表达式，格式为字段和方向
     * @return 照片轻量列表分页
     */
    @Transactional(readOnly = true)
    public Page<PhotoListItemDto> listPeriodPage(
            UUID ownerUserId,
            int year,
            int month,
            int page,
            int size,
            String sort
    ) {
        if (month < 1 || month > 12) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "照片月份参数不合法");
        }
        YearMonth period = YearMonth.of(year, month);
        ZoneId zoneId = systemInstanceConfigService.timeZone();
        Instant periodStart = period.atDay(1).atStartOfDay(zoneId).toInstant();
        Instant periodEnd = period.plusMonths(1).atDay(1).atStartOfDay(zoneId).toInstant();
        Pageable pageable = photoPageable(page, size, sort);
        Page<PhotoListItemProjection> result = photoItemRepository.findPeriodListPage(
                ownerUserId,
                periodStart,
                periodEnd,
                pageable
        );
        return mapListPage(ownerUserId, result, false);
    }

    /**
     * 按地点分组键分页查询照片。
     *
     * @param ownerUserId 用户标识
     * @param location 地点分组键
     * @param page 页码，从零开始
     * @param size 每页条数
     * @return 照片轻量列表分页
     */
    @Transactional(readOnly = true)
    public Page<PhotoItemDto> listLocationPage(
            UUID ownerUserId,
            String location,
            int page,
            int size
    ) {
        String normalizedLocation = location == null || location.isBlank()
                ? "未知位置"
                : location.trim();
        int safePage = Math.max(0, page);
        int safeSize = Math.max(1, Math.min(size, 200));
        long total = photoItemRepository.countByLocation(ownerUserId, normalizedLocation);
        if (total == 0) {
            return new PageImpl<>(List.of(), PageRequest.of(safePage, safeSize), 0);
        }
        List<UUID> ids = photoItemRepository.findIdsByLocation(
                ownerUserId,
                normalizedLocation,
                safeSize,
                (long) safePage * safeSize
        );
        if (ids.isEmpty()) {
            return new PageImpl<>(List.of(), PageRequest.of(safePage, safeSize), total);
        }
        Set<UUID> favoriteIds = Set.copyOf(
                favoriteRepository.findPhotoIdsByOwnerUserIdAndPhotoIdIn(ownerUserId, ids));
        Map<UUID, PhotoItem> itemsById = photoItemRepository
                .findActiveByOwnerUserIdAndIdIn(ownerUserId, ids)
                .stream()
                .collect(Collectors.toMap(PhotoItem::getId, item -> item));
        List<PhotoItem> orderedItems = ids.stream()
                .map(itemsById::get)
                .filter(Objects::nonNull)
                .toList();
        List<PhotoItemDto> content = photoDtoAssembler.mapPhotoItemDtos(
                ownerUserId, orderedItems, favoriteIds);
        return new PageImpl<>(content, PageRequest.of(safePage, safeSize), total);
    }

    /**
     * 分页查询可加入相册的候选照片，排除已在该相册内的照片。
     *
     * @param ownerUserId 用户标识
     * @param albumId 相册标识
     * @param page 页码，从零开始
     * @param size 每页条数
     * @param sort 排序表达式，格式为字段和方向
     * @return 候选照片轻量列表分页
     */
    @Transactional(readOnly = true)
    public Page<PhotoListItemDto> listAlbumCandidatesPage(
            UUID ownerUserId,
            UUID albumId,
            int page,
            int size,
            String sort
    ) {
        Pageable pageable = photoPageable(page, size, sort);
        Page<PhotoListItemProjection> result = photoItemRepository.findAlbumCandidatePage(
                ownerUserId,
                albumId,
                pageable
        );
        return mapListPage(ownerUserId, result, false);
    }

    /**
     * 添加照片标签。
     */
    @Transactional(rollbackFor = Exception.class)
    public void addTag(UUID ownerUserId, UUID photoId, String tag) {
        photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "图片不存在"));
        if (photoTagRepository.existsByOwnerUserIdAndPhotoIdAndTag(ownerUserId, photoId, tag)) {
            return;
        }
        PhotoTag photoTag = new PhotoTag();
        photoTag.setOwnerUserId(ownerUserId);
        photoTag.setPhotoId(photoId);
        photoTag.setTag(tag);
        photoTagRepository.save(photoTag);
        sideEffects.recordPhotoEvent(ownerUserId, photoId, SyncAction.UPDATED, null, Map.of("tagsChanged", true));
        photoIndexTaskService.scheduleIndexAfterCommit(ownerUserId, photoId);
    }

    /**
     * 移除照片标签。
     */
    @Transactional(rollbackFor = Exception.class)
    public void removeTag(UUID ownerUserId, UUID photoId, String tag) {
        photoTagRepository.deleteByOwnerUserIdAndPhotoIdAndTag(ownerUserId, photoId, tag);
        sideEffects.recordPhotoEvent(ownerUserId, photoId, SyncAction.UPDATED, null, Map.of("tagsChanged", true));
        photoIndexTaskService.scheduleIndexAfterCommit(ownerUserId, photoId);
    }

    /**
     * 按标签查询照片列表。
     */
    @Transactional(readOnly = true)
    public List<PhotoItemDto> listByTag(UUID ownerUserId, String tag) {
        List<UUID> photoIds = photoTagRepository.findByOwnerUserIdAndTagOrderByCreatedAtDesc(
                        ownerUserId,
                        tag,
                        PageRequest.of(0, photosRuntimeConfigService.legacyListLimit()))
                .stream()
                .map(PhotoTag::getPhotoId)
                .toList();
        if (photoIds.isEmpty()) {
            return List.of();
        }
        // IN 查询不保证顺序，按标签行（打标签时间倒序）重排，翻页与预览顺序才稳定。
        Map<UUID, PhotoItem> itemsById = photoItemRepository
                .findActiveByOwnerUserIdAndIdIn(ownerUserId, photoIds).stream()
                .collect(Collectors.toMap(PhotoItem::getId, item -> item, (left, right) -> left));
        List<PhotoItem> items = photoIds.stream()
                .map(itemsById::get)
                .filter(Objects::nonNull)
                .toList();
        return photoDtoAssembler.mapPhotoItemDtos(ownerUserId, items, photoDtoAssembler.favoriteIdsFor(ownerUserId, photoIds(items)));
    }

    /**
     * 按标签分页查询照片列表。
     *
     * <p>删除过滤已下沉到查询：先分页再在内存里剔除软删照片会让单页条数不足 size、
     * totalElements 虚高，前端按总数翻页时会翻到空白页。</p>
     *
     * @param ownerUserId 用户标识
     * @param tag 标签名
     * @param page 页码，从零开始
     * @param size 每页条数
     * @return 标签照片分页
     */
    @Transactional(readOnly = true)
    public Page<PhotoItemDto> listByTagPage(UUID ownerUserId, String tag, int page, int size) {
        Page<PhotoTag> tagPage = photoTagRepository.findActiveByOwnerUserIdAndTag(
                ownerUserId,
                tag,
                PageRequest.of(PageClamps.safePage(page), PageClamps.safeSize(size)));
        if (tagPage.isEmpty()) {
            return new PageImpl<>(List.of(), tagPage.getPageable(), tagPage.getTotalElements());
        }
        List<UUID> photoIds = tagPage.getContent().stream().map(PhotoTag::getPhotoId).toList();
        // IN 查询不保证返回顺序，按标签行的排序（打标签时间倒序）重排，否则翻页顺序抖动。
        Map<UUID, PhotoItem> itemsById = photoItemRepository
                .findActiveByOwnerUserIdAndIdIn(ownerUserId, photoIds).stream()
                .collect(Collectors.toMap(PhotoItem::getId, item -> item, (left, right) -> left));
        List<PhotoItem> items = photoIds.stream()
                .map(itemsById::get)
                .filter(Objects::nonNull)
                .toList();
        List<PhotoItemDto> dtos = photoDtoAssembler.mapPhotoItemDtos(ownerUserId, items, photoDtoAssembler.favoriteIdsFor(ownerUserId, photoIds(items)));
        return new PageImpl<>(dtos, tagPage.getPageable(), tagPage.getTotalElements());
    }

    /**
     * 查询用户所有标签。
     */
    @Transactional(readOnly = true)
    public List<String> listTags(UUID ownerUserId) {
        return photoTagRepository.findDistinctTagsByOwnerUserId(ownerUserId);
    }

    /**
     * 按指定维度对照片进行分组。
     */
    @Transactional(readOnly = true)
    public List<PhotoGroupDto> groupBy(UUID ownerUserId, GroupBy groupBy) {
        return groupBy(ownerUserId, groupBy, PREVIEW_PAGE_MAX);
    }

    /**
     * 返回受分组数量上限约束的兼容版照片分组。
     *
     * @param ownerUserId 用户标识
     * @param groupBy 分组维度
     * @param maxGroups 最多返回的分组数量
     * @return 有界照片分组
     */
    @Transactional(readOnly = true)
    public List<PhotoGroupDto> groupBy(UUID ownerUserId, GroupBy groupBy, int maxGroups) {
        return groupByPage(ownerUserId, groupBy, 0, maxGroups).getContent();
    }

    /**
     * 按指定维度分页聚合照片，每组只返回最多四张轻量预览。
     *
     * @param ownerUserId 用户标识
     * @param groupBy 分组维度
     * @param page 页码，从零开始
     * @param size 每页分组数量
     * @return 照片分组分页
     */
    @Transactional(readOnly = true)
    public Page<PhotoGroupDto> groupByPage(UUID ownerUserId, GroupBy groupBy, int page, int size) {
        int safePage = Math.max(0, page);
        int safeSize = boundedPageSize(size);
        String zoneId = systemInstanceConfigService.timeZone().getId();
        List<PhotoGroupPreviewProjection> rows = photoItemRepository.findGroupPreviewPage(
                ownerUserId,
                groupBy.name(),
                zoneId,
                Math.multiplyFull(safePage, safeSize),
                safeSize
        );
        long totalGroups = photoItemRepository.countPhotoGroups(ownerUserId, groupBy.name(), zoneId);
        List<PhotoGroupDto> groups = mapPhotoGroups(ownerUserId, rows);
        return new PageImpl<>(groups, PageRequest.of(safePage, safeSize), totalGroups);
    }

    /**
     * 将照片实体转换为DTO，包含预签名缩略图URL和标签
     */
    PhotoItemDto toDto(PhotoItem photo, boolean favorite) {
        return toDto(photo, favorite, false);
    }

    private PhotoItemDto toDto(PhotoItem photo, boolean favorite, boolean includeContentAnalysis) {
        String coverUrl = resolveCoverUrl(photo.getOwnerUserId(), photo.getId(), photo.getCoverFileId());
        List<String> tags = photoTagRepository.findByOwnerUserIdAndPhotoId(photo.getOwnerUserId(), photo.getId())
                .stream()
                .map(PhotoTag::getTag)
                .toList();
        return PhotoItemDto.fromEntity(
                photo,
                coverUrl,
                favorite,
                tags,
                includeContentAnalysis
                        ? resolveSourceUrl(photo.getOwnerUserId(), photo.activeOrSourceFileId())
                        : null,
                includeContentAnalysis
                        ? contentAnalysisService.current(photo.getOwnerUserId(), photo.getId())
                        : null,
                includeContentAnalysis
                        ? resolveMotionVideoUrl(photo)
                        : null
        );
    }

    /**
     * 解析动态照片的运动视频地址，仅在 READY 状态对派生节点签发下载地址。
     */
    private String resolveMotionVideoUrl(PhotoItem photo) {
        if (!PhotoMotionVideoService.STATE_READY.equals(photo.getMotionState())
                || photo.getMotionVideoFileNodeId() == null) {
            return null;
        }
        try {
            return fileQueryService.createDownloadUrl(
                    photo.getOwnerUserId(),
                    photo.getMotionVideoFileNodeId()
            ).downloadUrl();
        } catch (Exception ex) {
            log.warn("解析动态视频地址失败: fileNodeId={}", photo.getMotionVideoFileNodeId(), ex);
            return null;
        }
    }

    private Page<PhotoListItemDto> mapListPage(
            UUID ownerUserId,
            Page<PhotoListItemProjection> page,
            boolean favoritePage
    ) {
        List<PhotoListItemDto> items = photoDtoAssembler.mapListItems(ownerUserId, page.getContent(), favoritePage);
        return new PageImpl<>(items, page.getPageable(), page.getTotalElements());
    }

    private List<PhotoTimelineMonthDto> mapTimelineMonths(
            UUID ownerUserId,
            List<PhotoTimelinePreviewProjection> rows
    ) {
        List<PhotoListItemDto> previews = photoDtoAssembler.mapListItems(ownerUserId, rows, false);
        Map<UUID, PhotoListItemDto> previewById = previews.stream()
                .collect(Collectors.toMap(PhotoListItemDto::id, item -> item));
        Map<String, List<PhotoTimelinePreviewProjection>> groupedRows = new LinkedHashMap<>();
        for (PhotoTimelinePreviewProjection row : rows) {
            String groupKey = row.getYear() + "-" + row.getMonth();
            groupedRows.computeIfAbsent(groupKey, ignored -> new ArrayList<>()).add(row);
        }
        return groupedRows.values().stream()
                .map(groupRows -> {
                    PhotoTimelinePreviewProjection first = groupRows.getFirst();
                    List<PhotoListItemDto> groupPreviews = groupRows.stream()
                            .map(row -> previewById.get(row.getId()))
                            .filter(Objects::nonNull)
                            .toList();
                    int photoCount = (int) Math.min(Integer.MAX_VALUE, first.getPhotoCount());
                    return new PhotoTimelineMonthDto(
                            first.getYear(),
                            first.getMonth(),
                            photoCount,
                            groupPreviews
                    );
                })
                .toList();
    }

    private List<PhotoGroupDto> mapPhotoGroups(
            UUID ownerUserId,
            List<PhotoGroupPreviewProjection> rows
    ) {
        List<PhotoListItemDto> previews = photoDtoAssembler.mapListItems(ownerUserId, rows, false);
        Map<UUID, PhotoListItemDto> previewById = previews.stream()
                .collect(Collectors.toMap(
                        PhotoListItemDto::id,
                        item -> item,
                        (first, ignored) -> first,
                        LinkedHashMap::new
                ));
        Map<String, List<PhotoGroupPreviewProjection>> groupedRows = new LinkedHashMap<>();
        for (PhotoGroupPreviewProjection row : rows) {
            groupedRows.computeIfAbsent(row.getGroupKey(), ignored -> new ArrayList<>()).add(row);
        }
        return groupedRows.values().stream()
                .map(groupRows -> {
                    PhotoGroupPreviewProjection first = groupRows.getFirst();
                    List<PhotoItemDto> groupPreviews = groupRows.stream()
                            .map(row -> previewById.get(row.getId()))
                            .filter(Objects::nonNull)
                            .map(photoDtoAssembler::toLegacyPhotoItem)
                            .toList();
                    int photoCount = (int) Math.min(Integer.MAX_VALUE, first.getPhotoCount());
                    return new PhotoGroupDto(first.getGroupKey(), photoCount, groupPreviews);
                })
                .toList();
    }

    private Pageable photoPageable(int page, int size, String sortExpression) {
        int safePage = Math.max(0, page);
        int safeSize = boundedPageSize(size);
        String[] sortParts = sortExpression == null ? new String[0] : sortExpression.split(",", 2);
        String requestedField = sortParts.length == 0 || sortParts[0].isBlank()
                ? "createdAt"
                : sortParts[0].trim();
        String sortField = SORT_FIELDS.get(requestedField);
        if (sortField == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "照片排序字段不合法");
        }
        Sort.Direction direction = sortParts.length > 1
                ? parseSortDirection(sortParts[1])
                : Sort.Direction.DESC;
        Sort sort = Sort.by(direction, sortField).and(Sort.by(Sort.Direction.ASC, "id"));
        return PageRequest.of(safePage, safeSize, sort);
    }

    private int boundedPageSize(int size) {
        // 时间线/分组预览页单页条目上限取域内 100，避免预览卡片一次拉过多。
        return PageClamps.safeSize(size, PREVIEW_PAGE_MAX);
    }

    private Sort.Direction parseSortDirection(String direction) {
        if ("asc".equalsIgnoreCase(direction.trim())) {
            return Sort.Direction.ASC;
        }
        if ("desc".equalsIgnoreCase(direction.trim())) {
            return Sort.Direction.DESC;
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "照片排序方向不合法");
    }

    private String normalizeQuery(String query) {
        if (query == null || query.isBlank()) {
            return null;
        }
        // 走 LIKE 的查询词按字面量处理，配套的查询必须声明 escape 符。
        return LikePatterns.escapeSpecials(query.trim());
    }

    private String resolveCoverUrl(UUID ownerUserId, UUID photoId, UUID coverFileId) {
        if (coverFileId == null) {
            return null;
        }
        try {
            FileDownloadUrlDto url = fileQueryService.createDownloadUrl(ownerUserId, coverFileId);
            return url.downloadUrl();
        } catch (Exception ex) {
            log.warn("解析封面 URL 失败: photoId={}, coverFileId={}", photoId, coverFileId, ex);
            return null;
        }
    }

    private String resolveSourceUrl(UUID ownerUserId, UUID fileNodeId) {
        try {
            return fileQueryService.createDownloadUrl(ownerUserId, fileNodeId).downloadUrl();
        } catch (Exception ex) {
            log.warn("解析照片原图 URL 失败: fileNodeId={}", fileNodeId, ex);
            return null;
        }
    }


}
