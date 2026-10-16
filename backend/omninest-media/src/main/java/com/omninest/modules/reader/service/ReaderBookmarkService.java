package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderBookmark;
import com.omninest.modules.reader.dto.ReaderDtos.CreateBookmarkRequest;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderBookmarkDto;
import com.omninest.modules.reader.repository.ReaderBookmarkRepository;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 阅读书签服务：管理书签的创建、查询与删除。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderBookmarkService {

    private final ReaderBookmarkRepository bookmarkRepository;
    private final MediaSyncEventService syncEventService;
    private final ReaderItemService readerItemService;

    /**
     * 列出指定条目的所有书签。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @return 书签列表
     */
    @Transactional(readOnly = true)
    public List<ReaderBookmarkDto> listBookmarks(UUID ownerUserId, UUID readerItemId) {
        return bookmarkRepository.findByOwnerUserIdAndReaderItemIdOrderByCreatedAtDesc(ownerUserId, readerItemId)
                .stream()
                .map(this::toDto)
                .toList();
    }

    /**
     * 创建书签。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @param request      创建请求
     * @return 创建的书签 DTO
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderBookmarkDto createBookmark(UUID ownerUserId, UUID readerItemId, CreateBookmarkRequest request) {
        if (request == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "书签请求参数不能为空");
        }
        // 书签归属按 (owner, item) 落库，不校验条目可读性就会给不存在或无权阅读的条目写出孤儿行。
        readerItemService.requireItem(ownerUserId, readerItemId);
        String clientOperationId = normalizeClientOperationId(request.clientOperationId());
        ReaderBookmark existing = findExistingByClientOperationId(ownerUserId, readerItemId, clientOperationId);
        if (existing != null) {
            return toDto(existing);
        }

        ReaderBookmark bookmark = new ReaderBookmark();
        bookmark.setOwnerUserId(ownerUserId);
        bookmark.setReaderItemId(readerItemId);
        bookmark.setChapterId(normalizeChapterId(request.chapterId()));
        bookmark.setClientOperationId(clientOperationId);
        bookmark.setCharOffset(request.charOffset());
        // 进度百分比夹紧到 [0, 1]，全程 BigDecimal 运算，禁止转 double（阿里 Java 手册规范）
        BigDecimal clampedPercent = request.progressPercent()
                .max(BigDecimal.ZERO)
                .min(BigDecimal.ONE);
        bookmark.setProgressPercent(clampedPercent);
        bookmark.setNote(request.note());
        try {
            ReaderBookmark saved = bookmarkRepository.saveAndFlush(bookmark);
            recordBookmarkEvent(ownerUserId, saved, SyncAction.CREATED);
            log.info("创建书签: userId={}, itemId={}, offset={}", ownerUserId, readerItemId, request.charOffset());
            return toDto(saved);
        } catch (DataIntegrityViolationException exception) {
            return resolveCreateConflict(ownerUserId, readerItemId, clientOperationId, exception);
        }
    }

    /**
     * 删除书签。
     *
     * @param ownerUserId 所有者用户 ID
     * @param bookmarkId  书签 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteBookmark(UUID ownerUserId, UUID bookmarkId) {
        ReaderBookmark bookmark = bookmarkRepository.findById(bookmarkId)
                .filter(b -> b.getOwnerUserId().equals(ownerUserId))
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "书签不存在"));
        bookmarkRepository.delete(bookmark);
        recordBookmarkEvent(ownerUserId, bookmark, SyncAction.DELETED);
        log.info("删除书签: userId={}, bookmarkId={}", ownerUserId, bookmarkId);
    }

    /**
     * 实体转 DTO。
     */
    private ReaderBookmarkDto toDto(ReaderBookmark bookmark) {
        return new ReaderBookmarkDto(
                bookmark.getId(),
                bookmark.getReaderItemId(),
                bookmark.getChapterId(),
                bookmark.getCharOffset(),
                bookmark.getProgressPercent(),
                bookmark.getNote(),
                bookmark.getCreatedAt()
        );
    }

    /**
     * 规范化章节标识。
     */
    private String normalizeChapterId(String chapterId) {
        if (chapterId == null || chapterId.isBlank()) {
            return null;
        }
        return chapterId.trim();
    }

    /**
     * 规范化客户端操作号。
     */
    private String normalizeClientOperationId(String clientOperationId) {
        if (clientOperationId == null || clientOperationId.isBlank()) {
            return null;
        }
        return clientOperationId.trim();
    }

    /**
     * 按客户端操作号查找已创建书签。
     */
    private ReaderBookmark findExistingByClientOperationId(
            UUID ownerUserId,
            UUID readerItemId,
            String clientOperationId
    ) {
        if (clientOperationId == null) {
            return null;
        }
        return bookmarkRepository
                .findByOwnerUserIdAndReaderItemIdAndClientOperationId(ownerUserId, readerItemId, clientOperationId)
                .orElse(null);
    }

    /**
     * 处理并发创建导致的唯一约束冲突。
     */
    private ReaderBookmarkDto resolveCreateConflict(
            UUID ownerUserId,
            UUID readerItemId,
            String clientOperationId,
            DataIntegrityViolationException exception
    ) {
        ReaderBookmark existing = findExistingByClientOperationId(ownerUserId, readerItemId, clientOperationId);
        if (existing != null) {
            return toDto(existing);
        }
        throw exception;
    }

    private void recordBookmarkEvent(UUID ownerUserId, ReaderBookmark bookmark, SyncAction action) {
        syncEventService.record(
                ownerUserId,
                SyncScope.READER,
                "READER_BOOKMARK",
                bookmark.getId() == null ? null : bookmark.getId().toString(),
                action,
                null,
                Map.of("readerItemId", bookmark.getReaderItemId().toString())
        );
    }
}
