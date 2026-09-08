package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.domain.MediaContentPurpose;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileContentAccessService;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FilePurgeOrigin;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.file.service.LegacyObjectReference;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.service.PhotoInputGuard;
import com.omninest.modules.reader.domain.ReaderBookshelf;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPageAsset;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDetailDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderProgressDto;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateItemMetadataRequest;
import com.omninest.modules.reader.dto.ReaderFileTicketDto;
import com.omninest.modules.reader.repository.ReaderAnnotationRepository;
import com.omninest.modules.reader.repository.ReaderBookmarkRepository;
import com.omninest.modules.reader.repository.ReaderBookshelfRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderNoteRepository;
import com.omninest.modules.reader.repository.ReaderCatalogNodeRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageAssetRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import com.omninest.modules.reader.repository.ReaderReadingSessionRepository;
import com.omninest.modules.reader.repository.ReaderTextChapterRepository;
import com.omninest.modules.task.service.TaskRecordService;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;

/**
 * 阅读条目服务：条目查询、元数据更新、封面上传、文件下载与删除。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ReaderItemService {

    private static final long MAX_COVER_BYTES = 20L * 1024 * 1024;

    private final ReaderItemRepository itemRepository;
    private final ReaderProgressRepository progressRepository;
    private final ReaderBookshelfRepository bookshelfRepository;
    private final ReaderBookmarkRepository bookmarkRepository;
    private final ReaderAnnotationRepository annotationRepository;
    private final ReaderNoteRepository noteRepository;
    private final ReaderReadingSessionRepository sessionRepository;
    private final ReaderPageAssetRepository pageAssetRepository;
    private final ReaderPageRepository pageRepository;
    private final ReaderCatalogNodeRepository catalogRepository;
    private final ReaderItemSourceRepository sourceRepository;
    private final ReaderTextChapterRepository textChapterRepository;
    private final TaskRecordService taskRecordService;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final FileQueryService fileQueryService;
    private final FileContentAccessService fileContentAccessService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final FileDeletionService fileDeletionService;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final MediaSyncEventService syncEventService;
    private final PhotoInputGuard photoInputGuard;

    /**
     * 列出阅读条目，支持按类型、内容类型和关键词过滤。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemType    条目类型过滤（EPUB / TXT / CBZ），可为 null
     * @param contentKind 内容类型过滤（TEXT / COMIC），可为 null
     * @param query       标题关键词，可为 null
     * @return 条目 DTO 列表
     */
    public List<ReaderItemDto> listItems(UUID ownerUserId, String itemType, String contentKind, String query) {
        // 查询用户可见的所有条目（个人空间 + 共享空间）
        List<ReaderItem> items = itemRepository.findItemsVisibleToUser(ownerUserId, SpaceType.SHARED);

        // 按类型过滤
        if (itemType != null && !itemType.isBlank()) {
            items = items.stream()
                    .filter(item -> itemType.equalsIgnoreCase(item.getItemType()))
                    .toList();
        }

        // 按内容类型过滤
        if (contentKind != null && !contentKind.isBlank()) {
            items = items.stream()
                    .filter(item -> contentKind.equalsIgnoreCase(item.getContentKind()))
                    .toList();
        }

        // 按关键词过滤
        if (query != null && !query.isBlank()) {
            String lowerQuery = query.toLowerCase();
            items = items.stream()
                    .filter(item -> item.getTitle() != null && item.getTitle().toLowerCase().contains(lowerQuery))
                    .toList();
        }

        // 批量查询书架状态（1 次查询替代 N 次）
        List<UUID> itemIds = items.stream().map(ReaderItem::getId).toList();
        Set<UUID> bookshelfItemIds = bookshelfRepository
                .findByOwnerUserIdAndReaderItemIdIn(ownerUserId, itemIds)
                .stream()
                .map(ReaderBookshelf::getReaderItemId)
                .collect(Collectors.toSet());

        // 批量查询文件节点空间类型（1 次查询替代 N 次）
        List<UUID> fileNodeIds = items.stream()
                .map(ReaderItem::getFileNodeId)
                .filter(Objects::nonNull)
                .distinct()
                .toList();
        Map<UUID, String> spaceTypeMap = fileMetadataQueryService.findAllByIds(fileNodeIds)
                .stream()
                .collect(Collectors.toMap(
                        FileDescriptor::id,
                        file -> file.spaceType().getValue()
                ));

        // 批量查询阅读进度（1 次查询替代 N 次）
        Map<UUID, ReaderProgress> progressMap = items.isEmpty()
                ? Map.of()
                : progressRepository.findByOwnerUserIdAndReaderItemIdIn(ownerUserId, itemIds)
                        .stream()
                        .collect(Collectors.toMap(
                                ReaderProgress::getReaderItemId,
                                p -> p
                        ));

        return items.stream()
                .map(item -> toDto(
                        item,
                        bookshelfItemIds.contains(item.getId()),
                        spaceTypeMap,
                        progressMap
                ))
                .toList();
    }

    /**
     * 获取条目详情（含当前阅读进度）。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemId      条目 ID
     * @return 条目详情 DTO
     */
    public ReaderItemDetailDto getItemDetail(UUID ownerUserId, UUID itemId) {
        ReaderItem item = requireItem(ownerUserId, itemId);
        boolean onBookshelf = bookshelfRepository.existsByOwnerUserIdAndReaderItemId(ownerUserId, itemId);
        ReaderProgress progress = progressRepository
                .findByOwnerUserIdAndReaderItemId(ownerUserId, itemId)
                .orElse(null);
        ReaderItemDto itemDto = toDto(
                item,
                onBookshelf,
                null,
                progress == null ? Map.of() : Map.of(item.getId(), progress)
        );
        ReaderProgressDto progressDto = progress == null
                ? null
                : new ReaderProgressDto(
                        progress.getCharOffset(),
                        progress.getProgressPercent(),
                        progress.getReadingMode(),
                        progress.getChapterId(),
                        progress.getPageId(),
                        progress.getPageIndex(),
                        progress.getPageFingerprint(),
                        progress.getSourceId(),
                        progress.getSourcePageIndex(),
                        progress.getCatalogKey(),
                        progress.getManifestVersion(),
                        progress.getIntraPageOffset(),
                        progress.getUpdatedAt()
                );
        return new ReaderItemDetailDto(itemDto, progressDto);
    }

    /**
     * 从书库删除当前用户拥有的阅读条目，默认保留源文件。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemId      条目 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID deleteItem(UUID ownerUserId, UUID itemId) {
        return deleteItem(ownerUserId, itemId, false);
    }

    /**
     * 删除阅读条目；仅在明确启用级联时永久删除源文件。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemId 条目 ID
     * @param cascade 是否允许级联清理其他业务引用
     * @return 任务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID deleteItem(UUID ownerUserId, UUID itemId, boolean cascade) {
        ReaderItem item = itemRepository.findByIdAndOwnerUserId(itemId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在或无权删除"));
        if (!cascade) {
            return deleteLibraryItem(ownerUserId, item);
        }
        UUID taskId = fileDeletionService.deletePermanently(
                ownerUserId,
                item.getFileNodeId(),
                cascade,
                new FilePurgeOrigin("READER", itemId),
                null
        );
        log.info("阅读条目永久删除任务已创建: taskId={}, userId={}, itemId={}, fileNodeId={}",
                taskId, ownerUserId, itemId, item.getFileNodeId());
        return taskId;
    }

    private UUID deleteLibraryItem(UUID ownerUserId, ReaderItem item) {
        UUID itemId = item.getId();
        List<UUID> itemIds = List.of(itemId);
        List<ReaderItemSource> sources = sourceRepository.findByReaderItemId(itemId);
        List<UUID> sourceFileIds = new ArrayList<>();
        if (item.getFileNodeId() != null) {
            sourceFileIds.add(item.getFileNodeId());
        }
        sourceFileIds.addAll(sources.stream()
                .map(ReaderItemSource::getFileNodeId)
                .filter(Objects::nonNull)
                .toList());
        taskRecordService.cancelActiveResourceTasks(
                ownerUserId,
                "FILE_NODE",
                sourceFileIds.stream().distinct().toList(),
                List.of("QUEUED", "RUNNING", "RETRY_WAIT"),
                "FILE_PURGE"
        );
        List<ReaderPageAsset> pageAssets = List.copyOf(
                pageAssetRepository.findByReaderItemIdIn(itemIds)
        );
        progressRepository.deleteByReaderItemIdIn(itemIds);
        bookshelfRepository.deleteByReaderItemIdIn(itemIds);
        bookmarkRepository.deleteByReaderItemIdIn(itemIds);
        annotationRepository.deleteByReaderItemIdIn(itemIds);
        noteRepository.deleteByReaderItemIdIn(itemIds);
        sessionRepository.deleteByReaderItemIdIn(itemIds);
        pageRepository.deleteByReaderItemIdIn(itemIds);
        catalogRepository.deleteByReaderItemIdIn(itemIds);
        sourceRepository.deleteByReaderItemIdIn(itemIds);
        textChapterRepository.deleteByReaderItemIdIn(itemIds);
        itemRepository.delete(item);
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                "READER_ITEM_DELETE",
                "local.reader.item.delete",
                "DELETING",
                "READER_ITEM",
                itemId,
                Map.of("itemId", itemId.toString(), "sourceFilesRetained", true)
        );
        taskRecordService.markCompleted(taskId, Map.of("sourceFilesRetained", true));
        syncEventService.invalidate(ownerUserId, SyncScope.READER, "READER_LIBRARY", Map.of());
        registerPageAssetCleanupAfterCommit(pageAssets);
        log.info("阅读条目已删除并保留源文件: userId={}, itemId={}", ownerUserId, itemId);
        return taskId;
    }

    private void registerPageAssetCleanupAfterCommit(List<ReaderPageAsset> assets) {
        if (assets.isEmpty()) {
            return;
        }
        Runnable cleanup = () -> {
            boolean allDeleted = true;
            for (ReaderPageAsset asset : assets) {
                try {
                    derivedAssetStorageService.deleteObject(
                            new LegacyObjectReference(asset.getBucketName(), asset.getObjectKey())
                    );
                } catch (RuntimeException exception) {
                    allDeleted = false;
                    log.warn("阅读旧页面对象清理失败，将保留资产记录: assetId={}, errorType={}",
                            asset.getId(), exception.getClass().getSimpleName());
                }
            }
            if (!allDeleted) {
                return;
            }
            try {
                pageAssetRepository.deleteAllById(assets.stream().map(ReaderPageAsset::getId).toList());
            } catch (RuntimeException exception) {
                log.warn("阅读页面资产元数据清理失败: assetCount={}, errorType={}",
                        assets.size(), exception.getClass().getSimpleName());
            }
        };
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            cleanup.run();
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                cleanup.run();
            }
        });
    }

    /**
     * 更新条目元数据。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemId      条目 ID
     * @param request     更新请求
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateMetadata(UUID ownerUserId, UUID itemId, UpdateItemMetadataRequest request) {
        if (request == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "元数据更新请求参数不能为空");
        }
        ReaderItem item = requireOwnedItem(ownerUserId, itemId);
        applyMetadataUpdate(item, request);
        itemRepository.save(item);
        recordItemEvent(ownerUserId, item, SyncAction.UPDATED);
        log.info("更新条目元数据: userId={}, itemId={}", ownerUserId, itemId);
    }

    /**
     * 管理员更新任意条目元数据（不校验所有权）。
     *
     * @param itemId   条目 ID
     * @param request  更新请求
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateMetadataAsAdmin(UUID itemId, UpdateItemMetadataRequest request) {
        if (request == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "元数据更新请求参数不能为空");
        }
        ReaderItem item = itemRepository.findById(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在"));
        applyMetadataUpdate(item, request);
        itemRepository.save(item);
        recordItemEvent(item.getOwnerUserId(), item, SyncAction.UPDATED);
        log.info("管理员更新条目元数据: itemId={}", itemId);
    }

    /**
     * 将元数据更新请求应用到条目实体。
     */
    private void applyMetadataUpdate(ReaderItem item, UpdateItemMetadataRequest request) {
        if (request.title() != null && !request.title().isBlank()) {
            item.setTitle(request.title());
        }
        if (request.authorName() != null) {
            item.setAuthorName(request.authorName());
        }
        if (request.description() != null) {
            item.setDescription(request.description());
        }
        if (request.publisher() != null) {
            item.setPublisher(request.publisher());
        }
        if (request.language() != null) {
            item.setLanguage(request.language());
        }
    }

    /**
     * 上传封面图片。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemId      条目 ID
     * @param file        上传的文件
     */
    @Transactional(rollbackFor = Exception.class)
    public void uploadCover(UUID ownerUserId, UUID itemId, MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面文件不能为空");
        }
        if (file.getSize() <= 0 || file.getSize() > MAX_COVER_BYTES) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面文件大小超出限制");
        }
        ReaderItem item = requireOwnedItem(ownerUserId, itemId);
        Path staged = null;
        try {
            staged = Files.createTempFile("omninest-reader-cover-", ".upload");
            file.transferTo(staged);
            photoInputGuard.inspectForDecode(staged, file.getOriginalFilename());
            String extension = getExtension(file.getOriginalFilename()).toLowerCase(Locale.ROOT);
            String mimeType = switch (extension) {
                case ".jpg", ".jpeg" -> "image/jpeg";
                case ".png" -> "image/png";
                case ".webp" -> "image/webp";
                case ".gif" -> "image/gif";
                case ".bmp" -> "image/bmp";
                case ".tif", ".tiff" -> "image/tiff";
                default -> throw new BusinessException(ErrorCode.PARAM_ERROR, "封面格式不受支持");
            };
            try (InputStream data = Files.newInputStream(staged)) {
                String fileName = "cover_" + itemId + getExtension(file.getOriginalFilename());
                UUID coverFileId = derivedAssetStorageService.store(
                        ownerUserId, "READER_ITEM", itemId, "COVER", fileName,
                        mimeType, data);
                item.setCoverFileId(coverFileId);
                itemRepository.save(item);
                recordItemEvent(ownerUserId, item, SyncAction.UPDATED);
                log.info("上传封面: userId={}, itemId={}", ownerUserId, itemId);
            }
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "封面文件读取失败");
        } finally {
            if (staged != null) {
                try {
                    Files.deleteIfExists(staged);
                } catch (IOException exception) {
                    log.warn("Reader 封面临时文件清理失败: itemId={}", itemId, exception);
                }
            }
        }
    }

    /**
     * 从已有的文件节点设置封面。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemId      条目 ID
     * @param fileNodeId  文件节点 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void setCoverFromFile(UUID ownerUserId, UUID itemId, UUID fileNodeId) {
        ReaderItem item = requireOwnedItem(ownerUserId, itemId);
        FileDescriptor coverFile = fileLifecycleGuard.requireReadable(ownerUserId, fileNodeId);
        if (coverFile.mimeType() == null || !coverFile.mimeType().toLowerCase().startsWith("image/")) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面必须是图片文件");
        }
        item.setCoverFileId(fileNodeId);
        itemRepository.save(item);
        recordItemEvent(ownerUserId, item, SyncAction.UPDATED);
        log.info("从文件节点设置封面: userId={}, itemId={}, fileNodeId={}", ownerUserId, itemId, fileNodeId);
    }

    /**
     * 校验封面访问权限并准备流式下载描述。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemId 条目 ID
     * @return 封面流式下载描述
     */
    public DownloadDescriptor prepareCoverDownload(UUID ownerUserId, UUID itemId) {
        ReaderItem item = requireItem(ownerUserId, itemId);
        if (item.getCoverFileId() == null) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "条目无封面");
        }
        FileDescriptor fileNode = fileMetadataQueryService.findById(item.getCoverFileId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "封面文件不存在"));
        if (fileNode.deleted() || !"FILE".equals(fileNode.nodeType())) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "封面文件不存在");
        }
        if (fileNode.sizeBytes() > MAX_COVER_BYTES) {
            throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "封面文件超过读取限制");
        }
        String contentType = fileNode.mimeType();
        if (contentType == null || contentType.isBlank()) {
            contentType = "image/jpeg";
        }
        return new DownloadDescriptor(
                ownerUserId,
                fileNode.id(),
                fileNode.name(),
                fileNode.sizeBytes(),
                fileMetadataQueryService.findContentSha256(fileNode.id()).orElse(null),
                contentType,
                true
        );
    }

    /**
     * 查找条目并校验访问权限（个人拥有 或 共享空间文件）。
     */
    public ReaderItem requireItem(UUID ownerUserId, UUID itemId) {
        ReaderItem item = itemRepository.findById(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在"));
        if (item.getFileNodeId() == null) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "阅读条目未关联源文件");
        }
        fileLifecycleGuard.requireReadable(ownerUserId, item.getFileNodeId());
        return item;
    }

    /**
     * 查找当前用户拥有且源文件仍可修改的阅读条目。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemId 条目 ID
     * @return 阅读条目
     */
    public ReaderItem requireOwnedItem(UUID ownerUserId, UUID itemId) {
        ReaderItem item = itemRepository.findById(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在"));
        if (!ownerUserId.equals(item.getOwnerUserId())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权修改此阅读条目");
        }
        if (item.getFileNodeId() == null) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "阅读条目未关联源文件");
        }
        fileLifecycleGuard.requireOwnedWritable(ownerUserId, item.getFileNodeId());
        return item;
    }

    /**
     * 实体转 DTO（无预加载数据，进度为空）。
     */
    public ReaderItemDto toDto(ReaderItem item, boolean addedToBookshelf) {
        return toDto(item, addedToBookshelf, null, null);
    }

    /**
     * 实体转 DTO（使用预加载的空间类型映射，避免逐条查询文件节点）。
     *
     * @param item          阅读条目
     * @param addedToBookshelf 是否已加入书架
     * @param spaceTypeMap  文件节点 ID → 空间类型值 的预加载映射
     * @return 条目 DTO
     */
    public ReaderItemDto toDto(ReaderItem item, boolean addedToBookshelf, Map<UUID, String> spaceTypeMap) {
        return toDto(item, addedToBookshelf, spaceTypeMap, null);
    }

    /**
     * 实体转 DTO（使用预加载的空间类型映射与进度映射，避免逐条查询）。
     *
     * @param item          阅读条目
     * @param addedToBookshelf 是否已加入书架
     * @param spaceTypeMap  文件节点 ID → 空间类型值 的预加载映射
     * @param progressMap   阅读条目 ID → 进度 的预加载映射，可为 null
     * @return 条目 DTO
     */
    public ReaderItemDto toDto(
            ReaderItem item,
            boolean addedToBookshelf,
            Map<UUID, String> spaceTypeMap,
            Map<UUID, ? extends ReaderProgress> progressMap
    ) {
        String coverUrl = item.getCoverFileId() != null
                ? "/files/" + item.getCoverFileId() + "/download-url"
                : null;

        // 从预加载映射获取空间类型，默认 PERSONAL
        String spaceType = "PERSONAL";
        if (item.getFileNodeId() != null && spaceTypeMap != null && spaceTypeMap.containsKey(item.getFileNodeId())) {
            spaceType = spaceTypeMap.get(item.getFileNodeId());
        } else if (item.getFileNodeId() != null) {
            spaceType = fileMetadataQueryService.findById(item.getFileNodeId())
                    .map(file -> file.spaceType().getValue())
                    .orElse("PERSONAL");
        }
        ReaderProgress progress = progressMap != null ? progressMap.get(item.getId()) : null;
        Double progressPercent = progress != null && progress.getProgressPercent() != null
                ? progress.getProgressPercent().doubleValue()
                : null;

        return new ReaderItemDto(
                item.getId(),
                item.getItemType(),
                item.getContentKind(),
                item.getTitle(),
                item.getAuthorName(),
                coverUrl,
                item.getDescription(),
                item.getPublisher(),
                item.getLanguage(),
                item.getRating(),
                item.getCreatedAt(),
                item.getUpdatedAt(),
                addedToBookshelf,
                progressPercent,
                spaceType,
                item.getManifestVersion(),
                item.getImportStatus(),
                item.getParseErrorCode(),
                item.getParseErrorMessage()
        );
    }

    /**
     * 创建阅读源文件临时下载票据。
     *
     * @param ownerUserId 当前用户标识
     * @param itemId 阅读条目标识
     * @return 临时下载票据
     */
    public ReaderFileTicketDto createFileTicket(UUID ownerUserId, UUID itemId) {
        DownloadDescriptor descriptor = prepareDownload(ownerUserId, itemId);
        FileDownloadUrlDto download = fileQueryService.createReadableDownloadUrl(
                ownerUserId,
                descriptor.fileNodeId()
        );
        return new ReaderFileTicketDto(
                itemId,
                descriptor.fileName(),
                download.downloadUrl(),
                descriptor.sizeBytes(),
                descriptor.sha256(),
                download.expiresAt()
        );
    }

    /**
     * 校验阅读条目访问权限并准备流式下载描述。
     *
     * @param ownerUserId 当前用户标识
     * @param itemId 阅读条目标识
     * @return 流式下载描述
     */
    public DownloadDescriptor prepareDownload(UUID ownerUserId, UUID itemId) {
        ReaderItem item = requireItem(ownerUserId, itemId);
        if (item.getFileNodeId() == null) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "条目未关联文件");
        }
        FileDescriptor fileNode = fileLifecycleGuard.requireReadable(ownerUserId, item.getFileNodeId());
        // 使用条目标题和文件扩展名构建下载文件名
        String downloadFileName = buildDownloadFileName(item.getTitle(), fileNode.name());
        return new DownloadDescriptor(
                ownerUserId,
                fileNode.id(),
                downloadFileName,
                fileNode.sizeBytes(),
                fileMetadataQueryService.findContentSha256(fileNode.id()).orElse(null),
                fileNode.mimeType(),
                false
        );
    }

    /**
     * 将阅读源文件传输到响应输出流。
     *
     * @param descriptor 下载描述
     * @param outputStream 响应输出流
     * @throws IOException 对象读取或客户端连接写入失败
     */
    public void streamFile(DownloadDescriptor descriptor, OutputStream outputStream) throws IOException {
        try (FileContentStream content = descriptor.mediaAsset()
                ? fileContentAccessService.openAuthorizedMediaStream(
                        descriptor.fileNodeId(),
                        MediaContentPurpose.MEDIA_ASSET)
                : fileQueryService.openReadableFileContent(
                        descriptor.requesterUserId(),
                        descriptor.fileNodeId())) {
            content.inputStream().transferTo(outputStream);
        }
    }

    /**
     * 阅读源文件流式下载描述。
     *
     * @param requesterUserId 请求用户 ID
     * @param fileNodeId 文件节点 ID
     * @param fileName 下载文件名
     * @param sizeBytes 文件大小
     * @param sha256 文件摘要
     * @param contentType 内容类型
     * @param mediaAsset 是否作为已授权媒体资产读取
     * @author OmniNest
     */
    public record DownloadDescriptor(
            UUID requesterUserId,
            UUID fileNodeId,
            String fileName,
            long sizeBytes,
            String sha256,
            String contentType,
            boolean mediaAsset
    ) {
    }

    /**
     * 根据条目标题和原始文件名构建下载文件名。
     * 优先使用条目标题，保留原始文件扩展名。
     */
    private String buildDownloadFileName(String title, String originalFileName) {
        String extension = getExtension(originalFileName);
        if (title != null && !title.isBlank()) {
            return title + extension;
        }
        return originalFileName != null ? originalFileName : "download" + extension;
    }

    /**
     * 从文件名提取扩展名（含点号）。
     */
    private String getExtension(String fileName) {
        if (fileName == null || !fileName.contains(".")) {
            return "";
        }
        return fileName.substring(fileName.lastIndexOf('.'));
    }

    private void recordItemEvent(UUID ownerUserId, ReaderItem item, SyncAction action) {
        syncEventService.record(
                ownerUserId,
                SyncScope.READER,
                "READER_ITEM",
                item.getId().toString(),
                action,
                item.getVersion(),
                Map.of()
        );
    }
}
