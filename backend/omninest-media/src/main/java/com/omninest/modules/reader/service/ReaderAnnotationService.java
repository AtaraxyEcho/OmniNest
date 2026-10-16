package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderAnnotation;
import com.omninest.modules.reader.dto.ReaderDtos.CreateAnnotationRequest;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderAnnotationDto;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateAnnotationRequest;
import com.omninest.modules.reader.repository.ReaderAnnotationRepository;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 阅读批注服务：管理高亮批注的创建、查询、更新与删除。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderAnnotationService {

    private final ReaderAnnotationRepository annotationRepository;
    private final MediaSyncEventService syncEventService;
    private final ReaderItemService readerItemService;

    /**
     * 列出指定条目的所有批注。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @return 批注列表
     */
    @Transactional(readOnly = true)
    public List<ReaderAnnotationDto> listAnnotations(UUID ownerUserId, UUID readerItemId) {
        return annotationRepository.findByOwnerUserIdAndReaderItemIdOrderByCreatedAtDesc(ownerUserId, readerItemId)
                .stream()
                .map(this::toDto)
                .toList();
    }

    /**
     * 创建批注。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @param request      创建请求
     * @return 创建的批注 DTO
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderAnnotationDto createAnnotation(UUID ownerUserId, UUID readerItemId, CreateAnnotationRequest request) {
        if (request == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "批注请求参数不能为空");
        }
        readerItemService.requireItem(ownerUserId, readerItemId);
        String clientOperationId = normalizeClientOperationId(request.clientOperationId());
        ReaderAnnotation existing = findExistingByClientOperationId(ownerUserId, readerItemId, clientOperationId);
        if (existing != null) {
            return toDto(existing);
        }

        ReaderAnnotation annotation = new ReaderAnnotation();
        annotation.setOwnerUserId(ownerUserId);
        annotation.setReaderItemId(readerItemId);
        annotation.setChapterId(normalizeChapterId(request.chapterId()));
        annotation.setClientOperationId(clientOperationId);
        annotation.setStartOffset(request.startOffset());
        annotation.setEndOffset(request.endOffset());
        annotation.setHighlightText(request.highlightText());
        annotation.setNote(request.note());
        if (request.color() != null && !request.color().isBlank()) {
            annotation.setColor(request.color());
        }
        try {
            ReaderAnnotation saved = annotationRepository.saveAndFlush(annotation);
            recordAnnotationEvent(ownerUserId, saved, SyncAction.CREATED);
            log.info(
                    "创建批注: userId={}, itemId={}, startOffset={}, endOffset={}",
                    ownerUserId,
                    readerItemId,
                    request.startOffset(),
                    request.endOffset()
            );
            return toDto(saved);
        } catch (DataIntegrityViolationException exception) {
            return resolveCreateConflict(ownerUserId, readerItemId, clientOperationId, exception);
        }
    }

    /**
     * 更新批注（仅允许更新备注和颜色）。
     *
     * @param ownerUserId  所有者用户 ID
     * @param annotationId 批注 ID
     * @param request      更新请求
     * @return 更新后的批注 DTO
     */
    @Transactional(rollbackFor = Exception.class)
    public ReaderAnnotationDto updateAnnotation(UUID ownerUserId, UUID annotationId, UpdateAnnotationRequest request) {
        if (request == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "批注更新请求参数不能为空");
        }
        ReaderAnnotation annotation = requireAnnotation(ownerUserId, annotationId);
        // null 表示本次不改备注；空串是用户把备注清空，保留高亮本体。
        if (request.note() != null) {
            annotation.setNote(request.note().isBlank() ? null : request.note());
        }
        if (request.color() != null && !request.color().isBlank()) {
            annotation.setColor(request.color());
        }
        ReaderAnnotation saved = annotationRepository.save(annotation);
        recordAnnotationEvent(ownerUserId, saved, SyncAction.UPDATED);
        log.info("更新批注: userId={}, annotationId={}", ownerUserId, annotationId);
        return toDto(saved);
    }

    /**
     * 删除批注。
     *
     * @param ownerUserId  所有者用户 ID
     * @param annotationId 批注 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteAnnotation(UUID ownerUserId, UUID annotationId) {
        ReaderAnnotation annotation = requireAnnotation(ownerUserId, annotationId);
        annotationRepository.delete(annotation);
        recordAnnotationEvent(ownerUserId, annotation, SyncAction.DELETED);
        log.info("删除批注: userId={}, annotationId={}", ownerUserId, annotationId);
    }

    /**
     * 查找批注并校验所有权。
     */
    private ReaderAnnotation requireAnnotation(UUID ownerUserId, UUID annotationId) {
        return annotationRepository.findById(annotationId)
                .filter(a -> a.getOwnerUserId().equals(ownerUserId))
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "批注不存在"));
    }

    /**
     * 实体转 DTO。
     */
    private ReaderAnnotationDto toDto(ReaderAnnotation annotation) {
        return new ReaderAnnotationDto(
                annotation.getId(),
                annotation.getReaderItemId(),
                annotation.getChapterId(),
                annotation.getStartOffset(),
                annotation.getEndOffset(),
                annotation.getHighlightText(),
                annotation.getNote(),
                annotation.getColor(),
                annotation.getCreatedAt()
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
     * 规范化章节标识。
     *
     * @param chapterId 客户端章节标识
     * @return 去除首尾空白后的章节标识，空值返回 {@code null}
     */
    private String normalizeChapterId(String chapterId) {
        if (chapterId == null || chapterId.isBlank()) {
            return null;
        }
        return chapterId.trim();
    }

    /**
     * 按客户端操作号查找已创建批注。
     */
    private ReaderAnnotation findExistingByClientOperationId(
            UUID ownerUserId,
            UUID readerItemId,
            String clientOperationId
    ) {
        if (clientOperationId == null) {
            return null;
        }
        return annotationRepository
                .findByOwnerUserIdAndReaderItemIdAndClientOperationId(ownerUserId, readerItemId, clientOperationId)
                .orElse(null);
    }

    /**
     * 处理并发创建导致的唯一约束冲突。
     */
    private ReaderAnnotationDto resolveCreateConflict(
            UUID ownerUserId,
            UUID readerItemId,
            String clientOperationId,
            DataIntegrityViolationException exception
    ) {
        ReaderAnnotation existing = findExistingByClientOperationId(ownerUserId, readerItemId, clientOperationId);
        if (existing != null) {
            return toDto(existing);
        }
        throw exception;
    }

    private void recordAnnotationEvent(UUID ownerUserId, ReaderAnnotation annotation, SyncAction action) {
        syncEventService.record(
                ownerUserId,
                SyncScope.READER,
                "READER_ANNOTATION",
                annotation.getId() == null ? null : annotation.getId().toString(),
                action,
                annotation.getVersion(),
                Map.of("readerItemId", annotation.getReaderItemId().toString())
        );
    }
}
