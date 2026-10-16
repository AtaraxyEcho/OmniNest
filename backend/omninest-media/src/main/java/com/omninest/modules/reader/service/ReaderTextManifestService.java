package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderTextChapter;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderTextChapterRepository;
import com.omninest.modules.reader.service.ReaderTextParser.ParsedTextBook;
import com.omninest.modules.reader.service.ReaderTextParser.TextChapterDraft;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.TaskRecordService;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 文本书籍章节清单服务，负责原子替换解析结果和授权查询。
 *
 * @author OmniNest
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class ReaderTextManifestService {

    private final ReaderItemRepository itemRepository;
    private final ReaderTextChapterRepository chapterRepository;
    private final TaskRecordService taskRecordService;
    private final MediaSyncEventService syncEventService;
    private final ReaderCoverExtractionService coverExtractionService;
    private final ReaderItemService readerItemService;

    /**
     * 原子替换文本书籍解析结果。
     *
     * @param itemId 阅读条目 ID
     * @param parsedBook 解析草稿
     * @return 被替换掉的每章正文派生节点 ID，调用方在新版本落盘后负责清理
     */
    @Transactional(rollbackFor = Exception.class)
    public List<UUID> replaceManifest(UUID itemId, ParsedTextBook parsedBook) {
        ReaderItem item = itemRepository.findById(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在"));
        if (!"TEXT".equalsIgnoreCase(item.getContentKind())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "漫画条目不能写入文本章节清单");
        }
        // 章节行即将重建，派生节点引用只能在此处收集，否则旧版本文件永久泄漏
        List<UUID> obsoleteChapterAssetIds = chapterRepository.findByReaderItemIdOrderByChapterIndex(itemId).stream()
                .map(ReaderTextChapter::getContentFileNodeId)
                .filter(Objects::nonNull)
                .toList();
        chapterRepository.deleteByReaderItemId(itemId);
        chapterRepository.saveAll(parsedBook.chapters().stream()
                .map(draft -> toEntity(itemId, draft))
                .toList());
        applyParsedMetadata(item, parsedBook);
        item.setImportStatus("READY");
        item.setParseErrorCode(null);
        item.setParseErrorMessage(null);
        item.setParsedAt(Instant.now());
        // 每章正文派生资产按 (itemId, manifestVersion) 定位，清单替换必须推进版本号，
        // 否则重解析后旧版本正文仍会被继续命中。
        item.setManifestVersion(item.getManifestVersion() + 1);
        itemRepository.save(item);
        syncEventService.invalidate(item.getOwnerUserId(), SyncScope.READER, "READER_LIBRARY", Map.of());
        persistCoverAfterCommit(itemId, parsedBook.cover());
        return obsoleteChapterAssetIds;
    }

    /**
     * 标记文本书籍解析失败。
     *
     * @param itemId 阅读条目 ID
     * @param errorCode 稳定错误码
     * @param message 错误摘要
     */
    @Transactional(rollbackFor = Exception.class)
    public void markFailed(UUID itemId, String errorCode, String message) {
        itemRepository.findById(itemId).ifPresent(item -> {
            item.setImportStatus("FAILED");
            item.setParseErrorCode(errorCode);
            item.setParseErrorMessage(message);
            itemRepository.save(item);
            syncEventService.invalidate(item.getOwnerUserId(), SyncScope.READER, "READER_LIBRARY", Map.of());
        });
    }

    /**
     * 获取文本书籍章节清单。
     *
     * @param ownerUserId 当前用户 ID
     * @param itemId 阅读条目 ID
     * @return 文本清单
     */
    @Transactional(readOnly = true)
    public TextManifestDto getManifest(UUID ownerUserId, UUID itemId) {
        ReaderItem item = readerItemService.requireItem(ownerUserId, itemId);
        if (!"TEXT".equalsIgnoreCase(item.getContentKind())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "当前条目不是文本书籍");
        }
        List<TextChapterDto> chapters = chapterRepository.findByReaderItemIdOrderByChapterIndex(itemId).stream()
                .map(chapter -> new TextChapterDto(
                        chapter.getChapterIndex(),
                        chapter.getChapterKey(),
                        chapter.getTitle(),
                        chapter.getContentPath(),
                        chapter.getSourceStartOffset(),
                        chapter.getSourceEndOffset(),
                        chapter.getCharCount(),
                        chapter.getLevel(),
                        chapter.getBodyStartOffset()
                ))
                .toList();
        // 解析任务记录归条目所有者，共享成员查自己的用户 id 永远查不到进度与失败原因。
        TextParseTaskDto parseTask = taskRecordService
                .findLatestTaskByPayload(item.getOwnerUserId(), "READER_PARSE", "itemId", itemId)
                .map(this::toParseTaskDto)
                .orElse(null);
        return new TextManifestDto(
                item.getId(),
                item.getTitle(),
                item.getAuthorName(),
                item.getDescription(),
                item.getPublisher(),
                item.getLanguage(),
                item.getImportStatus(),
                item.getParseErrorCode(),
                item.getParseErrorMessage(),
                chapters,
                parseTask
        );
    }

    private TextParseTaskDto toParseTaskDto(TaskRecord task) {
        return new TextParseTaskDto(
                task.getId(),
                task.getStatus(),
                task.getProgress(),
                task.getErrorMessage(),
                task.getUpdatedAt()
        );
    }

    private ReaderTextChapter toEntity(UUID itemId, TextChapterDraft draft) {
        ReaderTextChapter chapter = new ReaderTextChapter();
        chapter.setReaderItemId(itemId);
        chapter.setChapterIndex(draft.chapterIndex());
        chapter.setChapterKey(draft.chapterKey());
        chapter.setTitle(draft.title());
        chapter.setContentPath(draft.contentPath());
        chapter.setSourceStartOffset(draft.sourceStartOffset());
        chapter.setSourceEndOffset(draft.sourceEndOffset());
        chapter.setCharCount(draft.charCount());
        chapter.setLevel(draft.level());
        chapter.setBodyStartOffset(draft.bodyStartOffset());
        return chapter;
    }

    private void applyParsedMetadata(ReaderItem item, ParsedTextBook parsedBook) {
        if (parsedBook.title() != null && !parsedBook.title().isBlank()) {
            item.setTitle(parsedBook.title().trim());
        }
        if (parsedBook.author() != null && !parsedBook.author().isBlank()) {
            item.setAuthorName(parsedBook.author().trim());
        }
        if ((item.getLanguage() == null || item.getLanguage().isBlank())
                && parsedBook.language() != null
                && !parsedBook.language().isBlank()) {
            item.setLanguage(parsedBook.language());
        }
    }

    private void persistCoverAfterCommit(UUID itemId, ReaderCoverDraft cover) {
        if (cover == null) {
            return;
        }
        Runnable persistCover = () -> {
            try {
                coverExtractionService.storeIfAbsent(itemId, cover);
            } catch (RuntimeException exception) {
                log.warn("文本书籍封面自动保存失败: itemId={}, errorType={}",
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
     * 文本书籍清单响应。
     *
     * @param itemId 阅读条目 ID
     * @param title 标题
     * @param author 作者
     * @param description 简介
     * @param publisher 出版方
     * @param language 语言
     * @param importStatus 解析状态
     * @param errorCode 错误码
     * @param errorMessage 错误摘要
     * @param chapters 章节清单
     * @param parseTask 最近一次解析任务状态
     */
    public record TextManifestDto(
            UUID itemId,
            String title,
            String author,
            String description,
            String publisher,
            String language,
            String importStatus,
            String errorCode,
            String errorMessage,
            List<TextChapterDto> chapters,
            TextParseTaskDto parseTask
    ) {
    }

    /**
     * 文本书籍解析任务状态 DTO。
     *
     * @param id 任务 ID
     * @param status 任务状态
     * @param progress 解析进度（0-100）
     * @param errorMessage 错误摘要
     * @param updatedAt 最近更新时间
     */
    public record TextParseTaskDto(
            UUID id,
            String status,
            int progress,
            String errorMessage,
            Instant updatedAt
    ) {
    }

    /**
     * 文本章节清单响应。
     *
     * @param index 章节顺序
     * @param chapterKey 稳定章节键
     * @param title 标题
     * @param contentPath EPUB 正文路径
     * @param sourceStartOffset TXT 起始字符偏移
     * @param sourceEndOffset TXT 结束字符偏移
     * @param charCount 字符数
     * @param level 目录层级
     * @param bodyStartOffset TXT 正文起点相对章节起点的偏移，标题行不计入；EPUB 为 null
     */
    public record TextChapterDto(
            int index,
            String chapterKey,
            String title,
            String contentPath,
            Long sourceStartOffset,
            Long sourceEndOffset,
            int charCount,
            int level,
            Integer bodyStartOffset
    ) {
    }
}
