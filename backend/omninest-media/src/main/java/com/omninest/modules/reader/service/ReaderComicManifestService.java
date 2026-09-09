package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderCatalogNode;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPage;
import com.omninest.modules.reader.domain.ReaderPageAsset;
import com.omninest.modules.reader.domain.ReaderSourceStatus;
import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.repository.ReaderCatalogNodeRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.service.ComicPageAssetService.PageDownloadDescriptor;
import com.omninest.modules.reader.service.ReaderComicManifestDtos.ComicCatalogDto;
import com.omninest.modules.reader.service.ReaderComicManifestDtos.ComicManifestDto;
import com.omninest.modules.reader.service.ReaderComicManifestDtos.ComicPageDto;
import com.omninest.modules.reader.service.ReaderComicManifestDtos.ComicParseTaskDto;
import com.omninest.modules.reader.service.ReaderComicManifestDtos.ComicSourceDto;
import com.omninest.modules.reader.service.ReaderComicArchiveParser.ImageEntry;
import com.omninest.modules.reader.service.ReaderEpubArchiveStager.StagedArchive;
import com.omninest.modules.reader.service.model.ComicManifestDraft;
import com.omninest.modules.reader.service.model.ComicManifestDraft.ComicCatalogDraftNode;
import com.omninest.modules.reader.service.model.ComicManifestDraft.ComicPageDraft;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.io.IOException;
import java.io.OutputStream;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.function.IntConsumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 漫画清单生成服务：解析 CBZ/ZIP 文件，生成来源、目录树、页面记录。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderComicManifestService {

    private final ReaderItemRepository itemRepository;
    private final ReaderItemSourceRepository sourceRepository;
    private final ReaderCatalogNodeRepository catalogRepository;
    private final ReaderPageRepository pageRepository;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final ReaderComicArchiveParser archiveParser;
    private final ComicManifestBuilder manifestBuilder;
    private final ComicPageAssetService pageAssetService;
    private final ReaderArchiveSafetyPolicy archiveSafetyPolicy;
    private final ReaderEpubArchiveStager epubArchiveStager;
    private final TaskDispatchService taskDispatchService;
    private final TaskRecordService taskRecordService;
    private final MediaSyncEventService syncEventService;
    private final ReaderCoverExtractionService coverExtractionService;

    /**
     * 为已导入的漫画条目生成清单。
     * 支持增量合并：同一 fileNodeId 幂等返回，不同 fileNodeId 合并来源和页面。
     * 从所有来源的目录结构重建层次化目录树。
     *
     * @param item 漫画条目（itemType 为 CBZ 或 ZIP）
     * @return 生成的来源记录
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderItemSource generateManifest(ReaderItem item) {
        if (item.getFileNodeId() == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "条目无关联文件");
        }
        return addSource(item.getId(), item.getFileNodeId(), item.getContentHash(), item.getItemType());
    }

    /**
     * 确保漫画来源解析任务已入队。
     *
     * <p>该方法用于兼容旧的生成清单接口。请求线程只创建或唤醒来源记录，
     * 实际解析由 Worker 异步执行，避免阅读页或详情页同步解析大文件。
     *
     * @param item 漫画条目
     */
    @Transactional(rollbackFor = Exception.class)
    public void enqueueManifestParse(ReaderItem item) {
        if (item.getFileNodeId() == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "条目无关联文件");
        }

        ReaderItem lockedItem = itemRepository.findByIdForUpdate(item.getId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "条目不存在"));
        ReaderItemSource source = findOrCreatePendingSource(lockedItem);
        if (source.getStatus() == ReaderSourceStatus.READY) {
            refreshItemImportStatus(lockedItem.getId());
            return;
        }

        boolean sourceChanged = source.getStatus() != ReaderSourceStatus.PENDING
                || source.getErrorCode() != null
                || source.getErrorMessage() != null;
        source.setStatus(ReaderSourceStatus.PENDING);
        source.setErrorCode(null);
        source.setErrorMessage(null);
        if (sourceChanged) {
            sourceRepository.save(source);
        }

        lockedItem.setImportStatus("PARSING");
        itemRepository.save(lockedItem);

        enqueueParseTask(lockedItem, source, false);
    }

    /**
     * 重新解析漫画条目的所有来源。
     *
     * <p>重新解析只重建派生清单和页面数据，不创建新的阅读条目。
     * 已处于等待或解析中的来源保持当前任务，避免重复投递。
     *
     * @param itemId 漫画条目 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void enqueueManifestReparse(UUID itemId) {
        ReaderItem item = itemRepository.findByIdForUpdate(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "条目不存在"));
        if (!"COMIC".equalsIgnoreCase(item.getContentKind())) {
            return;
        }

        List<ReaderItemSource> sources = sourceRepository.findByReaderItemId(itemId);
        boolean createdPrimarySource = false;
        if (sources.isEmpty()) {
            if (item.getFileNodeId() == null) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "条目无关联文件");
            }
            sources = List.of(findOrCreatePendingSource(item));
            createdPrimarySource = true;
        }

        boolean hasQueuedSource = false;
        for (ReaderItemSource source : sources) {
            if (!createdPrimarySource
                    && (source.getStatus() == ReaderSourceStatus.PENDING
                    || source.getStatus() == ReaderSourceStatus.PARSING)) {
                hasQueuedSource = true;
                continue;
            }
            source.setStatus(ReaderSourceStatus.PENDING);
            source.setErrorCode(null);
            source.setErrorMessage(null);
            sourceRepository.save(source);
            enqueueParseTask(item, source, false);
            hasQueuedSource = true;
        }

        if (hasQueuedSource) {
            item.setImportStatus("PARSING");
            item.setParseErrorCode(null);
            item.setParseErrorMessage(null);
            itemRepository.save(item);
        }
    }

    /**
     * 为漫画作品添加新的来源文件并发布异步解析任务。
     *
     * <p>请求线程只创建来源记录和任务事件。页面解析、目录重建、派生图片写入
     * 统一由 Worker 调用 {@link #parseExistingSource(UUID, UUID)} 完成。
     *
     * @param itemId      漫画作品 ID
     * @param fileNodeId  新来源文件的 FileNode ID
     * @param contentHash 文件内容哈希
     * @param fileFormat  文件格式（CBZ/ZIP/EPUB）
     * @return 创建或已有的来源记录
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderItemSource addSource(UUID itemId, UUID fileNodeId, String contentHash, String fileFormat) {
        ReaderItem item = itemRepository.findByIdForUpdate(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "条目不存在"));
        ReaderItemSource existing = sourceRepository.findByReaderItemIdAndFileNodeId(itemId, fileNodeId)
                .orElse(null);
        if (existing != null) {
            if (existing.getStatus() == ReaderSourceStatus.READY
                    || existing.getStatus() == ReaderSourceStatus.PARSING
                    || existing.getStatus() == ReaderSourceStatus.PENDING) {
                log.info("来源已存在，跳过重复入队: itemId={}, fileNodeId={}", itemId, fileNodeId);
                return existing;
            }
            existing.setStatus(ReaderSourceStatus.PENDING);
            existing.setErrorCode(null);
            existing.setErrorMessage(null);
            sourceRepository.save(existing);
            item.setImportStatus("PARSING");
            itemRepository.save(item);
            enqueueParseTask(item, existing, false);
            return existing;
        }

        FileDescriptor fileNode = fileMetadataQueryService.findById(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));

        ReaderItemSource source = new ReaderItemSource();
        source.setReaderItemId(itemId);
        source.setFileNodeId(fileNodeId);
        source.setContentHash(contentHash);
        source.setFileFormat(fileFormat);
        source.setSourceName(fileNode.name());
        applySourceSortMetadata(source, fileNode.name());
        source.setStatus(ReaderSourceStatus.PENDING);
        sourceRepository.save(source);

        item.setImportStatus("PARSING");
        itemRepository.save(item);
        enqueueParseTask(item, source, false);

        log.info("漫画来源已入队解析: itemId={}, sourceId={}, fileNodeId={}, fileFormat={}",
                itemId, source.getId(), fileNodeId, fileFormat);
        return source;
    }

    /**
     * 统一重建漫画清单：排序来源、重排页面、重建目录、递增版本。
     * 委托给 ComicManifestBuilder 执行。
     *
     * @param itemId 漫画作品 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void rebuildComicManifest(UUID itemId) {
        manifestBuilder.rebuildComicManifest(itemId);
    }

    /**
     * 使用解析器目录草稿重建漫画清单。
     *
     * @param itemId 漫画作品 ID
     * @param catalogDrafts 目录草稿
     */
    @Transactional(rollbackFor = Exception.class)
    public void rebuildComicManifest(UUID itemId, List<ComicCatalogDraftNode> catalogDrafts) {
        manifestBuilder.rebuildComicManifest(itemId, catalogDrafts);
    }

    /**
     * 解析已经存在的来源记录。
     *
     * <p>异步导入和异步重试都通过该方法执行，保证 sourceId 稳定，不重复创建来源。
     *
     * @param itemId   漫画作品 ID
     * @param sourceId 来源 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void parseExistingSource(UUID itemId, UUID sourceId) {
        parseExistingSource(itemId, sourceId, ignored -> {
        });
    }

    /**
     * 解析已经存在的来源记录，并按阶段回报任务进度。
     *
     * @param itemId 漫画作品 ID
     * @param sourceId 来源 ID
     * @param progressReporter 任务进度回调
     */
    @Transactional(rollbackFor = Exception.class)
    public void parseExistingSource(UUID itemId, UUID sourceId, IntConsumer progressReporter) {
        progressReporter.accept(20);
        ReaderItemSource source = sourceRepository.findById(sourceId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "来源不存在"));
        if (!source.getReaderItemId().equals(itemId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "来源不属于该作品");
        }
        if (source.getStatus() == ReaderSourceStatus.READY) {
            refreshItemImportStatus(itemId);
            return;
        }

        source.setStatus(ReaderSourceStatus.PARSING);
        source.setErrorCode(null);
        source.setErrorMessage(null);
        sourceRepository.save(source);
        refreshItemImportStatus(itemId);

        List<ReaderPageAsset> previousPageAssets = pageAssetService.findPageAssets(source.getId());
        progressReporter.accept(30);
        if ("EPUB".equals(source.getFileFormat())) {
            EpubSourceParseResult parseResult = reparseEpubSource(source, progressReporter);
            if (source.getStatus() == ReaderSourceStatus.READY) {
                rebuildComicManifest(itemId, parseResult.catalogDrafts());
                progressReporter.accept(95);
                refreshItemImportStatus(itemId);
                persistCoverAfterCommit(itemId, parseResult.cover());
                cleanupPageAssetsAfterCommit(previousPageAssets);
                return;
            }
        } else {
            ReaderCoverDraft cover = reparseZipSource(source, progressReporter);
            if (source.getStatus() == ReaderSourceStatus.READY) {
                rebuildComicManifest(itemId);
                progressReporter.accept(95);
                refreshItemImportStatus(itemId);
                persistCoverAfterCommit(itemId, cover);
                cleanupPageAssetsAfterCommit(previousPageAssets);
                return;
            }
        }
        refreshItemImportStatus(itemId);
    }

    /**
     * 将未完成的漫画来源标记为失败，并刷新阅读条目聚合状态。
     *
     * @param itemId 阅读条目 ID
     * @param sourceId 漫画来源 ID
     * @param errorCode 稳定错误码
     * @param errorMessage 错误摘要
     */
    @Transactional(rollbackFor = Exception.class)
    public void markSourceFailed(
            UUID itemId,
            UUID sourceId,
            String errorCode,
            String errorMessage
    ) {
        ReaderItemSource source = sourceRepository.findById(sourceId).orElse(null);
        if (source != null && source.getStatus() != ReaderSourceStatus.READY) {
            source.setStatus(ReaderSourceStatus.FAILED);
            source.setErrorCode(errorCode);
            source.setErrorMessage(errorMessage);
            sourceRepository.save(source);
        }
        refreshItemImportStatus(itemId);
    }

    /**
     * 根据来源状态刷新条目的聚合导入状态。
     *
     * @param itemId 阅读条目 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void refreshItemImportStatus(UUID itemId) {
        ReaderItem item = itemRepository.findById(itemId).orElse(null);
        if (item == null) {
            return;
        }
        List<ReaderItemSource> sources = sourceRepository.findByReaderItemId(itemId);
        boolean hasParsing = false;
        boolean hasReady = false;
        boolean hasFailed = false;
        String firstErrorCode = null;
        String firstErrorMessage = null;

        for (ReaderItemSource source : sources) {
            switch (source.getStatus()) {
                case PENDING, PARSING -> hasParsing = true;
                case READY -> hasReady = true;
                case FAILED -> {
                    hasFailed = true;
                    if (firstErrorCode == null) {
                        firstErrorCode = source.getErrorCode();
                        firstErrorMessage = source.getErrorMessage();
                    }
                }
                default -> {
                }
            }
        }

        if (hasParsing) {
            item.setImportStatus("PARSING");
            item.setParseErrorCode(null);
            item.setParseErrorMessage(null);
        } else if (hasReady && hasFailed) {
            item.setImportStatus("PARTIAL_FAILED");
            item.setParseErrorCode(firstErrorCode);
            item.setParseErrorMessage(firstErrorMessage);
            item.setParsedAt(Instant.now());
        } else if (hasReady) {
            item.setImportStatus("READY");
            item.setParseErrorCode(null);
            item.setParseErrorMessage(null);
            item.setParsedAt(Instant.now());
        } else if (hasFailed) {
            item.setImportStatus("FAILED");
            item.setParseErrorCode(firstErrorCode);
            item.setParseErrorMessage(firstErrorMessage);
            item.setParsedAt(Instant.now());
        } else {
            item.setImportStatus("READY");
            item.setParseErrorCode(null);
            item.setParseErrorMessage(null);
        }
        itemRepository.save(item);
        syncEventService.invalidate(item.getOwnerUserId(), SyncScope.READER, "READER_LIBRARY", Map.of());
    }

    /**
     * 获取漫画清单（来源 + 目录 + 页面）。
     *
     * @param itemId 阅读条目 ID
     * @return 漫画清单 DTO
     */
    @Transactional(readOnly = true)
    public ComicManifestDto getManifest(UUID itemId) {
        return getManifest(null, itemId);
    }

    /**
     * 获取漫画清单及当前用户最近一次解析任务状态。
     *
     * @param ownerUserId 当前用户 ID，可为 null
     * @param itemId 阅读条目 ID
     * @return 漫画清单 DTO
     */
    @Transactional(readOnly = true)
    public ComicManifestDto getManifest(UUID ownerUserId, UUID itemId) {
        List<ReaderItemSource> sources = sourceRepository.findByReaderItemId(itemId);
        List<ReaderCatalogNode> catalog = catalogRepository.findByReaderItemIdOrderBySortIndex(itemId);
        List<ReaderPage> pages = pageRepository.findByReaderItemIdOrderByPageIndex(itemId);
        ReaderItem item = itemRepository.findById(itemId).orElse(null);
        int manifestVersion = item != null ? item.getManifestVersion() : 0;
        String importStatus = item != null ? item.getImportStatus() : "READY";
        ComicParseTaskDto parseTask = ownerUserId == null ? null : taskRecordService
                .findLatestTaskByPayload(ownerUserId, "COMIC_PARSE", "itemId", itemId)
                .map(this::toParseTaskDto)
                .orElse(null);
        return new ComicManifestDto(
                itemId,
                importStatus,
                manifestVersion,
                resolveReadingDirection(sources),
                sources.stream().map(this::toSourceDto).toList(),
                catalog.stream().map(this::toCatalogDto).toList(),
                pages.stream().map(this::toPageDto).toList(),
                parseTask);
    }

    /**
     * 校验漫画页面访问权限并准备流式下载描述。
     *
     * @param ownerUserId 请求用户 ID
     * @param pageId 页面 ID
     * @return 页面流式下载描述
     */
    @Transactional(readOnly = true)
    public PageDownloadDescriptor preparePageImageDownload(UUID ownerUserId, UUID pageId) {
        return pageAssetService.preparePageImageDownload(ownerUserId, pageId);
    }

    /**
     * 将漫画页面图片传输到响应输出流。
     *
     * @param descriptor 页面流式下载描述
     * @param outputStream 响应输出流
     * @throws IOException 对象读取或客户端连接写入失败
     */
    public void streamPageImage(
            PageDownloadDescriptor descriptor,
            OutputStream outputStream
    ) throws IOException {
        pageAssetService.streamPageImage(descriptor, outputStream);
    }

    /**
     * 从文件名解析排序元数据，同时设置 sourceSortKey 和结构化排序字段。
     *
     * <p>解析规则：
     * <ul>
     *   <li>季号：S01、Season 1、第1季</li>
     *   <li>卷号：Vol.01、Volume 2、第2卷</li>
     *   <li>章节范围：Ch001-010、第001-010话、Chapter 1</li>
     *   <li>番外：Extra、番外、Special</li>
     * </ul>
     *
     * @param source   来源实体
     * @param fileName 文件名
     */
    public void applySourceSortMetadata(ReaderItemSource source, String fileName) {
        source.setSourceSortKey(parseSourceSortKey(fileName));

        if (fileName == null) {
            return;
        }
        String name = fileName.toLowerCase(Locale.ROOT).replaceAll("\\.[^.]+$", "");

        // 季号：S01、Season 1、第1季
        Matcher season = Pattern.compile("s(\\d+)|season\\s*(\\d+)|第(\\d+)季").matcher(name);
        if (season.find()) {
            String num = season.group(1) != null ? season.group(1)
                    : season.group(2) != null ? season.group(2)
                    : season.group(3);
            source.setSeasonNo(Integer.parseInt(num));
        }

        // 卷/话/章等分卷信息：统一使用 ComicVolumeParser，兼容卷/册/目/話/繁简
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse(fileName);
        if (part.matched() && part.partNo() != null) {
            switch (part.partKind()) {
                case "VOL" -> {
                    source.setVolumeNo(part.partNo());
                    source.setChapterStart(null);
                    source.setChapterEnd(null);
                }
                case "SEASON_EP" -> {
                    source.setSeasonNo(part.partNo());
                    source.setChapterStart(part.rangeEnd());
                }
                case "SEASON" -> source.setSeasonNo(part.partNo());
                default -> {
                    source.setChapterStart(part.partNo());
                    source.setChapterEnd(part.rangeEnd());
                }
            }
        }

        // 番外：Extra、番外、Special（使用 extraOrder 区分多个番外）
        if (name.contains("extra") || name.contains("番外") || name.contains("special")) {
            Matcher extraNum = Pattern.compile("(?:extra|番外|special)\\s*(\\d+)").matcher(name);
            source.setExtraOrder(extraNum.find() ? Integer.parseInt(extraNum.group(1)) : 1);
        }
    }

    /**
     * 从文件名解析排序键。
     * 识别 Vol.01、Chapter 003、第001话、001-010、S01E02 等模式。
     * 返回可用于字典排序的字符串。
     *
     * @param fileName 文件名
     * @return 排序键
     */
    private String parseSourceSortKey(String fileName) {
        if (fileName == null) return "";
        String name = fileName.toLowerCase(Locale.ROOT).replaceAll("\\.[^.]+$", "");

        // 统一使用 ComicVolumeParser：覆盖卷/话/章/册/目/話区间/S01E02/繁简
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse(fileName);
        if (part.matched() && part.partNo() != null) {
            return switch (part.partKind()) {
                case "VOL" -> String.format("vol%06d", part.partNo());
                case "SEASON_EP" -> String.format("s%03de%06d",
                        part.partNo(), part.rangeEnd() == null ? 0 : part.rangeEnd());
                case "SEASON" -> String.format("season%06d", part.partNo());
                default -> String.format("ch%06d", part.partNo());
            };
        }

        // 兜底：纯数字前缀视为话号
        Matcher num = Pattern.compile("^(\\d{2,4})").matcher(name);
        if (num.find()) {
            return String.format("ch%06d", Integer.parseInt(num.group(1)));
        }

        return name;
    }

    /**
     * 去除文件名的扩展名。
     * 例如 "作品 001-010.cbz" → "作品 001-010"。
     *
     * @param fileName 文件名
     * @return 去除扩展名后的名称
     */
    private String stripExtension(String fileName) {
        if (fileName == null) return "";
        int lastDot = fileName.lastIndexOf('.');
        return lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
    }

    /**
     * 计算页面指纹（基于文件名和大小的 SHA-256 截断），用于检测重复或变更。
     */
    private String computeFingerprint(String name, int size) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            md.update(name.getBytes());
            md.update(String.valueOf(size).getBytes());
            byte[] hash = md.digest();
            StringBuilder hex = new StringBuilder(16);
            for (int i = 0; i < 8; i++) {
                hex.append(String.format("%02x", hash[i]));
            }
            return hex.toString();
        } catch (Exception e) {
            return "";
        }
    }

    private record EpubSourceParseResult(
            List<ComicCatalogDraftNode> catalogDrafts,
            ReaderCoverDraft cover
    ) {
    }

    /**
     * 为固定版式 EPUB 创建来源并发布异步解析任务。
     *
     * @param itemId      漫画作品 ID
     * @param fileNodeId  EPUB 文件的 FileNode ID
     * @param contentHash 文件哈希
     * @return 创建或已有的来源记录
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderItemSource generateEpubManifest(UUID itemId, UUID fileNodeId, String contentHash) {
        return addSource(itemId, fileNodeId, contentHash, "EPUB");
    }

    /**
     * 重试失败的来源解析。
     *
     * <p>该方法保留旧调用入口，实际执行委托给异步重试任务。
     *
     * @param itemId   漫画作品 ID
     * @param sourceId 来源 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void retrySource(UUID itemId, UUID sourceId) {
        publishRetryTask(itemId, sourceId);
    }

    /**
     * 发布异步重试任务：将失败来源的重试投递到 RabbitMQ。
     * 前端调用此方法后立即返回，Worker 异步执行重试。
     *
     * @param itemId   漫画作品 ID
     * @param sourceId 来源 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void publishRetryTask(UUID itemId, UUID sourceId) {
        ReaderItemSource source = sourceRepository.findById(sourceId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "来源不存在"));
        if (!source.getReaderItemId().equals(itemId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "来源不属于该作品");
        }
        if (source.getStatus() != ReaderSourceStatus.FAILED) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "只能重试失败的来源");
        }

        // 标记为 PENDING
        source.setStatus(ReaderSourceStatus.PENDING);
        source.setRetryCount(source.getRetryCount() + 1);
        sourceRepository.save(source);

        ReaderItem item = itemRepository.findById(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "条目不存在"));
        item.setImportStatus("PARSING");
        itemRepository.save(item);

        enqueueParseTask(item, source, true);

        log.info("已发布漫画重试任务: itemId={}, sourceId={}", itemId, sourceId);
    }

    /**
     * 查询或创建主来源记录，创建时不执行解析。
     */
    private ReaderItemSource findOrCreatePendingSource(ReaderItem item) {
        ReaderItemSource existing = sourceRepository
                .findByReaderItemIdAndFileNodeId(item.getId(), item.getFileNodeId())
                .orElse(null);
        if (existing != null) {
            return existing;
        }

        FileDescriptor fileNode = fileMetadataQueryService.findById(item.getFileNodeId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));

        ReaderItemSource source = new ReaderItemSource();
        source.setReaderItemId(item.getId());
        source.setFileNodeId(item.getFileNodeId());
        source.setContentHash(item.getContentHash());
        source.setFileFormat(item.getItemType());
        source.setSourceName(fileNode.name());
        source.setStatus(ReaderSourceStatus.PENDING);
        applySourceSortMetadata(source, fileNode.name());
        return sourceRepository.save(source);
    }

    /**
     * 创建漫画解析任务记录并在当前事务内写入 Outbox 投递行。
     */
    private void enqueueParseTask(ReaderItem item, ReaderItemSource source, boolean retry) {
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(taskId, item.getOwnerUserId(), "COMIC_PARSE",
                QueueNames.COMIC_PARSE_ROUTING_KEY, "QUEUED", "FILE_NODE", source.getFileNodeId(), Map.of(
                        "ownerUserId", item.getOwnerUserId().toString(),
                        "itemId", item.getId().toString(),
                        "sourceId", source.getId().toString(),
                        "fileNodeId", source.getFileNodeId().toString(),
                        "fileFormat", source.getFileFormat(),
                        "contentHash", source.getContentHash(),
                        "isRetry", retry
                ));
        // 任务记录与 Outbox 投递行在同一事务提交，避免"记录已建而消息丢失"的僵尸任务。
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.COMIC_PARSE_ROUTING_KEY,
                new ComicParseTaskEvent(
                        taskId,
                        item.getOwnerUserId(),
                        item.getId(),
                        source.getId(),
                        source.getFileNodeId(),
                        source.getFileFormat(),
                        source.getContentHash(),
                        retry));
    }

    /**
     * 重新解析 EPUB 来源（保留 sourceId，绕开幂等检查，流式读取）。
     */
    private EpubSourceParseResult reparseEpubSource(
            ReaderItemSource source,
            IntConsumer progressReporter
    ) {
        FileDescriptor fileNode = loadFileNode(source.getFileNodeId());

        try (StagedArchive stagedArchive = epubArchiveStager.stage(fileNode)) {
            progressReporter.accept(50);
            ComicEpubParser parser = new ComicEpubParser();
            try (EpubArchive archive = new EpubArchive(stagedArchive.path(), archiveSafetyPolicy)) {
                ComicEpubParser.EpubParseResult parseResult = parser.parseMetadata(archive);
                if (parseResult == null) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR, "EPUB 元数据解析失败");
                }
                progressReporter.accept(65);

                List<ComicPageDraft> pageDrafts = parser.extractPageDrafts(archive, parseResult, source.getId());
                if (pageDrafts.isEmpty()) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR, "EPUB 无可阅读页面");
                }
                progressReporter.accept(80);

                List<ComicCatalogDraftNode> catalogDrafts = parser.extractCatalogDrafts(parseResult, source.getId());
                ComicManifestDraft draft = new ComicManifestDraft(
                        source.getReaderItemId(), source.getId(), pageDrafts, catalogDrafts,
                        parseResult.readingDirection(), parseResult.title(), parseResult.author());
                manifestBuilder.applyDraft(draft);
                progressReporter.accept(90);

                source.setReadingDirection(normalizeReadingDirection(parseResult.readingDirection()));
                source.setStatus(ReaderSourceStatus.READY);
                source.setPageCount(pageDrafts.size());
                sourceRepository.save(source);
                return new EpubSourceParseResult(catalogDrafts, parser.extractCover(archive, parseResult));
            }
        } catch (BusinessException e) {
            throw e;
        } catch (Exception e) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "EPUB 解析失败: " + e.getMessage());
        }
    }

    /**
     * 重新解析 CBZ/ZIP 来源（保留 sourceId，绕开幂等检查）。
     */
    private ReaderCoverDraft reparseZipSource(ReaderItemSource source, IntConsumer progressReporter) {
        FileDescriptor fileNode = loadFileNode(source.getFileNodeId());

        List<ImageEntry> imageEntries = archiveParser.parseEntries(fileNode);
        progressReporter.accept(70);

        if (imageEntries.isEmpty()) {
            source.setPageCount(0);
            source.setStatus(ReaderSourceStatus.FAILED);
            source.setErrorCode("NO_IMAGE_ENTRY");
            source.setErrorMessage("未找到可阅读图片");
            sourceRepository.save(source);
            return null;
        }

        List<ReaderPage> newPages = new ArrayList<>();
        int sourcePageIndex = 0;
        for (ImageEntry img : imageEntries) {
            ReaderPage page = new ReaderPage();
            page.setReaderItemId(source.getReaderItemId());
            page.setSourceId(source.getId());
            page.setPageIndex(sourcePageIndex);
            page.setSourcePageIndex(sourcePageIndex);
            page.setSourcePath(img.name());
            page.setWidth(img.width() > 0 ? img.width() : null);
            page.setHeight(img.height() > 0 ? img.height() : null);
            page.setFingerprint(computeFingerprint(img.name(), (int) img.size()));
            page.setEntryIndex(img.entryIndex());
            page.setMimeType(ComicPageAssetService.detectMimeType(img.name()));
            page.setByteSize(img.size());
            newPages.add(page);
            sourcePageIndex++;
        }

        // 只有在新压缩包已经成功解析出页面后才替换旧页面，解析失败时保留旧清单。
        pageRepository.deleteBySourceId(source.getId());
        pageRepository.saveAll(newPages);
        progressReporter.accept(90);
        source.setPageCount(newPages.size());
        source.setStatus(ReaderSourceStatus.READY);
        sourceRepository.save(source);
        return archiveParser.extractCover(fileNode, imageEntries.getFirst());
    }

    private void persistCoverAfterCommit(UUID itemId, ReaderCoverDraft cover) {
        if (cover == null) {
            return;
        }
        Runnable persistCover = () -> {
            try {
                coverExtractionService.storeIfAbsent(itemId, cover);
            } catch (RuntimeException exception) {
                log.warn("漫画封面自动保存失败: itemId={}, errorType={}",
                        itemId, exception.getClass().getSimpleName());
            }
        };
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            persistCover.run();
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                persistCover.run();
            }
        });
    }

    /**
     * 加载可供解析的文件节点描述符。
     *
     * @param fileNodeId 文件节点 ID
     * @return 文件节点描述符
     */
    private FileDescriptor loadFileNode(UUID fileNodeId) {
        FileDescriptor fileNode = fileMetadataQueryService.findById(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (fileNode.deleted() || !"FILE".equals(fileNode.nodeType())) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在");
        }
        return fileNode;
    }

    /**
     * 删除来源及其页面，然后重建清单。
     *
     * @param itemId   漫画作品 ID
     * @param sourceId 来源 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteSource(UUID itemId, UUID sourceId) {
        itemRepository.findByIdForUpdate(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "阅读条目不存在"));
        ReaderItemSource source = sourceRepository.findById(sourceId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "来源不存在"));
        if (!source.getReaderItemId().equals(itemId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "来源不属于该作品");
        }
        if (sourceRepository.countByReaderItemId(itemId) <= 1) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "作品至少需要保留一个来源");
        }

        List<ReaderPageAsset> previousPageAssets = pageAssetService.findPageAssets(source.getId());
        pageRepository.deleteBySourceId(source.getId());
        // 删除来源
        sourceRepository.delete(source);
        // 重建清单
        rebuildComicManifest(itemId);
        refreshItemImportStatus(itemId);
        cleanupPageAssetsAfterCommit(previousPageAssets);

        log.info("删除漫画来源: itemId={}, sourceId={}", itemId, sourceId);
    }

    private void cleanupPageAssetsAfterCommit(List<ReaderPageAsset> assets) {
        if (assets == null || assets.isEmpty()) {
            return;
        }
        Runnable cleanup = () -> pageAssetService.cleanupPageAssetsAfterCommit(assets);
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

    private ComicSourceDto toSourceDto(ReaderItemSource source) {
        return new ComicSourceDto(
                source.getId(),
                source.getFileNodeId(),
                source.getFileFormat(),
                source.getSourceName(),
                source.getSourceSortKey(),
                source.getReadingDirection(),
                source.getStatus() != null ? source.getStatus().name() : ReaderSourceStatus.READY.name(),
                source.getErrorCode(),
                source.getErrorMessage(),
                source.getRetryCount(),
                source.getSeasonNo(),
                source.getVolumeNo(),
                source.getChapterStart(),
                source.getChapterEnd(),
                source.getExtraOrder(),
                source.getPageCount(),
                source.getCreatedAt());
    }

    private String resolveReadingDirection(List<ReaderItemSource> sources) {
        for (ReaderItemSource source : sources) {
            String direction = normalizeReadingDirection(source.getReadingDirection());
            if (direction != null) {
                return direction;
            }
        }
        return null;
    }

    private String normalizeReadingDirection(String direction) {
        if (direction == null || direction.isBlank()) {
            return null;
        }
        String normalized = direction.trim().toLowerCase(Locale.ROOT);
        return switch (normalized) {
            case "rtl", "ltr" -> normalized;
            default -> null;
        };
    }

    private ComicCatalogDto toCatalogDto(ReaderCatalogNode node) {
        return new ComicCatalogDto(
                node.getId(),
                node.getParentId(),
                node.getSourceId(),
                node.getNodeType(),
                node.getTitle(),
                node.getSortIndex(),
                node.getPageCount(),
                node.getCatalogKey(),
                node.getPageIndexStart(),
                node.getPageIndexEnd());
    }

    private ComicPageDto toPageDto(ReaderPage page) {
        return new ComicPageDto(
                page.getId(),
                page.getSourceId(),
                page.getCatalogNodeId(),
                page.getCatalogKey(),
                page.getPageIndex(),
                page.getSourcePageIndex(),
                page.getSourcePath(),
                page.getWidth(),
                page.getHeight(),
                page.getFingerprint(),
                page.getEntryIndex(),
                page.getMimeType(),
                page.getByteSize());
    }

    private ComicParseTaskDto toParseTaskDto(TaskRecord task) {
        return new ComicParseTaskDto(
                task.getId(),
                task.getStatus(),
                task.getProgress(),
                task.getErrorMessage(),
                task.getUpdatedAt()
        );
    }

}
