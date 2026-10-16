package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPage;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderProgressDto;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateProgressRequest;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 阅读进度服务：记录与查询用户的阅读进度。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderProgressService {

    private static final Set<String> ALLOWED_READING_MODES = Set.of("scroll", "page");

    private final ReaderItemRepository itemRepository;
    private final ReaderItemSourceRepository sourceRepository;
    private final ReaderPageRepository pageRepository;
    private final ReaderProgressRepository progressRepository;
    private final MediaSyncEventService syncEventService;
    private final ReaderItemService readerItemService;

    /**
     * 获取指定条目的阅读进度。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @return 进度 DTO，无进度记录时返回 null
     */
    @Transactional(readOnly = true)
    public ReaderProgressDto getProgress(UUID ownerUserId, UUID readerItemId) {
        return progressRepository.findByOwnerUserIdAndReaderItemId(ownerUserId, readerItemId)
                .map(this::toDto)
                .orElse(null);
    }

    /**
     * 更新阅读进度（Upsert 语义：存在则更新，不存在则创建）。
     *
     * <p>使用原生 SQL upsert 绕过 JPA 乐观锁，保证并发安全；写入按客户端上报时间围栏，
     * 早于已存记录的上报不会覆盖其他设备刚写入的位置，此时不产生同步事件。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @param request      进度更新请求
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateProgress(UUID ownerUserId, UUID readerItemId, UpdateProgressRequest request) {
        if (request == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "进度请求参数不能为空");
        }
        ReaderItem item = readerItemService.requireItem(ownerUserId, readerItemId);
        String readingMode = normalizeReadingMode(request.readingMode());
        validateComicAnchor(item, request);
        String chapterId = (request.chapterId() != null) ? request.chapterId() : "";
        // 进度百分比夹紧到 [0, 1]，防止客户端浮点误差违反数据库约束
        // 全程 BigDecimal 运算，禁止转 double 丢失精度（阿里 Java 手册规范）
        BigDecimal progressPercent = request.progressPercent() != null ? request.progressPercent() : BigDecimal.ZERO;
        BigDecimal clampedPercent = progressPercent
                .max(BigDecimal.ZERO)
                .min(BigDecimal.ONE);
        Double intraPageOffset = clampIntraPageOffset(request.intraPageOffset());
        // 缺少上报时间时按服务端接收时间处理：退化成"最新到达胜出"，而不是把写入永久挡住。
        Instant clientUpdatedAt = request.clientUpdatedAt() != null ? request.clientUpdatedAt() : Instant.now();
        int applied = progressRepository.upsertProgress(
                ownerUserId,
                readerItemId,
                request.charOffset(),
                clampedPercent,
                readingMode,
                chapterId,
                request.pageId(),
                request.pageIndex(),
                request.pageFingerprint(),
                request.sourceId(),
                request.sourcePageIndex(),
                request.catalogKey(),
                request.manifestVersion(),
                intraPageOffset,
                clientUpdatedAt);
        if (applied == 0) {
            log.debug("阅读进度上报早于已存记录，已忽略: userId={}, itemId={}, reportedAt={}",
                    ownerUserId, readerItemId, clientUpdatedAt);
            return;
        }
        syncEventService.record(
                ownerUserId,
                SyncScope.READER,
                "READER_PROGRESS",
                readerItemId.toString(),
                SyncAction.PROGRESS,
                null,
                Map.of("progressPercent", clampedPercent)
        );
        log.debug("更新阅读进度: userId={}, itemId={}, percent={}", ownerUserId, readerItemId, progressPercent);
    }

    /**
     * 规范化阅读模式，仅允许数据库约束支持的模式。
     */
    private String normalizeReadingMode(String readingMode) {
        if (readingMode == null || readingMode.isBlank()) {
            return "scroll";
        }
        String normalized = readingMode.trim();
        if (!ALLOWED_READING_MODES.contains(normalized)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "不支持的阅读模式");
        }
        return normalized;
    }

    /**
     * 校验漫画页面锚点必须归属于当前阅读条目。
     */
    private void validateComicAnchor(ReaderItem item, UpdateProgressRequest request) {
        UUID readerItemId = item.getId();
        if (request.pageIndex() != null && request.pageIndex() < 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "漫画页码不能为负数");
        }
        ReaderPage page = null;
        if (request.pageId() != null) {
            page = pageRepository.findById(request.pageId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.PARAM_ERROR, "漫画页面不存在"));
            if (!readerItemId.equals(page.getReaderItemId())) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "漫画页面不属于该阅读条目");
            }
        }
        if (request.sourceId() != null) {
            ReaderItemSource source = sourceRepository.findById(request.sourceId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.PARAM_ERROR, "漫画来源不存在"));
            if (!readerItemId.equals(source.getReaderItemId())) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "漫画来源不属于该阅读条目");
            }
            if (page != null && !request.sourceId().equals(page.getSourceId())) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "漫画页面与来源不一致");
            }
        }
    }

    /**
     * 将漫画页内偏移限制在 0 到 1 之间。
     */
    private Double clampIntraPageOffset(Double intraPageOffset) {
        if (intraPageOffset == null) {
            return null;
        }
        return Math.max(0.0, Math.min(1.0, intraPageOffset));
    }

    /**
     * 实体转 DTO。
     */
    private ReaderProgressDto toDto(ReaderProgress progress) {
        return new ReaderProgressDto(
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
    }
}
