package com.omninest.modules.video.service;

import com.omninest.modules.media.domain.AssetType;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.modules.video.domain.ContentAsset;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.service.DerivedAssetRequest;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.MovieContentAssetDto;
import com.omninest.modules.video.dto.MovieDtos.ScrapeCandidateDto;
import com.omninest.modules.video.repository.ContentAssetRepository;
import java.time.Instant;
import java.net.URI;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.Semaphore;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

@Slf4j
@Service
@RequiredArgsConstructor
public class ContentAssetService {
    private static final int SCREENSHOT_DOWNLOAD_PARALLELISM = 4;
    private final ContentAssetRepository contentAssetRepository;
    private final FileQueryService fileQueryService;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final PlatformTransactionManager transactionManager;

    @Transactional(rollbackFor = Exception.class)
    public void syncPrimaryVideoAssets(MediaVideoItem item, ScrapeCandidateDto candidate) {
        // 已废弃：元数据资产现在通过 syncPrimaryMovieAssets / syncPrimarySeriesAssets 同步到逻辑实体
    }

    @Async("mediaAsyncExecutor")
    public void syncVideoScreenshots(MediaVideoItem item, List<String> screenshotUrls, String provider, String externalId) {
        if (item == null || item.getId() == null || screenshotUrls == null || screenshotUrls.isEmpty()) {
            return;
        }
        List<ContentAsset> existing = contentAssetRepository.findByOwnerUserIdAndResourceTypeAndResourceIdAndAssetType(
                item.getOwnerUserId(), ResourceType.VIDEO_ITEM.getValue(), item.getId(), AssetType.SCREENSHOT.getValue());
        Set<String> existingUrls = existing.stream()
                .map(ContentAsset::getExternalUrl)
                .filter(url -> url != null && !url.isBlank())
                .collect(Collectors.toSet());
        int sortOrder = existing.size();
        Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("provider", provider);
        metadata.put("externalId", externalId);
        metadata.put("scrapedAt", Instant.now().toString());

        // 远程下载与派生入库先于任何事务完成：不能一边占着数据库连接一边等外部图片。
        record DownloadedScreenshot(String url, int sortOrder, UUID fileNodeId) {
        }
        Semaphore downloadPermits = new Semaphore(SCREENSHOT_DOWNLOAD_PARALLELISM);
        List<Callable<DownloadedScreenshot>> tasks = new ArrayList<>();
        int nextSortOrder = sortOrder;
        for (String url : screenshotUrls) {
            String normalizedUrl = url == null ? "" : url.trim();
            if (normalizedUrl.isBlank() || existingUrls.contains(normalizedUrl)) {
                continue;
            }
            int currentSortOrder = nextSortOrder++;
            tasks.add(() -> {
                downloadPermits.acquireUninterruptibly();
                try {
                    UUID fileNodeId = storeRemoteAsset(
                            item.getOwnerUserId(),
                            item.getId(),
                            AssetType.SCREENSHOT.getValue(),
                            normalizedUrl,
                            provider
                    );
                    return fileNodeId == null
                            ? null
                            : new DownloadedScreenshot(normalizedUrl, currentSortOrder, fileNodeId);
                } finally {
                    downloadPermits.release();
                }
            });
        }
        if (tasks.isEmpty()) {
            return;
        }

        List<DownloadedScreenshot> downloaded = new ArrayList<>(tasks.size());
        try (ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor()) {
            List<Future<DownloadedScreenshot>> futures;
            try {
                futures = executor.invokeAll(tasks);
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                return;
            }
            for (Future<DownloadedScreenshot> future : futures) {
                try {
                    DownloadedScreenshot screenshot = future.get();
                    if (screenshot != null) {
                        downloaded.add(screenshot);
                    }
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                    return;
                } catch (ExecutionException exception) {
                    log.warn("单张剧照预取失败，跳过: itemId={}, errorType={}",
                            item.getId(), exception.getCause() == null
                                    ? exception.getClass().getSimpleName()
                                    : exception.getCause().getClass().getSimpleName());
                }
            }
        }

        TransactionTemplate txTemplate = new TransactionTemplate(transactionManager);
        txTemplate.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        int added = 0;
        for (DownloadedScreenshot screenshot : downloaded) {
            try {
                txTemplate.executeWithoutResult(status -> {
                    ContentAsset asset = new ContentAsset();
                    asset.setOwnerUserId(item.getOwnerUserId());
                    asset.setResourceType(ResourceType.VIDEO_ITEM.getValue());
                    asset.setResourceId(item.getId());
                    asset.setAssetType(AssetType.SCREENSHOT.getValue());
                    asset.setExternalUrl(screenshot.url());
                    asset.setProvider(provider);
                    asset.setSortOrder(screenshot.sortOrder());
                    asset.setPrimary(false);
                    asset.setMetadata(metadata);
                    asset.setFileNodeId(screenshot.fileNodeId());
                    contentAssetRepository.save(asset);
                });
                added++;
            } catch (RuntimeException exception) {
                log.warn("单张剧照落库失败，跳过: itemId={}, errorType={}",
                        item.getId(), exception.getClass().getSimpleName());
            }
        }
        if (added > 0) {
            log.info("剧照同步完成: itemId={}, added={}, total={}", item.getId(), added, nextSortOrder);
        }
    }

    @Transactional(readOnly = true)
    public Map<UUID, Map<String, MovieContentAssetDto>> primaryVideoAssets(
            UUID ownerUserId,
            Collection<UUID> videoItemIds
    ) {
        return primaryAssets(ownerUserId, ResourceType.VIDEO_ITEM.getValue(), videoItemIds);
    }

    /**
     * 同步电影主海报/背景图。
     *
     * <p>刻意不加 {@code @Transactional}：外部图片下载与入库是分钟级网络 I/O，事务会整段
     * 占住数据库连接；两条派生写入各自带事务（{@code DerivedAssetStorageService} 用
     * REQUIRES_NEW，仓储保存各自成事务），调用方若已有事务仍会照常加入。</p>
     */
    public SeriesAssetResult syncPrimarySeriesAssets(UUID ownerUserId, UUID seriesId, ScrapeCandidateDto candidate) {
        if (ownerUserId == null || seriesId == null || candidate == null) {
            return new SeriesAssetResult(null, null);
        }
        Map<String, Object> metadata = candidateMetadata(candidate);
        try (ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor()) {
            Future<UUID> poster = executor.submit(() -> upsertPrimaryAssetWithType(
                    ownerUserId, seriesId, ResourceType.TV_SERIES.getValue(),
                    AssetType.POSTER.getValue(), candidate.posterUrl(),
                    candidate.provider(), metadata, 0));
            Future<UUID> backdrop = executor.submit(() -> upsertPrimaryAssetWithType(
                    ownerUserId, seriesId, ResourceType.TV_SERIES.getValue(),
                    AssetType.BACKDROP.getValue(), candidate.backdropUrl(),
                    candidate.provider(), metadata, 1));
            return new SeriesAssetResult(getQuietly(poster), getQuietly(backdrop));
        }
    }

    /**
     * 同步系列主海报/背景图，事务口径同 {@link #syncPrimarySeriesAssets}。
     */
    public MovieAssetResult syncPrimaryMovieAssets(UUID movieId, UUID ownerUserId, ScrapeCandidateDto candidate) {
        if (ownerUserId == null || movieId == null || candidate == null) {
            return new MovieAssetResult(null, null);
        }
        Map<String, Object> metadata = candidateMetadata(candidate);
        try (ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor()) {
            Future<UUID> poster = executor.submit(() -> upsertPrimaryAssetWithType(
                    ownerUserId, movieId, ResourceType.MOVIE.getValue(),
                    AssetType.POSTER.getValue(), candidate.posterUrl(),
                    candidate.provider(), metadata, 0));
            Future<UUID> backdrop = executor.submit(() -> upsertPrimaryAssetWithType(
                    ownerUserId, movieId, ResourceType.MOVIE.getValue(),
                    AssetType.BACKDROP.getValue(), candidate.backdropUrl(),
                    candidate.provider(), metadata, 1));
            return new MovieAssetResult(getQuietly(poster), getQuietly(backdrop));
        }
    }

    private UUID getQuietly(Future<UUID> future) {
        try {
            return future.get();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return null;
        } catch (ExecutionException exception) {
            log.warn("并行同步主资产异常: errorType={}",
                    exception.getCause() == null
                            ? exception.getClass().getSimpleName()
                            : exception.getCause().getClass().getSimpleName());
            return null;
        }
    }

    /**
     * 从已入库文件设置主资源。
     *
     * @param ownerUserId 所属用户 ID
     * @param resourceId 业务资源 ID
     * @param resourceType 业务资源类型
     * @param assetType 资源类型
     * @param fileNodeId 文件节点 ID
     * @return 文件节点 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID setPrimaryFileAsset(
            UUID ownerUserId,
            UUID resourceId,
            String resourceType,
            String assetType,
            UUID fileNodeId
    ) {
        if (ownerUserId == null || resourceId == null || fileNodeId == null) {
            return null;
        }
        // 入参来自用户提交的元数据表单：必须先确认文件归当前用户且是图片，
        // 否则资源上会挂一个别人（或不存在的）文件，后续按公开资产分发时取到错图。
        fileQueryService.validateOwnedImage(ownerUserId, fileNodeId);
        ContentAsset asset = contentAssetRepository
                .findPrimaryAsset(ownerUserId, resourceType, resourceId, assetType)
                .orElseGet(ContentAsset::new);
        asset.setOwnerUserId(ownerUserId);
        asset.setResourceType(resourceType);
        asset.setResourceId(resourceId);
        asset.setAssetType(assetType);
        asset.setFileNodeId(fileNodeId);
        asset.setExternalUrl(null);
        asset.setProvider("MANUAL");
        asset.setSortOrder(0);
        asset.setPrimary(true);
        asset.setMetadata(Map.of("manual", true, "updatedAt", Instant.now().toString()));
        contentAssetRepository.save(asset);
        return fileNodeId;
    }

    public record SeriesAssetResult(UUID posterFileId, UUID backdropFileId) {}

    public record MovieAssetResult(UUID posterFileId, UUID backdropFileId) {}

    @Transactional(readOnly = true)
    public Map<UUID, Map<String, MovieContentAssetDto>> primarySeriesAssets(
            UUID ownerUserId,
            Collection<UUID> seriesIds
    ) {
        return primaryAssets(ownerUserId, ResourceType.TV_SERIES.getValue(), seriesIds);
    }

    @Transactional(readOnly = true)
    public Map<UUID, Map<String, MovieContentAssetDto>> primaryMovieAssets(
            UUID ownerUserId,
            Collection<UUID> movieIds
    ) {
        return primaryAssets(ownerUserId, ResourceType.MOVIE.getValue(), movieIds);
    }

    @Transactional(readOnly = true)
    public Map<String, MovieContentAssetDto> primaryVideoAssets(UUID ownerUserId, UUID videoItemId) {
        if (videoItemId == null) {
            return Map.of();
        }
        return primaryVideoAssets(ownerUserId, List.of(videoItemId)).getOrDefault(videoItemId, Map.of());
    }

    @Transactional(readOnly = true)
    public List<MovieContentAssetDto> allVideoAssets(UUID ownerUserId, UUID videoItemId) {
        if (ownerUserId == null || videoItemId == null) {
            return List.of();
        }
        return contentAssetRepository
                .findAllByOwnerUserIdAndResourceTypeAndResourceId(ownerUserId, ResourceType.VIDEO_ITEM.getValue(), videoItemId)
                .stream()
                .map(asset -> toDto(ownerUserId, asset))
                .toList();
    }

    private Map<UUID, Map<String, MovieContentAssetDto>> primaryAssets(
            UUID ownerUserId,
            String resourceType,
            Collection<UUID> resourceIds
    ) {
        if (ownerUserId == null || resourceIds == null || resourceIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, Map<String, MovieContentAssetDto>> grouped = new LinkedHashMap<>();
        contentAssetRepository
                .listPrimaryAssets(
                        ownerUserId,
                        resourceType,
                        resourceIds,
                        List.of(AssetType.POSTER.getValue(), AssetType.BACKDROP.getValue())
                )
                .stream()
                .forEach(asset -> grouped
                        .computeIfAbsent(asset.getResourceId(), ignored -> new LinkedHashMap<>())
                        .putIfAbsent(asset.getAssetType(), toDto(ownerUserId, asset)));
        return grouped;
    }

    private UUID upsertPrimaryAsset(
            UUID ownerUserId,
            UUID resourceId,
            String assetType,
            String externalUrl,
            String provider,
            Map<String, Object> metadata,
            int sortOrder
    ) {
        return upsertPrimaryAssetWithType(ownerUserId, resourceId, ResourceType.VIDEO_ITEM.getValue(),
                assetType, externalUrl, provider, metadata, sortOrder);
    }

    private UUID upsertPrimaryAssetWithType(
            UUID ownerUserId,
            UUID resourceId,
            String resourceType,
            String assetType,
            String externalUrl,
            String provider,
            Map<String, Object> metadata,
            int sortOrder
    ) {
        if (ownerUserId == null || resourceId == null || externalUrl == null || externalUrl.isBlank()) {
            return null;
        }
        ContentAsset asset = contentAssetRepository
                .findPrimaryAsset(ownerUserId, resourceType, resourceId, assetType)
                .orElseGet(ContentAsset::new);
        String normalizedExternalUrl = externalUrl.trim();
        UUID fileNodeId = asset.getFileNodeId();
        if (fileNodeId == null || !normalizedExternalUrl.equals(asset.getExternalUrl())) {
            UUID storedFileNodeId = storeRemoteAssetWithType(ownerUserId, resourceId, resourceType, assetType, normalizedExternalUrl, provider);
            if (storedFileNodeId != null) {
                fileNodeId = storedFileNodeId;
            }
        }
        asset.setOwnerUserId(ownerUserId);
        asset.setResourceType(resourceType);
        asset.setResourceId(resourceId);
        asset.setAssetType(assetType);
        asset.setFileNodeId(fileNodeId);
        asset.setExternalUrl(normalizedExternalUrl);
        asset.setProvider(provider);
        asset.setSortOrder(sortOrder);
        asset.setPrimary(true);
        asset.setMetadata(metadata);
        contentAssetRepository.save(asset);
        return fileNodeId;
    }

    private UUID storeRemoteAsset(UUID ownerUserId, UUID resourceId, String assetType, String externalUrl, String provider) {
        return storeRemoteAssetWithType(ownerUserId, resourceId, ResourceType.VIDEO_ITEM.getValue(), assetType, externalUrl, provider);
    }

    private UUID storeRemoteAssetWithType(UUID ownerUserId, UUID resourceId, String resourceType, String assetType, String externalUrl, String provider) {
        try {
            return derivedAssetStorageService.storeRemote(new DerivedAssetRequest(
                    ownerUserId,
                    externalUrl,
                    resourceType,
                    resourceId,
                    assetType,
                    uniqueFileName(assetType, externalUrl),
                    "image/jpeg",
                    SpaceType.PERSONAL
            ));
        } catch (RuntimeException ex) {
            log.warn("媒体资源下载入库失败，保留外部资源降级: provider={}, resourceId={}, assetType={}, message={}",
                    provider, resourceId, assetType, ex.getMessage());
            return null;
        }
    }

    private String uniqueFileName(String assetType, String externalUrl) {
        String ext = extension(externalUrl);
        String path;
        try {
            path = URI.create(externalUrl).getPath();
        } catch (IllegalArgumentException ex) {
            return assetType.toLowerCase(Locale.ROOT) + "-" + UUID.randomUUID() + ext;
        }
        if (path != null) {
            int lastSlash = path.lastIndexOf('/');
            if (lastSlash >= 0 && lastSlash < path.length() - 1) {
                String baseName = path.substring(lastSlash + 1);
                int dotIndex = baseName.lastIndexOf('.');
                if (dotIndex > 0) {
                    baseName = baseName.substring(0, dotIndex);
                }
                if (!baseName.isBlank()) {
                    return baseName + ext;
                }
            }
        }
        return assetType.toLowerCase(Locale.ROOT) + "-" + UUID.randomUUID() + ext;
    }

    private Map<String, Object> candidateMetadata(ScrapeCandidateDto candidate) {
        Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("provider", candidate.provider());
        metadata.put("externalId", candidate.externalId());
        metadata.put("title", candidate.title());
        metadata.put("scrapedAt", Instant.now().toString());
        return metadata;
    }

    private MovieContentAssetDto toDto(UUID ownerUserId, ContentAsset asset) {
        return new MovieContentAssetDto(
                asset.getId(),
                asset.getAssetType(),
                asset.getFileNodeId(),
                assetUrl(ownerUserId, asset),
                asset.getProvider(),
                asset.getLanguage(),
                asset.isPrimary(),
                asset.getMetadata() == null ? Map.of() : asset.getMetadata()
        );
    }

    private String assetUrl(UUID ownerUserId, ContentAsset asset) {
        if (asset.getFileNodeId() != null) {
            try {
                FileDownloadUrlDto downloadUrl = fileQueryService.createDownloadUrl(ownerUserId, asset.getFileNodeId());
                return downloadUrl.downloadUrl();
            } catch (RuntimeException ex) {
                log.debug("MinIO 资源 URL 解析失败，降级到外部 URL: assetId={}, fileNodeId={}, message={}",
                        asset.getId(), asset.getFileNodeId(), ex.getMessage());
            }
        }
        if (asset.getExternalUrl() != null && !asset.getExternalUrl().isBlank()) {
            return asset.getExternalUrl();
        }
        return null;
    }

    private String extension(String externalUrl) {
        String path;
        try {
            path = URI.create(externalUrl).getPath();
        } catch (IllegalArgumentException ex) {
            return ".jpg";
        }
        if (path == null) {
            return ".jpg";
        }
        int dotIndex = path.lastIndexOf('.');
        if (dotIndex < 0 || dotIndex == path.length() - 1) {
            return ".jpg";
        }
        String extension = path.substring(dotIndex).toLowerCase(Locale.ROOT);
        return switch (extension) {
            case ".jpg", ".jpeg", ".png", ".webp", ".avif" -> extension;
            default -> ".jpg";
        };
    }
}
