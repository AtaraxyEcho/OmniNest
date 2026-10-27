package com.omninest.modules.reader.service;

import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderBookshelf;
import com.omninest.modules.reader.repository.ReaderBookshelfRepository;
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
 * 阅读书架服务：管理书架的添加与移除。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderBookshelfService {

    private final ReaderBookshelfRepository bookshelfRepository;
    private final ReaderItemService readerItemService;
    private final MediaSyncEventService syncEventService;
    private final TransactionTemplate transactionTemplate;

    /**
     * 切换书架状态：已存在则移除，不存在则添加。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @return true 表示已添加到书架，false 表示已从书架移除
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean toggleBookshelf(UUID ownerUserId, UUID readerItemId) {
        if (bookshelfRepository.existsByOwnerUserIdAndReaderItemId(ownerUserId, readerItemId)) {
            removeFromBookshelf(ownerUserId, readerItemId);
            return false;
        }
        addToBookshelf(ownerUserId, readerItemId);
        return true;
    }

    /**
     * 幂等设定书架状态：请求重放或多端并发点击不会把结果翻回相反值。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @param onBookshelf  true 表示加入书架，false 表示移除
     * @return 设定后的书架状态
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean setBookshelf(UUID ownerUserId, UUID readerItemId, boolean onBookshelf) {
        if (bookshelfRepository.existsByOwnerUserIdAndReaderItemId(ownerUserId, readerItemId) == onBookshelf) {
            return onBookshelf;
        }
        if (onBookshelf) {
            addToBookshelf(ownerUserId, readerItemId);
        } else {
            removeFromBookshelf(ownerUserId, readerItemId);
        }
        return onBookshelf;
    }

    private void addToBookshelf(UUID ownerUserId, UUID readerItemId) {
        // 书架行按 (owner, item) 落库，不校验条目可读性就会给不存在或无权阅读的条目写出孤儿行。
        readerItemService.requireItem(ownerUserId, readerItemId);
        ReaderBookshelf entry = new ReaderBookshelf();
        entry.setOwnerUserId(ownerUserId);
        entry.setReaderItemId(readerItemId);
        try {
            saveInNewTransaction(entry);
        } catch (DataIntegrityViolationException exception) {
            if (!bookshelfRepository.existsByOwnerUserIdAndReaderItemId(ownerUserId, readerItemId)) {
                throw exception;
            }
        }
        recordBookshelfEvent(ownerUserId, readerItemId, true);
        log.info("添加到书架: userId={}, itemId={}", ownerUserId, readerItemId);
    }

    private void removeFromBookshelf(UUID ownerUserId, UUID readerItemId) {
        bookshelfRepository.deleteByOwnerUserIdAndReaderItemId(ownerUserId, readerItemId);
        recordBookshelfEvent(ownerUserId, readerItemId, false);
        log.info("从书架移除: userId={}, itemId={}", ownerUserId, readerItemId);
    }

    /**
     * 在独立新事务里落这一行。
     *
     * <p>PostgreSQL 命中 {@code uniq_reader_bookshelf_owner_item} 后会把当前事务置为 aborted 态，
     * 同一事务里的后续语句一律报 "current transaction is aborted"；并发双加时的存在性回查必须换
     * 一个事务，否则本应返回既成事实的分支会变成 500。
     */
    private void saveInNewTransaction(ReaderBookshelf entry) {
        TransactionTemplate template = new TransactionTemplate(
                transactionTemplate.getTransactionManager());
        template.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        template.execute(status -> bookshelfRepository.saveAndFlush(entry));
    }

    /**
     * 判断阅读条目是否在当前用户书架中。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @return true 表示已加入书架
     */
    @Transactional(readOnly = true)
    public boolean isOnBookshelf(UUID ownerUserId, UUID readerItemId) {
        return bookshelfRepository.existsByOwnerUserIdAndReaderItemId(ownerUserId, readerItemId);
    }

    private void recordBookshelfEvent(UUID ownerUserId, UUID readerItemId, boolean onBookshelf) {
        syncEventService.record(
                ownerUserId,
                SyncScope.READER,
                "READER_BOOKSHELF",
                readerItemId.toString(),
                SyncAction.UPDATED,
                null,
                Map.of("onBookshelf", onBookshelf)
        );
    }
}
