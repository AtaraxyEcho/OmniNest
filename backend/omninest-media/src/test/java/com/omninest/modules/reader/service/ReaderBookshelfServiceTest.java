package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderBookshelf;
import com.omninest.modules.reader.repository.ReaderBookshelfRepository;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 阅读书架服务单元测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderBookshelfServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    @Mock
    private ReaderBookshelfRepository bookshelfRepository;
    @Mock
    private ReaderItemService readerItemService;
    @Mock
    private MediaSyncEventService syncEventService;
    @Mock
    private PlatformTransactionManager transactionManager;

    private ReaderBookshelfService bookshelfService;

    @BeforeEach
    void setUp() {
        bookshelfService = new ReaderBookshelfService(
                bookshelfRepository,
                readerItemService,
                syncEventService,
                new TransactionTemplate(transactionManager)
        );
    }

    @Test
    void toggleAddsToBookshelfAfterCheckingItemIsReadable() {
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.saveAndFlush(any(ReaderBookshelf.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        boolean result = bookshelfService.toggleBookshelf(OWNER_ID, ITEM_ID);

        assertThat(result).isTrue();
        // 书架行按 (owner, item) 落库，缺了可读性校验就能给不存在或他人私有条目写孤儿行
        verify(readerItemService).requireItem(OWNER_ID, ITEM_ID);
        ArgumentCaptor<ReaderBookshelf> captor = ArgumentCaptor.forClass(ReaderBookshelf.class);
        verify(bookshelfRepository).saveAndFlush(captor.capture());
        assertThat(captor.getValue().getOwnerUserId()).isEqualTo(OWNER_ID);
        assertThat(captor.getValue().getReaderItemId()).isEqualTo(ITEM_ID);
    }

    @Test
    void toggleRejectsUnreadableItemWithoutWritingRow() {
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, ITEM_ID)).thenReturn(false);
        Mockito.doThrow(new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在"))
                .when(readerItemService).requireItem(OWNER_ID, ITEM_ID);

        assertThatThrownBy(() -> bookshelfService.toggleBookshelf(OWNER_ID, ITEM_ID))
                .isInstanceOf(BusinessException.class);
        verify(bookshelfRepository, never()).saveAndFlush(any(ReaderBookshelf.class));
    }

    @Test
    void concurrentAddReturnsTrueAfterConflictLookupInNewTransaction() {
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, ITEM_ID))
                .thenReturn(false).thenReturn(true);
        when(bookshelfRepository.saveAndFlush(any(ReaderBookshelf.class)))
                .thenThrow(new DataIntegrityViolationException("uniq_reader_bookshelf_owner_item"));

        boolean result = bookshelfService.toggleBookshelf(OWNER_ID, ITEM_ID);

        assertThat(result).isTrue();
        ArgumentCaptor<TransactionDefinition> definition = ArgumentCaptor.forClass(TransactionDefinition.class);
        verify(transactionManager).getTransaction(definition.capture());
        // 回查必须落在健康事务上：同一事务里撞过唯一键后 PostgreSQL 已进入 aborted 态
        assertThat(definition.getValue().getPropagationBehavior())
                .isEqualTo(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    @Test
    void toggleRemovesFromBookshelf() {
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, ITEM_ID)).thenReturn(true);

        boolean result = bookshelfService.toggleBookshelf(OWNER_ID, ITEM_ID);

        assertThat(result).isFalse();
        verify(bookshelfRepository).deleteByOwnerUserIdAndReaderItemId(OWNER_ID, ITEM_ID);
        verify(readerItemService, never()).requireItem(OWNER_ID, ITEM_ID);
    }

    @Test
    void setBookshelfIsIdempotentWhenTargetStateAlreadyHolds() {
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, ITEM_ID)).thenReturn(true);

        // 重放的"加入书架"请求不能把已存在的书架行删掉。
        assertThat(bookshelfService.setBookshelf(OWNER_ID, ITEM_ID, true)).isTrue();

        verify(bookshelfRepository, never()).deleteByOwnerUserIdAndReaderItemId(OWNER_ID, ITEM_ID);
        verify(bookshelfRepository, never()).saveAndFlush(any(ReaderBookshelf.class));
    }

    @Test
    void setBookshelfRemovesOnlyWhenCurrentlyPresent() {
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, ITEM_ID)).thenReturn(false);

        assertThat(bookshelfService.setBookshelf(OWNER_ID, ITEM_ID, false)).isFalse();

        verify(bookshelfRepository, never()).deleteByOwnerUserIdAndReaderItemId(OWNER_ID, ITEM_ID);
        verify(readerItemService, never()).requireItem(OWNER_ID, ITEM_ID);
    }
}
