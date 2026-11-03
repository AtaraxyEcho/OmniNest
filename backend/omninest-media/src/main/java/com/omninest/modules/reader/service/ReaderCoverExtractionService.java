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
import jakarta.annotation.PostConstruct;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 阅读条目自动封面持久化服务。
 *
 * <p>封面字节写入对象存储不在数据库事务内进行：本服务只在“读条目当前指向”和
 * “把新节点写回条目”两段各开一个短事务，中间的上传与派生元数据落库由
 * {@link DerivedAssetStorageService} 自己的短事务负责，避免一个线程同时握着
 * 外层连接和子事务连接等待远程 IO。</p>
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
    private final PlatformTransactionManager transactionManager;

    private TransactionTemplate transactionTemplate;

    /**
     * 初始化封面持久化用的短事务模板。
     *
     * <p>必须是 REQUIRES_NEW：三个导入服务都在 {@code afterCommit} 里调用本方法，那时原事务
     * 已经提交但连接资源还绑定在线程上，REQUIRED 会挂进这个已完成的事务，写回的封面
     * 随连接归还一起被回滚。{@link DerivedAssetStorageService} 的元数据落库同理。</p>
     */
    @PostConstruct
    void initTransactionTemplate() {
        this.transactionTemplate = new TransactionTemplate(transactionManager);
        this.transactionTemplate.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    /**
     * 在条目没有封面时保存解析得到的封面。
     *
     * @param itemId 阅读条目 ID
     * @param cover 封面草稿
     * @return 成功补充封面时返回 true
     */
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
    public boolean store(UUID itemId, ReaderCoverDraft cover, boolean overwrite) {
        if (cover == null || cover.content() == null || cover.content().length == 0) {
            return false;
        }
        if (cover.content().length > processingLimits.getMaxReaderCoverBytes()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面图片超过大小限制");
        }

        CoverSlot slot = requireCoverSlot(itemId);
        if (slot.previousCoverFileId() != null && !overwrite) {
            return false;
        }

        CoverFormat format = detectFormat(cover.content());
        UUID coverFileId = null;
        try (ByteArrayInputStream input = new ByteArrayInputStream(cover.content())) {
            String fileName = "cover_" + itemId + format.extension();
            coverFileId = derivedAssetStorageService.store(
                    slot.ownerUserId(),
                    "READER_ITEM",
                    itemId,
                    "COVER",
                    fileName,
                    format.mimeType(),
                    input
            );
            applyCoverFileId(itemId, slot, coverFileId);
            log.info("自动提取阅读封面完成: itemId={}, overwrite={}", itemId, overwrite);
            return true;
        } catch (RuntimeException exception) {
            // 同一路径的派生存储会原地复用同一个 FileNode：新封面落库失败时该 ID
            // 可能仍是条目正在使用的旧封面，删除等于把既有封面清空。
            if (coverFileId != null && !Objects.equals(coverFileId, slot.previousCoverFileId())) {
                derivedAssetStorageService.deleteOwned(slot.ownerUserId(), coverFileId);
            }
            throw exception;
        } catch (IOException exception) {
            if (coverFileId != null && !Objects.equals(coverFileId, slot.previousCoverFileId())) {
                derivedAssetStorageService.deleteOwned(slot.ownerUserId(), coverFileId);
            }
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "封面图片保存失败");
        }
    }

    /**
     * 短事务：读取条目当前指向的封面，作为覆盖判定与并发校验的基线。
     */
    private CoverSlot requireCoverSlot(UUID itemId) {
        CoverSlot slot = transactionTemplate.execute(status -> itemRepository.findById(itemId)
                .map(item -> new CoverSlot(item.getOwnerUserId(), item.getCoverFileId()))
                .orElse(null));
        if (slot == null) {
            throw new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在");
        }
        return slot;
    }

    /**
     * 短事务：把新封面节点写回条目，并沿用同一份基线做并发校验。
     *
     * <p>上传期间条目指向被别的写入改掉时本次结果作废：调用方的封面只是自动提取的产物，
     * 不能覆盖已经生效的用户选择。</p>
     */
    private void applyCoverFileId(UUID itemId, CoverSlot slot, UUID coverFileId) {
        transactionTemplate.executeWithoutResult(status -> {
            ReaderItem item = itemRepository.findById(itemId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在"));
            if (!Objects.equals(item.getCoverFileId(), slot.previousCoverFileId())) {
                throw new BusinessException(ErrorCode.FILE_LIFECYCLE_CONFLICT, "封面已被并发更新");
            }
            item.setCoverFileId(coverFileId);
            itemRepository.saveAndFlush(item);
            syncEventService.invalidate(item.getOwnerUserId(), SyncScope.READER, "READER_LIBRARY", Map.of());
            registerReplacedCoverCleanup(slot.previousCoverFileId(), coverFileId, item);
        });
    }

    /** 条目的封面基线：所有者与写入前指向的节点。 */
    private record CoverSlot(UUID ownerUserId, UUID previousCoverFileId) {
    }

    /**
     * 事务提交后删除被本次覆盖替换掉的旧派生封面。
     *
     * <p>三条约束决定时机与范围：同一路径的派生存储会原地复用同一个 FileNode，新旧同节点时
     * 删除等于把刚写好的封面清掉；去重后的另一条目可能仍引用它；提交失败回滚时条目还指向
     * 旧封面，先删对象就只剩一个指向空对象的节点。
     *
     * @param previousCoverFileId 被替换的旧封面节点 ID
     * @param coverFileId 条目现在指向的封面节点 ID
     * @param item 当前条目
     */
    private void registerReplacedCoverCleanup(
            UUID previousCoverFileId,
            UUID coverFileId,
            ReaderItem item) {
        if (previousCoverFileId == null || previousCoverFileId.equals(coverFileId)) {
            return;
        }
        long referencingOthers = itemRepository
                .findByCoverFileIdIn(List.of(previousCoverFileId)).stream()
                .filter(candidate -> !candidate.getId().equals(item.getId()))
                .count();
        if (referencingOthers > 0) {
            log.info("派生封面仍被其他阅读条目引用，跳过清理: coverFileId={}, others={}",
                    previousCoverFileId, referencingOthers);
            return;
        }
        Runnable cleanup = () -> {
            try {
                derivedAssetStorageService.deleteDerivedFileNode(previousCoverFileId);
            } catch (RuntimeException exception) {
                log.warn("旧派生封面清理失败: coverFileId={}, errorType={}",
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
