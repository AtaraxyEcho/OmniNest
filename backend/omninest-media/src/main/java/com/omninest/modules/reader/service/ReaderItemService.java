package com.omninest.modules.reader.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import com.omninest.common.api.PageClamps;
import com.omninest.common.util.LikePatterns;
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

import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.service.PhotoInputGuard;
import com.omninest.modules.reader.domain.ReaderBookshelf;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPageAsset;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.domain.ReaderTextChapter;
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
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
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
import org.springframework.data.domain.Pageable;
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

    /** reader_items.genres 里存放标签列表的键 */
    private static final String GENRES_ITEMS_KEY = "items";

    /** reader_items.external_ids 里存放连载状态的键 */
    private static final String SERIAL_STATUS_KEY = "serialStatus";

    /** reader_items.external_ids 里存放 ISBN 的键 */
    private static final String ISBN_KEY = "isbn";


    private final MediaProcessingLimitsProperties processingLimits;
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
    public Page<ReaderItemDto> listItemsPage(
            UUID ownerUserId, String itemType, String contentKind, String query,
            boolean bookshelfOnly, int page, int size) {
        Pageable pageable = PageRequest.of(PageClamps.safePage(page), PageClamps.safeSize(size));
        String normalizedQuery = query == null || query.isBlank()
                ? ""
                : LikePatterns.escapeSpecials(query.trim());
        Page<ReaderItem> itemPage = itemRepository.findVisibleItemsPage(
                ownerUserId,
                SpaceType.SHARED,
                itemType == null ? "" : itemType.trim(),
                contentKind == null ? "" : contentKind.trim(),
                normalizedQuery,
                bookshelfOnly,
                pageable
        );
        if (itemPage.isEmpty()) {
            return new PageImpl<>(List.of(), itemPage.getPageable(), itemPage.getTotalElements());
        }
        List<ReaderItem> pageItems = itemPage.getContent();
        List<UUID> itemIds = pageItems.stream().map(ReaderItem::getId).toList();
        Set<UUID> shelfIds = bookshelfOnly
                ? Set.copyOf(itemIds)
                : bookshelfItemIds(ownerUserId, itemIds);
        List<UUID> fileNodeIds = pageItems.stream()
                .map(ReaderItem::getFileNodeId)
                .filter(Objects::nonNull)
                .distinct()
                .toList();
        Map<UUID, String> spaceTypeMap = fileNodeIds.isEmpty()
                ? Map.of()
                : fileMetadataQueryService.findAllByIds(fileNodeIds)
                        .stream()
                        .collect(Collectors.toMap(
                                FileDescriptor::id,
                                file -> file.spaceType().getValue()
                        ));
        Map<UUID, ReaderProgress> progressMap = progressRepository
                .findByOwnerUserIdAndReaderItemIdIn(ownerUserId, itemIds)
                .stream()
                .collect(Collectors.toMap(ReaderProgress::getReaderItemId, progress -> progress));
        List<ReaderItemDto> dtos = pageItems.stream()
                .map(item -> toDto(item, shelfIds.contains(item.getId()), spaceTypeMap, progressMap))
                .toList();
        return new PageImpl<>(dtos, itemPage.getPageable(), itemPage.getTotalElements());
    }

    public List<ReaderItemDto> listItems(UUID ownerUserId, String itemType, String contentKind, String query) {
        return listItems(ownerUserId, itemType, contentKind, query, false);
    }

    /**
     * 列出阅读条目，支持按类型、内容类型、关键词过滤，并可只保留已加入书架的条目。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemType 条目类型过滤（EPUB / TXT / CBZ），可为 null
     * @param contentKind 内容类型过滤（TEXT / COMIC），可为 null
     * @param query 标题或作者关键词，可为 null
     * @param bookshelfOnly 为 true 时只返回已加入书架的条目
     * @return 条目 DTO 列表
     */
    public List<ReaderItemDto> listItems(
            UUID ownerUserId, String itemType, String contentKind, String query, boolean bookshelfOnly) {
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

        // 按关键词过滤：书名与作者都要匹配。书库搜索下沉服务端分页后，这里少一个字段
        // 就等于把原先客户端在已加载窗口里做的匹配能力缩小。
        if (query != null && !query.isBlank()) {
            String lowerQuery = query.toLowerCase();
            items = items.stream()
                    .filter(item -> containsIgnoreCase(item.getTitle(), lowerQuery)
                            || containsIgnoreCase(item.getAuthorName(), lowerQuery))
                    .toList();
        }

        // 批量查询书架状态（1 次查询替代 N 次）
        List<UUID> itemIds = items.stream().map(ReaderItem::getId).toList();
        Set<UUID> bookshelfItemIds = bookshelfItemIds(ownerUserId, itemIds);
        // 书架过滤必须发生在分页之前：留在分页之后会让一页里可能一个书架条目都没有，
        // 前端只能不断续拉凑列表，总数也会算进未加架条目。
        if (bookshelfOnly) {
            items = items.stream()
                    .filter(item -> bookshelfItemIds.contains(item.getId()))
                    .toList();
            itemIds = items.stream().map(ReaderItem::getId).toList();
        }

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
        if (!cascade || item.getFileNodeId() == null) {
            return deleteLibraryItem(ownerUserId, item);
        }
        // 多卷漫画的"源文件"是全部卷：只提交主卷会让其余分卷留在网盘，
        // 清理参与者看到还有分卷存活就只抽走一卷，作品永远删不掉。
        List<UUID> volumeFileIds = cascadeFileNodeIds(ownerUserId, item);
        FilePurgeOrigin origin = new FilePurgeOrigin("READER", itemId);
        UUID taskId = volumeFileIds.size() == 1
                ? fileDeletionService.deletePermanently(
                        ownerUserId, volumeFileIds.getFirst(), cascade, origin, null)
                : fileDeletionService.deletePermanentlyBatch(
                        ownerUserId, volumeFileIds, cascade, List.of(origin));
        log.info("阅读条目永久删除任务已创建: taskId={}, userId={}, itemId={}, fileNodeCount={}",
                taskId, ownerUserId, itemId, volumeFileIds.size());
        return taskId;
    }

    /**
     * 收集整本书可以随条目永久删除的源文件节点。
     *
     * <p>主文件永远保留在结果里（批量与单节点删除都以它的归属判定权限，行为与改动前一致）；
     * 其余分卷只收当前用户自己拥有的节点，别人上传的分卷仍由网盘侧管理，塞进同一批会让整本
     * 删除直接失败。
     */
    private List<UUID> cascadeFileNodeIds(UUID ownerUserId, ReaderItem item) {
        LinkedHashSet<UUID> candidates = new LinkedHashSet<>();
        candidates.add(item.getFileNodeId());
        sourceRepository.findByReaderItemId(item.getId()).stream()
                .map(ReaderItemSource::getFileNodeId)
                .filter(Objects::nonNull)
                .filter(fileNodeId -> !fileNodeId.equals(item.getFileNodeId()))
                .filter(fileNodeId -> fileMetadataQueryService.findById(fileNodeId)
                        .map(descriptor -> ownerUserId.equals(descriptor.ownerUserId()))
                        .orElse(false))
                .forEach(candidates::add);
        return List.copyOf(candidates);
    }

    private UUID deleteLibraryItem(UUID ownerUserId, ReaderItem item) {
        UUID itemId = item.getId();
        List<UUID> itemIds = List.of(itemId);
        // 删除条目时封面必须一起清：派生封面不在网盘里，任何清理任务都不会再枚举它。
        UUID coverFileId = unreferencedCoverFileId(item);
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
        // 文本书籍的解析任务挂在 READER_ITEM 资源上，只按 FILE_NODE 取消会留下无人认领的在途任务。
        taskRecordService.cancelActiveResourceTasks(
                ownerUserId,
                "READER_ITEM",
                itemIds,
                List.of("QUEUED", "RUNNING", "RETRY_WAIT"),
                "FILE_PURGE"
        );
        List<ReaderPageAsset> pageAssets = List.copyOf(
                pageAssetRepository.findByReaderItemIdIn(itemIds)
        );
        List<UUID> chapterAssetIds = textChapterRepository.findByReaderItemIdIn(itemIds).stream()
                .map(ReaderTextChapter::getContentFileNodeId)
                .filter(Objects::nonNull)
                .toList();
        progressRepository.deleteByReaderItemIdIn(itemIds);
        bookshelfRepository.deleteByReaderItemIdIn(itemIds);
        bookmarkRepository.deleteByReaderItemIdIn(itemIds);
        annotationRepository.deleteByReaderItemIdIn(itemIds);
        noteRepository.deleteByReaderItemIdIn(itemIds);
        sessionRepository.deleteByReaderItemIdIn(itemIds);
        // 与 deleteItemsCompletely 同一顺序：先页面对象再页面，否则残留的资产元数据指向已消失的页面
        pageAssetRepository.deleteByReaderItemIdIn(itemIds);
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
        registerChapterAssetCleanupAfterCommit(chapterAssetIds);
        registerCoverCleanupAfterCommit(coverFileId, null);
        log.info("阅读条目已删除并保留源文件: userId={}, itemId={}", ownerUserId, itemId);
        return taskId;
    }

    /**
     * 取可以随条目一起清理的封面节点。
     *
     * <p>导入去重后不同条目会共用同一份派生封面：删一本就把共用的封面清掉，
     * 另一本会永久破图，因此只有"没有别的条目引用"时才放行清理。
     *
     * @param item 即将删除或替换封面的条目
     * @return 可清理的封面节点 ID；为空表示没有封面或仍被引用
     */
    private UUID unreferencedCoverFileId(ReaderItem item) {
        UUID coverFileId = item.getCoverFileId();
        if (coverFileId == null) {
            return null;
        }
        long referencingOthers = itemRepository.findByCoverFileIdIn(List.of(coverFileId)).stream()
                .filter(candidate -> !candidate.getId().equals(item.getId()))
                .count();
        if (referencingOthers > 0) {
            log.info("派生封面仍被其他阅读条目引用，跳过清理: coverFileId={}, others={}",
                    coverFileId, referencingOthers);
            return null;
        }
        return coverFileId;
    }

    /**
     * 事务提交后删除被替换或被随条目移除的派生封面节点。
     *
     * <p>对象删除必须在提交之后：提交失败回滚时条目仍指向旧封面，先把对象删掉
     * 就只剩一个指向空对象的节点。同一路径的派生存储会原地复用同一个 FileNode，
     * 因此"新旧同一个节点"时绝不能清——那会把刚写好的封面一起删掉。
     * 删除失败只记日志，不能把已经成功的写入回报为失败。
     *
     * @param previousCoverFileId 被替换或被随条目移除的封面节点 ID
     * @param currentCoverFileId 条目现在指向的封面节点 ID；null 表示条目已删除
     */
    private void registerCoverCleanupAfterCommit(
            UUID previousCoverFileId,
            UUID currentCoverFileId) {
        if (previousCoverFileId == null || previousCoverFileId.equals(currentCoverFileId)) {
            return;
        }
        Runnable cleanup = () -> {
            try {
                derivedAssetStorageService.deleteDerivedFileNode(previousCoverFileId);
            } catch (RuntimeException exception) {
                log.warn("阅读派生封面清理失败: coverFileId={}, errorType={}",
                        previousCoverFileId, exception.getClass().getSimpleName());
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

    private void registerPageAssetCleanupAfterCommit(List<ReaderPageAsset> assets) {
        if (assets.isEmpty()) {
            return;
        }
        Runnable cleanup = () -> {
            boolean allDeleted = true;
            for (ReaderPageAsset asset : assets) {
                try {
                    derivedAssetStorageService.deleteDerivedFileNode(asset.getFileNodeId());
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
     * 事务提交后删除 TXT 每章正文派生节点。
     *
     * <p>章节行随条目一起删除，节点引用只有在这里还能拿到；单个对象删除失败只记录，
     * 不能把已经成功的条目删除回报为失败。
     *
     * @param fileNodeIds 待删除的派生节点 ID
     */
    private void registerChapterAssetCleanupAfterCommit(List<UUID> fileNodeIds) {
        if (fileNodeIds.isEmpty()) {
            return;
        }
        Runnable cleanup = () -> {
            for (UUID fileNodeId : fileNodeIds) {
                try {
                    derivedAssetStorageService.deleteDerivedFileNode(fileNodeId);
                } catch (RuntimeException exception) {
                    log.warn("TXT 章节正文对象清理失败: errorType={}",
                            exception.getClass().getSimpleName());
                }
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
     * 管理员更新条目元数据。
     *
     * <p>管理权只覆盖公共共享空间：他人私人空间（PERSONAL）的条目一律按不存在处理，
     * 管理员不得借该入口篡改用户私人书库。</p>
     *
     * @param operatorUserId 操作者用户 ID
     * @param itemId         条目 ID
     * @param request        更新请求
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateMetadataAsAdmin(UUID operatorUserId, UUID itemId, UpdateItemMetadataRequest request) {
        if (request == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "元数据更新请求参数不能为空");
        }
        ReaderItem item = itemRepository.findById(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在"));
        if (!item.getOwnerUserId().equals(operatorUserId)) {
            String spaceType = item.getFileNodeId() == null
                    ? null
                    : fileMetadataQueryService.findById(item.getFileNodeId())
                            .map(file -> file.spaceType().getValue())
                            .orElse(null);
            if (!SpaceType.SHARED.getValue().equals(spaceType)) {
                throw new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在");
            }
        }
        applyMetadataUpdate(item, request);
        itemRepository.save(item);
        recordItemEvent(item.getOwnerUserId(), item, SyncAction.UPDATED);
        log.info("管理员更新条目元数据: operatorUserId={}, itemId={}", operatorUserId, itemId);
    }

    /**
     * 将元数据更新请求应用到条目实体。
     *
     * <p>分类标签写在 reader_items.genres 的 items 键，连载状态与 ISBN 写在 external_ids，
     * 与影视/音乐模块同一套 JSONB 形状；这些字段必须同时能被读回，否则编辑页保存成功、字段却静默丢弃。
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
        if (request.releaseDate() != null) {
            item.setReleaseDate(request.releaseDate());
        }
        if (request.rating() != null) {
            item.setRating(request.rating());
        }
        if (request.genres() != null) {
            Map<String, Object> genres = item.getGenres() == null
                    ? new LinkedHashMap<>()
                    : new LinkedHashMap<>(item.getGenres());
            genres.put(GENRES_ITEMS_KEY, request.genres().stream()
                    .filter(Objects::nonNull)
                    .map(value -> value.trim())
                    .filter(value -> !value.isEmpty())
                    .toList());
            item.setGenres(genres);
        }
        if (request.serialStatus() != null || request.isbn() != null) {
            Map<String, Object> externalIds = item.getExternalIds() == null
                    ? new LinkedHashMap<>()
                    : new LinkedHashMap<>(item.getExternalIds());
            if (request.serialStatus() != null) {
                externalIds.put(SERIAL_STATUS_KEY, request.serialStatus().trim());
            }
            if (request.isbn() != null) {
                externalIds.put(ISBN_KEY, request.isbn().trim());
            }
            item.setExternalIds(externalIds);
        }
    }

    /**
     * 关键词命中判定：值为空按不命中处理，入参已是小写。
     */
    private boolean containsIgnoreCase(String value, String lowerQuery) {
        return value != null && value.toLowerCase().contains(lowerQuery);
    }

    /**
     * 从 genres JSONB 中取出标签列表，形状不符时按空列表处理而不是抛出。
     */
    private List<String> extractGenres(ReaderItem item) {
        if (item.getGenres() == null) {
            return List.of();
        }
        Object raw = item.getGenres().get(GENRES_ITEMS_KEY);
        if (!(raw instanceof Collection<?> values)) {
            return List.of();
        }
        return values.stream().filter(Objects::nonNull).map(String::valueOf).toList();
    }

    /**
     * 从 external_ids JSONB 中取出字符串值。
     */
    private String extractExternalString(ReaderItem item, String key) {
        if (item.getExternalIds() == null) {
            return null;
        }
        Object value = item.getExternalIds().get(key);
        return value == null ? null : String.valueOf(value);
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
        if (file.getSize() <= 0 || file.getSize() > processingLimits.getMaxReaderCoverBytes()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面文件大小超出限制");
        }
        ReaderItem item = requireOwnedItem(ownerUserId, itemId);
        UUID previousCoverFileId = unreferencedCoverFileId(item);
        Path staged = null;
        try {
            staged = Files.createTempFile("omninest-reader-cover-", ".upload");
            file.transferTo(staged);
            photoInputGuard.inspectForDecode(staged, file.getOriginalFilename());
            String extension = getExtension(file.getOriginalFilename()).toLowerCase(Locale.ROOT);
            // 只放行各端渲染器都能直接解码的位图：TIFF 在此前会被接受，
            // 存下来后客户端 Image.memory 解不开，封面永远显示成错误占位。
            String mimeType = switch (extension) {
                case ".jpg", ".jpeg" -> "image/jpeg";
                case ".png" -> "image/png";
                case ".webp" -> "image/webp";
                case ".gif" -> "image/gif";
                case ".bmp" -> "image/bmp";
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
                registerCoverCleanupAfterCommit(previousCoverFileId, coverFileId);
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
        // 与 prepareCoverDownload 同一份白名单：SVG 在这里放行会变成"设封面成功但封面永远 400"，
        // 因为内联直出只接受位图，避免给同源可执行类型开一条通道。
        String coverMimeType = coverFile.mimeType();
        String normalizedType = coverMimeType == null
                ? ""
                : coverMimeType.toLowerCase(Locale.ROOT);
        if (!normalizedType.startsWith("image/") || normalizedType.contains("svg")) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面仅支持位图类图片");
        }
        UUID previousCoverFileId = unreferencedCoverFileId(item);
        item.setCoverFileId(fileNodeId);
        itemRepository.save(item);
        recordItemEvent(ownerUserId, item, SyncAction.UPDATED);
        registerCoverCleanupAfterCommit(previousCoverFileId, fileNodeId);
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
        if (fileNode.sizeBytes() > processingLimits.getMaxReaderCoverBytes()) {
            throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "封面文件超过读取限制");
        }
        String contentType = fileNode.mimeType();
        if (contentType == null || contentType.isBlank()) {
            contentType = "image/jpeg";
        }
        // 封面以内联方式直出：仅放行位图类图片，svg 等浏览器可执行类型拒绝，
        // 阻断把上传文件设为封面获得同源 inline image/svg+xml 的通道
        String normalizedType = contentType.toLowerCase(Locale.ROOT);
        if (!normalizedType.startsWith("image/") || normalizedType.contains("svg")) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "封面仅支持位图类图片");
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
     * 批量查询用户已加入书架的条目 ID（1 次查询替代逐条判断）。
     *
     * @param ownerUserId 所属用户 ID
     * @param itemIds 待判定条目 ID
     * @return 已在书架上的条目 ID 集合
     */
    @Transactional(readOnly = true)
    public Set<UUID> bookshelfItemIds(UUID ownerUserId, Collection<UUID> itemIds) {
        if (itemIds.isEmpty()) {
            return Set.of();
        }
        return bookshelfRepository.findByOwnerUserIdAndReaderItemIdIn(ownerUserId, itemIds)
                .stream()
                .map(ReaderBookshelf::getReaderItemId)
                .collect(Collectors.toSet());
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
                item.getFileNodeId(),
                item.getItemType(),
                item.getContentKind(),
                item.getTitle(),
                item.getAuthorName(),
                coverUrl,
                item.getDescription(),
                item.getPublisher(),
                item.getLanguage(),
                item.getRating(),
                item.getReleaseDate(),
                extractGenres(item),
                extractExternalString(item, SERIAL_STATUS_KEY),
                extractExternalString(item, ISBN_KEY),
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
                        MediaContentPurpose.MEDIA_ASSET,
                        descriptor.requesterUserId())
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
