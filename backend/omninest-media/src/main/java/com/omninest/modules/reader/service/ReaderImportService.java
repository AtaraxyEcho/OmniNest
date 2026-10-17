package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import org.springframework.beans.factory.annotation.Value;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderBookshelf;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderSourceStatus;
import com.omninest.modules.reader.dto.ReaderDtos;
import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.repository.ReaderBookshelfRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.task.service.TaskDispatchService;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HashSet;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 阅读导入服务，负责创建阅读条目、加入书架和触发漫画异步解析。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderImportService {

    private static final String CONTENT_KIND_COMIC = "COMIC";
    private static final String CONTENT_KIND_TEXT = "TEXT";
    private static final String FILE_TYPE_EPUB = "EPUB";
    private static final String FILE_TYPE_TXT = "TXT";
    private static final String FILE_TYPE_CBZ = "CBZ";
    private static final String FILE_TYPE_ZIP = "ZIP";
    private static final String FILE_TYPE_PDF = "PDF";
    private static final Set<String> SUPPORTED_CONTENT_KINDS = Set.of(CONTENT_KIND_TEXT, CONTENT_KIND_COMIC);

    private final ReaderItemRepository itemRepository;
    private final ReaderBookshelfRepository bookshelfRepository;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final FileQueryService fileQueryService;
    private final ReaderFileDetector fileDetector;
    private final ReaderArchiveSafetyPolicy archiveSafetyPolicy;
    private final ReaderComicManifestService comicManifestService;
    private final ReaderItemSourceRepository sourceRepository;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final ReaderTextParseSubmissionService textParseSubmissionService;
    private final ReaderPdfMetadataService pdfMetadataService;
    private final ReaderCoverExtractionService coverExtractionService;
    private final MediaSyncEventService syncEventService;

    /**
     * EPUB 自动归类时每文本条目平均正文字符阈值，低于该值判定为漫画。
     */
    @Value("${omninest.reader.content-kind.text-chars-threshold:100}")
    private int textCharsThreshold;

    /**
     * 导入阅读文件。普通文本条目只创建元数据，漫画条目创建待解析来源并投递异步解析任务。
     *
     * @param ownerUserId 所属用户 ID
     * @param fileNodeId 文件节点 ID
     * @param forceImport 是否强制导入
     * @param contentKindOverride 内容形态覆盖值，EPUB 可指定 TEXT 或 COMIC
     * @return 导入或复用的阅读条目
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderItem importFile(
            UUID ownerUserId,
            UUID fileNodeId,
            boolean forceImport,
            String contentKindOverride) {
        FileDescriptor fileNode = loadReadableFileNode(ownerUserId, fileNodeId);
        String fileType = fileDetector.detectType(fileNode.name());
        if (fileType == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "不支持的阅读文件类型");
        }

        Optional<ReaderItem> existingByFile = itemRepository
                .findAccessibleByFileNodeId(ownerUserId, fileNodeId, SpaceType.SHARED)
                .stream()
                .filter(candidate -> isSameSpaceScope(ownerUserId, candidate, fileNode.spaceType()))
                .findFirst();
        if (existingByFile.isPresent()) {
            ReaderItem existing = applyExplicitComicOverride(
                    ownerUserId,
                    fileNodeId,
                    existingByFile.get(),
                    contentKindOverride);
            if (FILE_TYPE_PDF.equals(fileType)) {
                // 内容替换后重新提取页数与封面，避免派生元数据陈旧。
                enrichPdfMetadata(existing, fileNode, true);
            }
            ensureOnBookshelf(ownerUserId, existing.getId());
            recordReaderItem(ownerUserId, existing, SyncAction.UPDATED);
            log.info("文件已导入，加入书架: userId={}, fileNodeId={}", ownerUserId, fileNodeId);
            return existing;
        }

        // 该文件已作为别人的多卷漫画分卷并入共享作品时，再次点击导入应回到同一作品而不是新建条目。
        for (ReaderItemSource attached : sourceRepository.findByFileNodeIdIn(List.of(fileNodeId))) {
            ReaderItem parent = itemRepository.findById(attached.getReaderItemId()).orElse(null);
            if (parent != null && isSameSpaceScope(ownerUserId, parent, fileNode.spaceType())) {
                ensureOnBookshelf(ownerUserId, parent.getId());
                syncEventService.invalidate(ownerUserId, SyncScope.READER, "READER_LIBRARY", Map.of());
                log.info("文件已作为漫画分卷并入作品，加入书架: userId={}, fileNodeId={}, itemId={}",
                        ownerUserId, fileNodeId, parent.getId());
                return parent;
            }
        }

        String contentHash = computeSha256Stream(fileNode);
        String contentKind = resolveContentKind(fileNode, fileType, contentKindOverride);
        itemRepository.lockContentHash(ownerUserId, contentHash);

        if (!forceImport) {
            ReaderItem duplicate = findDuplicate(ownerUserId, contentHash, fileNode.spaceType());
            if (duplicate != null) {
                syncEventService.invalidate(ownerUserId, SyncScope.READER, "READER_LIBRARY", Map.of());
                return duplicate;
            }
        }

        if (!forceImport && CONTENT_KIND_COMIC.equals(contentKind)) {
            ReaderItem merged = tryMergeComicSource(ownerUserId, fileNodeId, fileNode, fileType, contentHash);
            if (merged != null) {
                syncEventService.invalidate(ownerUserId, SyncScope.READER, "READER_LIBRARY", Map.of());
                return merged;
            }
        }

        ReaderItem item = new ReaderItem();
        item.setOwnerUserId(ownerUserId);
        item.setFileNodeId(fileNodeId);
        item.setContentHash(contentHash);
        item.setItemType(fileType);
        item.setContentKind(contentKind);
        String sourceTitle = stripExtension(fileNode.name());
        String normalizedTitle = CONTENT_KIND_COMIC.equals(contentKind)
                ? normalizeComicTitle(sourceTitle)
                : sourceTitle;
        item.setTitle(normalizedTitle == null || normalizedTitle.isBlank() ? sourceTitle : normalizedTitle);
        item.setImportStatus("PARSING");

        ReaderItem saved = itemRepository.save(item);
        ensureOnBookshelf(ownerUserId, saved.getId());
        if (CONTENT_KIND_COMIC.equals(contentKind)) {
            PendingComicSource pendingSource = findOrCreatePendingComicSource(
                    saved.getId(),
                    fileNodeId,
                    contentHash,
                    fileType,
                    fileNode.name());
            if (pendingSource.created()) {
                publishComicParseAfterCommit(
                        ownerUserId,
                        fileNode.ownerUserId(),
                        saved.getId(),
                        pendingSource.source().getId(),
                        fileNodeId,
                        fileType,
                        contentHash,
                        false);
            }
        } else if (FILE_TYPE_PDF.equals(fileType)) {
            // PDF 由客户端渲染，服务端提取页数与首页封面后即可阅读。
            saved.setImportStatus("READY");
            saved.setParsedAt(Instant.now());
            saved = itemRepository.save(saved);
            enrichPdfMetadata(saved, fileNode);
        } else {
            textParseSubmissionService.submit(saved, false);
        }

        recordReaderItem(ownerUserId, saved, SyncAction.CREATED);

        log.info("导入阅读文件: userId={}, fileNodeId={}, itemId={}, type={}",
                ownerUserId, fileNodeId, saved.getId(), fileType);
        return saved;
    }

    /**
     * 对已自动导入的 EPUB 条目应用用户显式选择的漫画类型。
     *
     * @param ownerUserId 所属用户 ID
     * @param fileNodeId 文件节点 ID
     * @param existing 已存在条目
     * @param contentKindOverride 用户显式指定的内容形态
     * @return 原条目或完成漫画升级后的条目
     */
    private ReaderItem applyExplicitComicOverride(
            UUID ownerUserId,
            UUID fileNodeId,
            ReaderItem existing,
            String contentKindOverride) {
        String normalizedOverride = normalizeContentKindOverride(contentKindOverride);
        if (normalizedOverride == null || normalizedOverride.equalsIgnoreCase(existing.getContentKind())) {
            return existing;
        }

        FileDescriptor fileNode = loadReadableFileNode(ownerUserId, fileNodeId);
        String fileType = fileDetector.detectType(fileNode.name());
        validateContentKindOverride(fileType, normalizedOverride);
        if (!CONTENT_KIND_COMIC.equals(normalizedOverride)) {
            return existing;
        }

        ReaderItem lockedItem = itemRepository.findByIdForUpdate(existing.getId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "条目不存在"));
        String contentHash = lockedItem.getContentHash();
        if (contentHash == null || contentHash.isBlank()) {
            contentHash = computeSha256Stream(fileNode);
            lockedItem.setContentHash(contentHash);
        }
        lockedItem.setItemType(fileType);
        lockedItem.setContentKind(CONTENT_KIND_COMIC);
        lockedItem.setImportStatus("PARSING");
        lockedItem.setParseErrorCode(null);
        lockedItem.setParseErrorMessage(null);
        ReaderItem saved = itemRepository.save(lockedItem);

        // 升级前这本书可能已经按 TEXT 提交了在途解析任务：放任它跑完，回写会把刚切成
        // COMIC 的条目覆写成 FAILED（文本清单写入被漫画守卫拒绝后仍会 markFailed）。
        // 只排除漫画任务本身，其余挂在条目上的活动任务都作废。
        taskRecordService.cancelActiveResourceTasks(
                saved.getOwnerUserId(),
                "READER_ITEM",
                List.of(saved.getId()),
                List.of("QUEUED", "RUNNING", "RETRY_WAIT"),
                "COMIC_PARSE"
        );

        PendingComicSource pendingSource = findOrCreatePendingComicSource(
                saved.getId(),
                fileNodeId,
                contentHash,
                fileType,
                fileNode.name());
        if (pendingSource.created()) {
            publishComicParseAfterCommit(
                    ownerUserId,
                    fileNode.ownerUserId(),
                    saved.getId(),
                    pendingSource.source().getId(),
                    fileNodeId,
                    fileType,
                    contentHash,
                    false);
        } else {
            comicManifestService.enqueueManifestReparse(saved.getId());
        }
        log.info("已将阅读条目升级为漫画: userId={}, itemId={}, fileNodeId={}",
                ownerUserId, saved.getId(), fileNodeId);
        return saved;
    }

    /**
     * 使用默认策略导入阅读文件。
     *
     * @param ownerUserId 所属用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 导入或复用的阅读条目
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderItem importFile(UUID ownerUserId, UUID fileNodeId) {
        return importFile(ownerUserId, fileNodeId, false);
    }

    /**
     * 使用默认内容形态策略导入阅读文件。
     *
     * @param ownerUserId 所属用户 ID
     * @param fileNodeId 文件节点 ID
     * @param forceImport 是否强制导入
     * @return 导入或复用的阅读条目
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderItem importFile(UUID ownerUserId, UUID fileNodeId, boolean forceImport) {
        return importFile(ownerUserId, fileNodeId, forceImport, null);
    }

    /**
     * 列出当前用户可导入的阅读文件。
     *
     * @param ownerUserId 所属用户 ID
     * @return 可导入文件列表
     */
    @Transactional(readOnly = true)
    public List<ReaderDtos.ImportCandidateDto> importCandidates(UUID ownerUserId) {
        // 目录行由 SQL 过滤掉，候选集只剩文件节点。
        List<FileDescriptor> personalFiles = fileMetadataQueryService.listOwnedActiveFiles(ownerUserId);
        List<FileDescriptor> sharedFiles = fileMetadataQueryService.listActiveFilesBySpace(SpaceType.SHARED);

        List<FileDescriptor> allFiles = new ArrayList<>(personalFiles);
        Set<UUID> seenFileNodeIds = new HashSet<>();
        personalFiles.forEach(file -> seenFileNodeIds.add(file.id()));
        for (FileDescriptor shared : sharedFiles) {
            if (seenFileNodeIds.add(shared.id())) {
                allFiles.add(shared);
            }
        }

        List<ReaderDtos.ImportCandidateDto> candidates = new ArrayList<>();
        List<FileDescriptor> readerFiles = allFiles.stream()
                .filter(file -> fileDetector.isReaderFile(file.name()))
                .toList();
        List<UUID> allFileNodeIds = readerFiles.stream().map(FileDescriptor::id).toList();

        Set<UUID> importedFileNodeIds = importedFileNodeIds(ownerUserId, allFileNodeIds);
        Set<String> importedContentHashes = new HashSet<>(
                itemRepository.findVisibleContentHashes(ownerUserId, SpaceType.SHARED));
        importedContentHashes.addAll(
                sourceRepository.findVisibleSourceContentHashes(ownerUserId, SpaceType.SHARED));
        Map<UUID, String> contentHashes = fileMetadataQueryService
                .findContentSha256ByFileNodeIds(allFileNodeIds);

        for (FileDescriptor file : readerFiles) {
            if (importedFileNodeIds.contains(file.id())) {
                continue;
            }
            if (importedContentHashes.contains(contentHashes.get(file.id()))) {
                continue;
            }
            candidates.add(new ReaderDtos.ImportCandidateDto(
                    file.id(),
                    file.name(),
                    fileDetector.detectType(file.name()),
                    file.sizeBytes(),
                    file.spaceType().getValue(),
                    file.createdAt()));
        }
        return candidates;
    }

    /**
     * 取消尚未完成的阅读导入任务。源文件保留，已写入的条目用于展示可重试失败状态。
     *
     * @param ownerUserId 所有者用户 ID
     * @param itemId 阅读条目 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void cancelImport(UUID ownerUserId, UUID itemId) {
        ReaderItem item = itemRepository.findByIdAndOwnerUserId(itemId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在或无权操作"));
        if ("READY".equals(item.getImportStatus())) {
            throw new BusinessException(ErrorCode.CONFLICT, "阅读条目已经导入完成");
        }
        List<ReaderItemSource> sources = sourceRepository.findByReaderItemId(itemId);
        List<UUID> fileNodeIds = new ArrayList<>();
        if (item.getFileNodeId() != null) {
            fileNodeIds.add(item.getFileNodeId());
        }
        fileNodeIds.addAll(sources.stream()
                .map(ReaderItemSource::getFileNodeId)
                .filter(Objects::nonNull)
                .toList());
        taskRecordService.cancelActiveResourceTasks(
                ownerUserId,
                "FILE_NODE",
                fileNodeIds.stream().distinct().toList(),
                List.of("QUEUED", "RUNNING", "RETRY_WAIT"),
                "FILE_PURGE"
        );
        // 文本解析任务挂在 READER_ITEM 资源上，漏掉它会让取消后的任务继续跑完并覆盖失败状态。
        taskRecordService.cancelActiveResourceTasks(
                ownerUserId,
                "READER_ITEM",
                List.of(itemId),
                List.of("QUEUED", "RUNNING", "RETRY_WAIT"),
                "FILE_PURGE"
        );
        for (ReaderItemSource source : sources) {
            if (source.getStatus() == ReaderSourceStatus.PENDING
                    || source.getStatus() == ReaderSourceStatus.PARSING) {
                source.setStatus(ReaderSourceStatus.FAILED);
                source.setErrorCode("IMPORT_CANCELLED");
                source.setErrorMessage("用户已取消导入");
            }
        }
        sourceRepository.saveAll(sources);
        item.setImportStatus("FAILED");
        item.setParseErrorCode("IMPORT_CANCELLED");
        item.setParseErrorMessage("用户已取消导入");
        itemRepository.save(item);
        syncEventService.invalidate(ownerUserId, SyncScope.READER, "READER_LIBRARY", Map.of());
    }

    /**
     * 读取并校验可导入文件节点。
     */
    private FileDescriptor loadReadableFileNode(UUID ownerUserId, UUID fileNodeId) {
        FileDescriptor fileNode = fileMetadataQueryService.findById(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (fileNode.deleted()) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件已删除");
        }
        if (fileNode.spaceType() == SpaceType.PERSONAL && !fileNode.ownerUserId().equals(ownerUserId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权导入此文件");
        }
        return fileNode;
    }

    /**
     * 根据文件类型和 EPUB 版式/文本密度判断阅读内容类型。
     */
    private String detectContentKind(FileDescriptor fileNode, String fileType) {
        String contentKind = fileDetector.detectContentKind(fileType);
        if (FILE_TYPE_EPUB.equals(fileType)) {
            try {
                if (isFixedLayoutEpub(fileNode)) {
                    return CONTENT_KIND_COMIC;
                }
            } catch (Exception ex) {
                log.debug("EPUB fixed-layout 预检测失败: {}", ex.getMessage());
            }
        }
        return contentKind;
    }

    /**
     * 解析导入时最终使用的内容形态。
     */
    private String resolveContentKind(FileDescriptor fileNode, String fileType, String contentKindOverride) {
        String normalizedOverride = normalizeContentKindOverride(contentKindOverride);
        if (normalizedOverride == null) {
            return detectContentKind(fileNode, fileType);
        }
        validateContentKindOverride(fileType, normalizedOverride);
        return normalizedOverride;
    }

    /**
     * 规范化内容形态覆盖值。
     */
    private String normalizeContentKindOverride(String contentKindOverride) {
        if (contentKindOverride == null || contentKindOverride.isBlank()) {
            return null;
        }
        String normalized = contentKindOverride.trim().toUpperCase();
        if (!SUPPORTED_CONTENT_KINDS.contains(normalized)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "不支持的内容形态");
        }
        return normalized;
    }

    /**
     * 校验内容形态与文件格式是否匹配。
     */
    private void validateContentKindOverride(String fileType, String contentKindOverride) {
        if (FILE_TYPE_PDF.equals(fileType)) {
            if (CONTENT_KIND_TEXT.equals(contentKindOverride)) {
                return;
            }
            throw new BusinessException(ErrorCode.PARAM_ERROR, "PDF 仅支持文本阅读形态");
        }
        if (FILE_TYPE_EPUB.equals(fileType)) {
            return;
        }
        if (FILE_TYPE_TXT.equals(fileType) && CONTENT_KIND_TEXT.equals(contentKindOverride)) {
            return;
        }
        if ((FILE_TYPE_CBZ.equals(fileType) || FILE_TYPE_ZIP.equals(fileType))
                && CONTENT_KIND_COMIC.equals(contentKindOverride)) {
            return;
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "内容形态与文件格式不匹配");
    }

    /**
     * 查找可复用的共享空间重复条目。
     */
    private Set<UUID> importedFileNodeIds(UUID ownerUserId, List<UUID> candidateFileNodeIds) {
        if (candidateFileNodeIds.isEmpty()) {
            return Set.of();
        }
        Set<UUID> imported = new HashSet<>(itemRepository.findVisibleMainFileNodeIds(
                ownerUserId, candidateFileNodeIds, SpaceType.SHARED));
        imported.addAll(sourceRepository.findImportedFileNodeIds(
                ownerUserId, candidateFileNodeIds, SpaceType.SHARED));
        return imported;
    }

    /**
     * 按内容摘要复用同空间的已有条目。个人内容与共享内容分属两套可见范围，不得跨空间互相复用。
     */
    private ReaderItem findDuplicate(UUID ownerUserId, String contentHash, SpaceType targetSpace) {
        List<ReaderItem> candidates = new ArrayList<>();
        itemRepository.findFirstByOwnerUserIdAndContentHashOrderByUpdatedAtDesc(ownerUserId, contentHash)
                .ifPresent(candidates::add);
        candidates.addAll(itemRepository.findByContentHash(contentHash));
        // 已并入多卷漫画的分卷只存在于来源表里，二次上传同一分卷要能回到所属作品。
        candidates.addAll(sourceRepository.findItemsBySourceContentHash(contentHash));

        Set<UUID> visited = new HashSet<>();
        for (ReaderItem candidate : candidates) {
            if (!visited.add(candidate.getId())) {
                continue;
            }
            if (!isSameSpaceScope(ownerUserId, candidate, targetSpace)) {
                continue;
            }
            ensureOnBookshelf(ownerUserId, candidate.getId());
            log.info("存在相同空间与内容的阅读条目，直接复用: userId={}, itemId={}, space={}",
                    ownerUserId, candidate.getId(), targetSpace);
            return candidate;
        }
        return null;
    }

    /**
     * 判断条目是否落在请求者可访问的同一空间内。
     */
    private boolean isSameSpaceScope(UUID requesterId, ReaderItem item, SpaceType targetSpace) {
        if (item.getFileNodeId() == null) {
            return false;
        }
        FileDescriptor mainFile = fileMetadataQueryService.findById(item.getFileNodeId()).orElse(null);
        if (mainFile == null || mainFile.deleted() || mainFile.spaceType() != targetSpace) {
            return false;
        }
        return targetSpace == SpaceType.SHARED || requesterId.equals(item.getOwnerUserId());
    }

    /**
     * 按规范化标题将漫画分包合并到已有作品。
     *
     * <p>合并严格限制在同一空间：共享分卷可以并入任何人在共享空间建的同系列作品，私有分卷只并入
     * 本人主文件仍在个人空间的作品。跨空间混并会让共享成员读到别人私有分卷的页面时 403。
     */
    private ReaderItem tryMergeComicSource(
            UUID ownerUserId,
            UUID fileNodeId,
            FileDescriptor fileNode,
            String fileType,
            String contentHash) {
        String strippedName = stripExtension(fileNode.name());
        String baseName = normalizeComicTitle(strippedName);
        if (baseName == null || baseName.isBlank()) {
            return null;
        }
        if (!hasComicPartSignal(strippedName)) {
            return null;
        }

        boolean sharedSpace = fileNode.spaceType() == SpaceType.SHARED;
        itemRepository.lockComicSeries(
                sharedSpace ? "SHARED" : "PERSONAL:" + ownerUserId,
                baseName);

        List<ReaderItem> existingComics = sharedSpace
                ? itemRepository.findSharedComicCandidates(SpaceType.SHARED, CONTENT_KIND_COMIC)
                : itemRepository.findPersonalComicCandidates(
                        ownerUserId, SpaceType.PERSONAL, CONTENT_KIND_COMIC);
        for (ReaderItem existing : existingComics) {
            String existingBase = normalizeComicTitle(existing.getTitle());
            if (!baseName.equalsIgnoreCase(existingBase)) {
                continue;
            }

            log.info("漫画分包合并: userId={}, existingItemId={}, itemOwner={}, space={}, newFile={}",
                    ownerUserId, existing.getId(), existing.getOwnerUserId(),
                    fileNode.spaceType(), fileNode.name());
            ReaderItem lockedItem = itemRepository.findByIdForUpdate(existing.getId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "条目不存在"));
            ensureOnBookshelf(ownerUserId, lockedItem.getId());
            PendingComicSource pendingSource = findOrCreatePendingComicSource(
                    lockedItem.getId(),
                    fileNodeId,
                    contentHash,
                    fileType,
                    fileNode.name());
            if (!pendingSource.created()) {
                return lockedItem;
            }
            lockedItem.setImportStatus("PARSING");
            itemRepository.save(lockedItem);
            publishComicParseAfterCommit(
                    lockedItem.getOwnerUserId(),
                    fileNode.ownerUserId(),
                    lockedItem.getId(),
                    pendingSource.source().getId(),
                    fileNodeId,
                    fileType,
                    contentHash,
                    false);
            if (!ownerUserId.equals(lockedItem.getOwnerUserId())) {
                // 合并改变的是别人创建的作品，创建者的书库列表也要重新拉取。
                syncEventService.invalidate(
                        lockedItem.getOwnerUserId(), SyncScope.READER, "READER_LIBRARY", Map.of());
            }
            return lockedItem;
        }
        return null;
    }

    /**
     * 确保阅读条目已经加入当前用户书架。
     */
    private void ensureOnBookshelf(UUID ownerUserId, UUID readerItemId) {
        if (!bookshelfRepository.existsByOwnerUserIdAndReaderItemId(ownerUserId, readerItemId)) {
            ReaderBookshelf bookshelf = new ReaderBookshelf();
            bookshelf.setOwnerUserId(ownerUserId);
            bookshelf.setReaderItemId(readerItemId);
            bookshelfRepository.save(bookshelf);
        }
    }

    /**
     * 以流式方式计算文件 SHA-256，避免将完整文件读入内存。
     */

    private void enrichPdfMetadata(ReaderItem item, FileDescriptor fileNode) {
        enrichPdfMetadata(item, fileNode, false);
    }

    private void enrichPdfMetadata(ReaderItem item, FileDescriptor fileNode, boolean overwriteCover) {
        ReaderPdfMetadataService.PdfMetadata metadata = pdfMetadataService.extract(fileNode);
        if (metadata == null) {
            return;
        }
        var cover = metadata.toCoverDraft();
        if (cover != null) {
            persistPdfCoverAfterCommit(item.getId(), cover, overwriteCover);
        }
        ReaderItemSource source = sourceRepository
                .findByReaderItemIdAndFileNodeId(item.getId(), fileNode.id())
                .orElseGet(ReaderItemSource::new);
        source.setPageCount(Math.max(0, metadata.pageCount()));
        if (source.getReaderItemId() == null) {
            source.setReaderItemId(item.getId());
            source.setFileNodeId(fileNode.id());
            source.setContentHash(item.getContentHash() != null ? item.getContentHash() : "");
            source.setFileFormat(FILE_TYPE_PDF);
            source.setSourceName(fileNode.name());
            source.setStatus(ReaderSourceStatus.READY);
        }
        sourceRepository.save(source);
    }

    /**
     * 重新提取 PDF 条目的页数与封面。
     *
     * <p>PDF 由客户端渲染，没有文本章节清单，绝不能投给文本解析引擎：那条链只认 EPUB 与 TXT，
     * 结果是把一份可读的条目写成 FAILED。
     */
    @Transactional(rollbackFor = Exception.class)
    public void reparsePdfItem(UUID ownerUserId, ReaderItem item) {
        if (item.getFileNodeId() == null) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "阅读条目未关联源文件");
        }
        FileDescriptor fileNode = loadReadableFileNode(ownerUserId, item.getFileNodeId());
        item.setImportStatus("READY");
        item.setParseErrorCode(null);
        item.setParseErrorMessage(null);
        item.setParsedAt(Instant.now());
        itemRepository.save(item);
        enrichPdfMetadata(item, fileNode, true);
        syncEventService.invalidate(ownerUserId, SyncScope.READER, "READER_LIBRARY", Map.of());
    }

    /**
     * 在事务提交后保存 PDF 封面。
     *
     * <p>封面服务开了 REQUIRES_NEW 独立事务，首次导入时条目还没提交，那个事务查不到行就会抛
     * BOOK_NOT_FOUND 并把整个导入一起回滚。
     */
    private void persistPdfCoverAfterCommit(UUID itemId, ReaderCoverDraft cover, boolean overwrite) {
        Runnable persistCover = () -> {
            try {
                coverExtractionService.store(itemId, cover, overwrite);
            } catch (RuntimeException exception) {
                log.warn("PDF 封面自动保存失败: itemId={}, errorType={}",
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

    private String computeSha256Stream(FileDescriptor fileNode) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (FileContentStream content = fileQueryService.openOwnedFileContent(
                    fileNode.ownerUserId(),
                    fileNode.id())) {
                InputStream stream = content.inputStream();
                byte[] buffer = new byte[8192];
                int read;
                while ((read = stream.read(buffer)) != -1) {
                    digest.update(buffer, 0, read);
                }
            }
            byte[] hash = digest.digest();
            StringBuilder hex = new StringBuilder(64);
            for (byte b : hash) {
                hex.append(String.format("%02x", b));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 不可用", ex);
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "文件读取失败");
        }
    }

    /**
     * 使用临时文件检测 EPUB 内容形态（规范声明优先，文本密度兜底），避免将完整 EPUB 读入堆内存。
     */
    private boolean isFixedLayoutEpub(FileDescriptor fileNode) {
        Path tempFile = null;
        try {
            tempFile = Files.createTempFile("omninest-epub-detect-", ".epub");
            try (FileContentStream content = fileQueryService.openOwnedFileContent(
                    fileNode.ownerUserId(),
                    fileNode.id())) {
                archiveSafetyPolicy.copyArchive(
                        content.inputStream(),
                        tempFile,
                        fileNode.sizeBytes()
                );
            }
            return CONTENT_KIND_COMIC.equals(
                    fileDetector.detectContentKind(tempFile, textCharsThreshold));
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "文件读取失败");
        } finally {
            if (tempFile != null) {
                try {
                    Files.deleteIfExists(tempFile);
                } catch (IOException ex) {
                    log.warn("EPUB content-kind 检测临时文件删除失败: errorType={}",
                            ex.getClass().getSimpleName());
                }
            }
        }
    }

    /**
     * 创建待解析的漫画来源，解析动作由 Worker 异步执行。
     */
    private PendingComicSource findOrCreatePendingComicSource(
            UUID itemId,
            UUID fileNodeId,
            String contentHash,
            String fileType,
            String sourceName) {
        Optional<ReaderItemSource> existing = sourceRepository
                .findByReaderItemIdAndFileNodeId(itemId, fileNodeId);
        if (existing.isPresent()) {
            return new PendingComicSource(existing.get(), false);
        }
        ReaderItemSource source = new ReaderItemSource();
        source.setId(UUID.randomUUID());
        source.setReaderItemId(itemId);
        source.setFileNodeId(fileNodeId);
        source.setContentHash(contentHash);
        source.setFileFormat(fileType);
        source.setSourceName(sourceName);
        source.setStatus(ReaderSourceStatus.PENDING);
        comicManifestService.applySourceSortMetadata(source, sourceName);
        return new PendingComicSource(sourceRepository.save(source), true);
    }

    /**
     * 漫画来源幂等创建结果。
     *
     * @param source 来源记录
     * @param created 本次调用是否创建了新记录
     */
    private record PendingComicSource(ReaderItemSource source, boolean created) {
    }

    /**
     * 创建漫画解析任务并通过 Outbox 可靠投递。
     *
     * <p>任务记录归属条目所有者，取消与任务列表都按此过滤；事件里的文件操作用户是源文件节点的真实
     * 所有者。共享空间的漫画分卷可能由成员各自上传，若两处都用同一个人，Worker 的生命周期守卫会
     * 把合法分卷判成"文件不存在"并静默取消任务。
     */
    private void publishComicParseAfterCommit(
            UUID taskOwnerId,
            UUID fileOwnerId,
            UUID itemId,
            UUID sourceId,
            UUID fileNodeId,
            String fileType,
            String contentHash,
            boolean retry) {
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(taskId, taskOwnerId, "COMIC_PARSE",
                QueueNames.COMIC_PARSE_ROUTING_KEY, "QUEUED", "FILE_NODE", fileNodeId, Map.of(
                "ownerUserId", taskOwnerId.toString(),
                // 心跳超时恢复是从 payload 重建事件的：不落源文件真实所有者，重投后
                // Worker 的严格所有权守卫又会把共享分卷判成已删除。
                "fileOwnerId", fileOwnerId.toString(),
                "itemId", itemId.toString(),
                "sourceId", sourceId.toString(),
                "fileNodeId", fileNodeId.toString(),
                "fileFormat", fileType,
                // Map.of 不收 null：与漫画任务入队侧同口径，缺哈希按空串落 payload。
                "contentHash", contentHash == null ? "" : contentHash,
                "isRetry", retry
        ));
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.COMIC_PARSE_ROUTING_KEY,
                new ComicParseTaskEvent(taskId, fileOwnerId, itemId,
                        sourceId, fileNodeId, fileType, contentHash, retry)
        );
    }

    /**
     * 去除文件扩展名。
     */
    private String stripExtension(String fileName) {
        return ComicVolumeParser.stripExtension(fileName);
    }

    /**
     * 标准化漫画标题，去除常见分包、卷、话、季信息。
     */
    private String normalizeComicTitle(String title) {
        return ComicVolumeParser.normalizeTitle(title);
    }

    /**
     * 判断文件名是否包含分包线索。
     */
    private boolean hasComicPartSignal(String title) {
        return ComicVolumeParser.hasPartSignal(title);
    }

    private void recordReaderItem(UUID ownerUserId, ReaderItem item, SyncAction action) {
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
