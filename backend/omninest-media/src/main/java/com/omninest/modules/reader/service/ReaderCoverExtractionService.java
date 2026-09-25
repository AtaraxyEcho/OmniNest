package com.omninest.modules.reader.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 阅读条目自动封面持久化服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderCoverExtractionService {



    private final MediaProcessingLimitsProperties processingLimits;
    private final ReaderItemRepository itemRepository;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final MediaSyncEventService syncEventService;

    /**
     * 在条目没有封面时保存解析得到的封面。
     *
     * @param itemId 阅读条目 ID
     * @param cover 封面草稿
     * @return 成功补充封面时返回 true
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public boolean storeIfAbsent(UUID itemId, ReaderCoverDraft cover) {
        return store(itemId, cover, false);
    }

    /**
     * 保存封面；内容变更后可强制覆盖旧封面。
     *
     * @param itemId 阅读条目 ID
     * @param cover 封面草稿
     * @param overwrite 已有封面时是否替换
     * @return 成功保存封面时返回 true
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public boolean store(UUID itemId, ReaderCoverDraft cover, boolean overwrite) {
        if (cover == null || cover.content() == null || cover.content().length == 0) {
            return false;
        }
        if (cover.content().length > processingLimits.getMaxReaderCoverBytes()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面图片超过大小限制");
        }

        ReaderItem item = itemRepository.findById(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在"));
        if (item.getCoverFileId() != null && !overwrite) {
            return false;
        }

        CoverFormat format = detectFormat(cover.content());
        UUID coverFileId = null;
        try (ByteArrayInputStream input = new ByteArrayInputStream(cover.content())) {
            String fileName = "cover_" + itemId + format.extension();
            coverFileId = derivedAssetStorageService.store(
                    item.getOwnerUserId(),
                    "READER_ITEM",
                    itemId,
                    "COVER",
                    fileName,
                    format.mimeType(),
                    input
            );
            item.setCoverFileId(coverFileId);
            itemRepository.saveAndFlush(item);
            syncEventService.invalidate(item.getOwnerUserId(), SyncScope.READER, "READER_LIBRARY", Map.of());
            log.info("自动提取阅读封面完成: itemId={}, overwrite={}", itemId, overwrite);
            return true;
        } catch (RuntimeException exception) {
            if (coverFileId != null) {
                derivedAssetStorageService.deleteOwned(item.getOwnerUserId(), coverFileId);
            }
            throw exception;
        } catch (IOException exception) {
            if (coverFileId != null) {
                derivedAssetStorageService.deleteOwned(item.getOwnerUserId(), coverFileId);
            }
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "封面图片保存失败");
        }
    }

    private CoverFormat detectFormat(byte[] content) {
        if (content.length >= 3
                && content[0] == (byte) 0xFF
                && content[1] == (byte) 0xD8
                && content[2] == (byte) 0xFF) {
            return new CoverFormat("image/jpeg", ".jpg");
        }
        if (content.length >= 8
                && content[0] == (byte) 0x89
                && content[1] == 0x50
                && content[2] == 0x4E
                && content[3] == 0x47) {
            return new CoverFormat("image/png", ".png");
        }
        if (content.length >= 6
                && content[0] == 'G'
                && content[1] == 'I'
                && content[2] == 'F') {
            return new CoverFormat("image/gif", ".gif");
        }
        if (content.length >= 12
                && content[0] == 'R'
                && content[1] == 'I'
                && content[2] == 'F'
                && content[3] == 'F'
                && content[8] == 'W'
                && content[9] == 'E'
                && content[10] == 'B'
                && content[11] == 'P') {
            return new CoverFormat("image/webp", ".webp");
        }
        if (content.length >= 2 && content[0] == 'B' && content[1] == 'M') {
            return new CoverFormat("image/bmp", ".bmp");
        }
        if (content.length >= 12
                && content[4] == 'f'
                && content[5] == 't'
                && content[6] == 'y'
                && content[7] == 'p'
                && content[8] == 'a'
                && content[9] == 'v'
                && content[10] == 'i'
                && (content[11] == 'f' || content[11] == 's')) {
            return new CoverFormat("image/avif", ".avif");
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "封面图片格式不受支持");
    }

    private record CoverFormat(String mimeType, String extension) {
    }
}
