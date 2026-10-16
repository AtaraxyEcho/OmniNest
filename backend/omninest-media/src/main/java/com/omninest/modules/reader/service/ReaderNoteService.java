package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderNote;
import com.omninest.modules.reader.dto.ReaderDtos.CreateNoteRequest;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderNoteDto;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateNoteRequest;
import com.omninest.modules.reader.repository.ReaderNoteRepository;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 阅读笔记服务：管理笔记的创建、查询、更新与删除。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderNoteService {

    private final ReaderNoteRepository noteRepository;
    private final MediaSyncEventService syncEventService;
    private final ReaderItemService readerItemService;
    private final TransactionTemplate transactionTemplate;

    /**
     * 列出指定条目的所有笔记。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @return 笔记列表
     */
    @Transactional(readOnly = true)
    public List<ReaderNoteDto> listNotes(UUID ownerUserId, UUID readerItemId) {
        return noteRepository.findByOwnerUserIdAndReaderItemIdOrderByCreatedAtDesc(ownerUserId, readerItemId)
                .stream()
                .map(this::toDto)
                .toList();
    }

    /**
     * 创建笔记。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @param request      创建请求
     * @return 创建的笔记 DTO
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderNoteDto createNote(UUID ownerUserId, UUID readerItemId, CreateNoteRequest request) {
        if (request == null || request.content() == null || request.content().isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "笔记内容不能为空");
        }
        readerItemService.requireItem(ownerUserId, readerItemId);
        String clientOperationId = normalizeClientOperationId(request.clientOperationId());
        ReaderNote existing = findExistingByClientOperationId(ownerUserId, readerItemId, clientOperationId);
        if (existing != null) {
            return toDto(existing);
        }

        ReaderNote note = new ReaderNote();
        note.setOwnerUserId(ownerUserId);
        note.setReaderItemId(readerItemId);
        note.setClientOperationId(clientOperationId);
        note.setCharOffset(request.charOffset());
        note.setTitle(request.title());
        note.setContent(request.content());
        try {
            ReaderNote saved = saveInNewTransaction(note);
            recordNoteEvent(ownerUserId, saved, SyncAction.CREATED);
            log.info("创建笔记: userId={}, itemId={}", ownerUserId, readerItemId);
            return toDto(saved);
        } catch (DataIntegrityViolationException exception) {
            return resolveCreateConflict(ownerUserId, readerItemId, clientOperationId, exception);
        }
    }

    /**
     * 在独立新事务里落这一行。
     *
     * <p>PostgreSQL 命中唯一约束后会把当前事务置为 aborted 态，同一事务里的后续语句一律报
     * "current transaction is aborted"；冲突回查必须换一个事务，否则离线队列重放并发撞上同一
     * {@code clientOperationId} 时，本应幂等返回已有记录的分支会变成 500。
     */
    private ReaderNote saveInNewTransaction(ReaderNote note) {
        TransactionTemplate template = new TransactionTemplate(
                transactionTemplate.getTransactionManager());
        template.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        return template.execute(status -> noteRepository.saveAndFlush(note));
    }

    /**
     * 更新笔记。
     *
     * @param ownerUserId 所有者用户 ID
     * @param noteId      笔记 ID
     * @param request     更新请求
     * @return 更新后的笔记 DTO
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderNoteDto updateNote(UUID ownerUserId, UUID noteId, UpdateNoteRequest request) {
        if (request == null || request.content() == null || request.content().isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "笔记内容不能为空");
        }
        ReaderNote note = requireNote(ownerUserId, noteId);
        if (request.title() != null) {
            note.setTitle(request.title());
        }
        note.setContent(request.content());
        ReaderNote saved = noteRepository.save(note);
        recordNoteEvent(ownerUserId, saved, SyncAction.UPDATED);
        log.info("更新笔记: userId={}, noteId={}", ownerUserId, noteId);
        return toDto(saved);
    }

    /**
     * 删除笔记。
     *
     * @param ownerUserId 所有者用户 ID
     * @param noteId      笔记 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteNote(UUID ownerUserId, UUID noteId) {
        ReaderNote note = requireNote(ownerUserId, noteId);
        noteRepository.delete(note);
        recordNoteEvent(ownerUserId, note, SyncAction.DELETED);
        log.info("删除笔记: userId={}, noteId={}", ownerUserId, noteId);
    }

    /**
     * 查找笔记并校验所有权。
     */
    private ReaderNote requireNote(UUID ownerUserId, UUID noteId) {
        return noteRepository.findById(noteId)
                .filter(n -> n.getOwnerUserId().equals(ownerUserId))
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "笔记不存在"));
    }

    /**
     * 实体转 DTO。
     */
    private ReaderNoteDto toDto(ReaderNote note) {
        return new ReaderNoteDto(
                note.getId(),
                note.getReaderItemId(),
                note.getCharOffset(),
                note.getTitle(),
                note.getContent(),
                note.getCreatedAt()
        );
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
     * 按客户端操作号查找已创建笔记。
     */
    private ReaderNote findExistingByClientOperationId(
            UUID ownerUserId,
            UUID readerItemId,
            String clientOperationId
    ) {
        if (clientOperationId == null) {
            return null;
        }
        return noteRepository
                .findByOwnerUserIdAndReaderItemIdAndClientOperationId(ownerUserId, readerItemId, clientOperationId)
                .orElse(null);
    }

    /**
     * 处理并发创建导致的唯一约束冲突。
     */
    private ReaderNoteDto resolveCreateConflict(
            UUID ownerUserId,
            UUID readerItemId,
            String clientOperationId,
            DataIntegrityViolationException exception
    ) {
        ReaderNote existing = findExistingByClientOperationId(ownerUserId, readerItemId, clientOperationId);
        if (existing != null) {
            return toDto(existing);
        }
        throw exception;
    }

    private void recordNoteEvent(UUID ownerUserId, ReaderNote note, SyncAction action) {
        syncEventService.record(
                ownerUserId,
                SyncScope.READER,
                "READER_NOTE",
                note.getId() == null ? null : note.getId().toString(),
                action,
                note.getVersion(),
                Map.of("readerItemId", note.getReaderItemId().toString())
        );
    }
}
