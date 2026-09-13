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
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

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

        Optional<ReaderItem> existingByFile = itemRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, fileNodeId);
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

        String contentHash = computeSha256Stream(fileNode);
        String contentKind = resolveContentKind(fileNode, fileType, contentKindOverride);
        itemRepository.lockContentHash(ownerUserId, contentHash);

        if (!forceImport) {
            ReaderItem duplicate = findDuplicate(ownerUserId, contentHash);
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

        PendingComicSource pendingSource = findOrCreatePendingComicSource(
                saved.getId(),
                fileNodeId,
                contentHash,
                fileType,
                fileNode.name());
        if (pendingSource.created()) {
            publishComicParseAfterCommit(
                    ownerUserId,
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
        List<FileDescriptor> personalFiles = fileMetadataQueryService.listOwnedActive(ownerUserId);
        List<FileDescriptor> sharedFiles = fileMetadataQueryService.listActiveBySpace(SpaceType.SHARED);

        List<FileDescriptor> allFiles = new ArrayList<>(personalFiles);
        for (FileDescriptor shared : sharedFiles) {
            if (allFiles.stream().noneMatch(file -> file.id().equals(shared.id()))) {
                allFiles.add(shared);
            }
        }

        List<UUID> allFileNodeIds = allFiles.stream()
                .filter(file -> "FILE".equals(file.nodeType()) && fileDetector.isReaderFile(file.name()))
                .map(FileDescriptor::id)
                .toList();

        Set<UUID> importedFileNodeIds = importedFileNodeIds(ownerUserId, allFileNodeIds);
        Set<String> importedContentHashes = new HashSet<>(
                itemRepository.findContentHashesByOwnerUserId(ownerUserId));
        Map<UUID, String> contentHashes = fileMetadataQueryService
                .findContentSha256ByFileNodeIds(allFileNodeIds);

        List<ReaderDtos.ImportCandidateDto> candidates = new ArrayList<>();
        for (FileDescriptor file : allFiles) {
            if (!"FILE".equals(file.nodeType())) {
                continue;
            }
            if (!fileDetector.isReaderFile(file.name())) {
                continue;
            }
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
        Set<UUID> imported = itemRepository.findByOwnerUserIdAndFileNodeIdIn(ownerUserId, candidateFileNodeIds)
                .stream()
                .map(ReaderItem::getFileNodeId)
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());
        imported.addAll(sourceRepository.findImportedFileNodeIds(ownerUserId, candidateFileNodeIds));
        return imported;
    }

    /**
     * 按用户和内容摘要复用已存在条目。个人空间重复上传与共享空间重复内容使用同一规则。
     */
    private ReaderItem findDuplicate(UUID ownerUserId, String contentHash) {
        ReaderItem owned = itemRepository
                .findFirstByOwnerUserIdAndContentHashOrderByUpdatedAtDesc(ownerUserId, contentHash)
                .orElse(null);
        if (owned != null) {
            ensureOnBookshelf(ownerUserId, owned.getId());
            log.info("个人空间存在相同阅读内容，复用原条目: userId={}, itemId={}", ownerUserId, owned.getId());
            return owned;
        }
        List<ReaderItem> duplicates = itemRepository.findByContentHash(contentHash);
        for (ReaderItem duplicate : duplicates) {
            if (duplicate.getFileNodeId() == null) {
                continue;
            }
            FileDescriptor duplicateFile = fileMetadataQueryService.findById(duplicate.getFileNodeId()).orElse(null);
            if (duplicateFile == null) {
                continue;
            }
            if (duplicateFile.spaceType() == SpaceType.SHARED && !duplicateFile.deleted()) {
                ensureOnBookshelf(ownerUserId, duplicate.getId());
                log.info("共享空间存在相同阅读条目，加入书架: userId={}, existingItemId={}",
                        ownerUserId, duplicate.getId());
                return duplicate;
            }
        }
        return null;
    }

    /**
     * 按规范化标题将漫画分包合并到已有作品。
     */
    private ReaderItem tryMergeComicSource(
            UUID ownerUserId,
            UUID fileNodeId,
            FileDescriptor fileNode,
            String fileType,
            String contentHash) {
        String baseName = normalizeComicTitle(stripExtension(fileNode.name()));
        if (baseName == null || baseName.isBlank()) {
            return null;
        }
        if (!hasComicPartSignal(stripExtension(fileNode.name()))) {
            return null;
        }

        List<ReaderItem> existingComics = itemRepository
                .findByOwnerUserIdAndContentKindOrderByUpdatedAtDesc(ownerUserId, CONTENT_KIND_COMIC);
        for (ReaderItem existing : existingComics) {
            String existingBase = normalizeComicTitle(existing.getTitle());
            if (!baseName.equalsIgnoreCase(existingBase)) {
                continue;
            }

            log.info("漫画分包合并: userId={}, existingItemId={}, newFile={}",
                    ownerUserId, existing.getId(), fileNode.name());
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
                    ownerUserId,
                    lockedItem.getId(),
                    pendingSource.source().getId(),
                    fileNodeId,
                    fileType,
                    contentHash,
                    false);
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
            coverExtractionService.store(item.getId(), cover, overwriteCover);
        }
        boolean existing = sourceRepository
                .findByReaderItemIdAndFileNodeId(item.getId(), fileNode.id())
                .isPresent();
        if (existing) {
            sourceRepository
                    .findByReaderItemIdAndFileNodeId(item.getId(), fileNode.id())
                    .ifPresent(source -> {
                        source.setPageCount(Math.max(0, metadata.pageCount()));
                        sourceRepository.save(source);
                    });
        } else {
            ReaderItemSource source = new ReaderItemSource();
            source.setReaderItemId(item.getId());
            source.setFileNodeId(fileNode.id());
            source.setContentHash(item.getContentHash() != null ? item.getContentHash() : "");
            source.setFileFormat("PDF");
            source.setSourceName(fileNode.name());
            source.setStatus(ReaderSourceStatus.READY);
            source.setPageCount(Math.max(0, metadata.pageCount()));
            sourceRepository.save(source);
        }
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
     */
    private void publishComicParseAfterCommit(
            UUID ownerUserId,
            UUID itemId,
            UUID sourceId,
            UUID fileNodeId,
            String fileType,
            String contentHash,
            boolean retry) {
        UUID taskId = UUID.randomUUID();
        taskRecordService.createQueuedTask(taskId, ownerUserId, "COMIC_PARSE",
                QueueNames.COMIC_PARSE_ROUTING_KEY, "QUEUED", "FILE_NODE", fileNodeId, Map.of(
                "ownerUserId", ownerUserId.toString(),
                "itemId", itemId.toString(),
                "sourceId", sourceId.toString(),
                "fileNodeId", fileNodeId.toString(),
                "fileFormat", fileType,
                "contentHash", contentHash,
                "isRetry", retry
        ));
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.COMIC_PARSE_ROUTING_KEY,
                new ComicParseTaskEvent(taskId, ownerUserId, itemId,
                        sourceId, fileNodeId, fileType, contentHash, retry)
        );
    }

    /**
     * 去除文件扩展名。
     */
    private String stripExtension(String fileName) {
        if (fileName == null) {
            return "";
        }
        int dotIndex = fileName.lastIndexOf('.');
        return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
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
