package com.omninest.modules.reader.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import java.io.InputStream;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

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

    private ReaderCoverExtractionService service;

    @BeforeEach
    void setUp() {
        service = new ReaderCoverExtractionService(new MediaProcessingLimitsProperties(), itemRepository, derivedAssetStorageService, syncEventService);
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
}
