package com.omninest.modules.reader.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import java.io.InputStream;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 阅读条目自动封面持久化测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderCoverExtractionServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID COVER_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    @Mock
    private ReaderItemRepository itemRepository;
    @Mock
    private DerivedAssetStorageService derivedAssetStorageService;
    @Mock
    private MediaSyncEventService syncEventService;
    @Mock
    private PlatformTransactionManager transactionManager;

    private ReaderCoverExtractionService service;

    @BeforeEach
    void setUp() {
        service = new ReaderCoverExtractionService(new MediaProcessingLimitsProperties(), itemRepository,
                derivedAssetStorageService, syncEventService, transactionManager);
        service.initTransactionTemplate();
    }

    @Test
    void storesDetectedCoverWhenItemHasNoCover() {
        ReaderItem item = item();
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(derivedAssetStorageService.store(
                eq(OWNER_ID),
                eq("READER_ITEM"),
                eq(ITEM_ID),
                eq("COVER"),
                eq("cover_" + ITEM_ID + ".png"),
                eq("image/png"),
                any(InputStream.class)
        )).thenReturn(COVER_ID);

        boolean stored = service.storeIfAbsent(ITEM_ID, new ReaderCoverDraft(pngBytes(), "image/png", "cover.png"));

        assertThat(stored).isTrue();
        assertThat(item.getCoverFileId()).isEqualTo(COVER_ID);
        verify(itemRepository).saveAndFlush(item);
    }

    @Test
    void preservesExistingManualCover() {
        ReaderItem item = item();
        item.setCoverFileId(COVER_ID);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));

        boolean stored = service.storeIfAbsent(ITEM_ID, new ReaderCoverDraft(pngBytes(), "image/png", "cover.png"));

        assertThat(stored).isFalse();
        verify(derivedAssetStorageService, never()).store(
                any(), any(), any(), any(), any(), any(), any(InputStream.class));
    }

    @Test
    void overwriteReplacesCoverAndDeletesPreviousNode() {
        // 重新解析会换封面格式：派生存储按逻辑路径原地复用同一个 FileNode 时不会新增节点，
        // 换了扩展名就多出第二个节点，而旧节点从此没有任何清理任务会再枚举它。
        UUID previousCoverId = UUID.fromString("40000000-0000-0000-0000-000000000001");
        ReaderItem item = item();
        item.setCoverFileId(previousCoverId);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(derivedAssetStorageService.store(
                any(), any(), any(), any(), any(), any(), any(InputStream.class)
        )).thenReturn(COVER_ID);
        when(itemRepository.findByCoverFileIdIn(List.of(previousCoverId)))
                .thenReturn(List.of(item));

        boolean stored = service.store(ITEM_ID, new ReaderCoverDraft(jpegBytes(), "image/jpeg", "cover.jpg"), true);

        assertThat(stored).isTrue();
        assertThat(item.getCoverFileId()).isEqualTo(COVER_ID);
        verify(derivedAssetStorageService).deleteDerivedFileNode(previousCoverId);
    }

    @Test
    void keepsReplacedCoverWhileAnotherItemReferencesIt() {
        // 导入去重后两本条目共用一份派生封面：只删自己那条引用，另一本会永久破图。
        UUID previousCoverId = UUID.fromString("40000000-0000-0000-0000-000000000002");
        ReaderItem item = item();
        item.setCoverFileId(previousCoverId);
        ReaderItem sibling = new ReaderItem();
        sibling.setId(UUID.fromString("20000000-0000-0000-0000-000000000009"));
        sibling.setOwnerUserId(OWNER_ID);
        sibling.setCoverFileId(previousCoverId);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(derivedAssetStorageService.store(
                any(), any(), any(), any(), any(), any(), any(InputStream.class)
        )).thenReturn(COVER_ID);
        when(itemRepository.findByCoverFileIdIn(List.of(previousCoverId)))
                .thenReturn(List.of(item, sibling));

        assertThat(service.store(ITEM_ID, new ReaderCoverDraft(jpegBytes(), "image/jpeg", "cover.jpg"), true)).isTrue();

        verify(derivedAssetStorageService, never()).deleteDerivedFileNode(any());
    }

    @Test
    void doesNotDeleteCoverWhenStoreReusesSameNode() {
        UUID sameCoverId = UUID.fromString("40000000-0000-0000-0000-000000000003");
        ReaderItem item = item();
        item.setCoverFileId(sameCoverId);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(derivedAssetStorageService.store(
                any(), any(), any(), any(), any(), any(), any(InputStream.class)
        )).thenReturn(sameCoverId);

        assertThat(service.store(ITEM_ID, new ReaderCoverDraft(jpegBytes(), "image/jpeg", "cover.jpg"), true)).isTrue();

        verify(derivedAssetStorageService, never()).deleteDerivedFileNode(any());
        verify(itemRepository, never()).findByCoverFileIdIn(any());
    }

    @Test
    void discardsStoreResultWhenCoverChangedDuringUpload() {
        // 上传期间别的写入改掉了条目指向：本次产物必须回收，不能覆盖已经生效的封面。
        UUID concurrentCoverId = UUID.fromString("40000000-0000-0000-0000-000000000004");
        ReaderItem before = item();
        ReaderItem after = item();
        after.setCoverFileId(concurrentCoverId);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(before), Optional.of(after));
        when(derivedAssetStorageService.store(
                any(), any(), any(), any(), any(), any(), any(InputStream.class)
        )).thenReturn(COVER_ID);

        assertThatThrownBy(() -> service.store(
                ITEM_ID, new ReaderCoverDraft(jpegBytes(), "image/jpeg", "cover.jpg"), true))
                .isInstanceOf(BusinessException.class);

        verify(derivedAssetStorageService).deleteOwned(OWNER_ID, COVER_ID);
        assertThat(after.getCoverFileId()).isEqualTo(concurrentCoverId);
    }

    @Test
    void deletesReplacedCoverOnlyAfterCommit() {
        UUID previousCoverId = UUID.fromString("40000000-0000-0000-0000-000000000005");
        ReaderItem item = item();
        item.setCoverFileId(previousCoverId);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(derivedAssetStorageService.store(
                any(), any(), any(), any(), any(), any(), any(InputStream.class)
        )).thenReturn(COVER_ID);
        when(itemRepository.findByCoverFileIdIn(List.of(previousCoverId)))
                .thenReturn(List.of(item));

        TransactionSynchronizationManager.initSynchronization();
        try {
            assertThat(service.store(ITEM_ID, new ReaderCoverDraft(jpegBytes(), "image/jpeg", "cover.jpg"), true))
                    .isTrue();
            // 落库事务还没提交，条目仍可能回滚到旧封面：提交前删对象会留下指向空对象的节点。
            verify(derivedAssetStorageService, never()).deleteDerivedFileNode(any());
            TransactionSynchronizationManager.getSynchronizations()
                    .forEach(TransactionSynchronization::afterCommit);
            verify(derivedAssetStorageService).deleteDerivedFileNode(previousCoverId);
        } finally {
            TransactionSynchronizationManager.clearSynchronization();
        }
    }

    private ReaderItem item() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setTitle("测试条目");
        item.setItemType("EPUB");
        item.setContentKind("TEXT");
        return item;
    }

    private byte[] pngBytes() {
        return new byte[]{
                (byte) 0x89, 0x50, 0x4E, 0x47,
                0x0D, 0x0A, 0x1A, 0x0A,
                0, 0, 0, 0
        };
    }

    private byte[] jpegBytes() {
        return new byte[]{(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0};
    }
}
