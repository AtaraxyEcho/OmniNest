package com.omninest.modules.reader.service;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPage;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateProgressRequest;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 阅读进度服务测试，验证进度写入的所有权和漫画锚点校验。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderProgressServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID PAGE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final Instant REPORTED_AT = Instant.parse("2026-10-08T10:00:00Z");

    @Mock
    private ReaderItemRepository itemRepository;
    @Mock
    private ReaderItemSourceRepository sourceRepository;
    @Mock
    private ReaderPageRepository pageRepository;
    @Mock
    private ReaderProgressRepository progressRepository;
    @Mock
    private MediaSyncEventService syncEventService;

    @InjectMocks
    private ReaderProgressService service;

    @Test
    void updateProgressRejectsItemNotOwnedByUser() {
        Mockito.when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.empty());

        Assertions.assertThatThrownBy(() -> service.updateProgress(OWNER_ID, ITEM_ID, request(null, null)))
                .isInstanceOf(BusinessException.class);

        Mockito.verifyNoInteractions(progressRepository);
    }

    @Test
    void updateProgressRejectsComicPageFromAnotherItem() {
        ReaderItem item = item();
        ReaderPage page = page(UUID.fromString("20000000-0000-0000-0000-000000000002"), SOURCE_ID);

        Mockito.when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        Mockito.when(pageRepository.findById(PAGE_ID)).thenReturn(Optional.of(page));

        Assertions.assertThatThrownBy(() -> service.updateProgress(OWNER_ID, ITEM_ID, request(PAGE_ID, SOURCE_ID)))
                .isInstanceOf(BusinessException.class);

        Mockito.verifyNoInteractions(progressRepository);
    }

    @Test
    void updateProgressRejectsComicSourceFromAnotherItem() {
        ReaderItem item = item();
        ReaderPage page = page(ITEM_ID, SOURCE_ID);
        ReaderItemSource source = source(UUID.fromString("20000000-0000-0000-0000-000000000003"));

        Mockito.when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        Mockito.when(pageRepository.findById(PAGE_ID)).thenReturn(Optional.of(page));
        Mockito.when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));

        Assertions.assertThatThrownBy(() -> service.updateProgress(OWNER_ID, ITEM_ID, request(PAGE_ID, SOURCE_ID)))
                .isInstanceOf(BusinessException.class);

        Mockito.verifyNoInteractions(progressRepository);
    }

    @Test
    void updateProgressRejectsUnsupportedReadingMode() {
        ReaderItem item = item();

        Mockito.when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));

        Assertions.assertThatThrownBy(() -> service.updateProgress(OWNER_ID, ITEM_ID, requestWithMode("comic")))
                .isInstanceOf(BusinessException.class);

        Mockito.verifyNoInteractions(progressRepository);
    }

    @Test
    void updateProgressRecordsSyncEventWhenWriteApplied() {
        ReaderItem item = item();
        Mockito.when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        stubUpsert(1);

        service.updateProgress(OWNER_ID, ITEM_ID, requestWithMode("scroll", null, null));

        Mockito.verify(syncEventService)
                .record(Mockito.eq(OWNER_ID), Mockito.any(), Mockito.any(), Mockito.any(),
                        Mockito.any(), Mockito.any(), Mockito.any());
    }

    @Test
    void updateProgressSkipsSyncEventWhenReportIsStalerThanStored() {
        ReaderItem item = item();
        Mockito.when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        // 围栏在 SQL 的 WHERE 上：0 行受影响即表示本次上报被更新的记录拒绝。
        stubUpsert(0);

        service.updateProgress(OWNER_ID, ITEM_ID, requestWithMode("scroll", null, null));

        Mockito.verifyNoInteractions(syncEventService);
    }

    @Test
    void updateProgressUsesServerTimeWhenClientStampMissing() {
        ReaderItem item = item();
        Instant before = Instant.now();
        Mockito.when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        stubUpsert(1);

        service.updateProgress(OWNER_ID, ITEM_ID, requestWithoutClientStamp());

        ArgumentCaptor<Instant> reportedAt = ArgumentCaptor.forClass(Instant.class);
        Mockito.verify(progressRepository)
                .upsertProgress(Mockito.any(), Mockito.any(), Mockito.anyLong(), Mockito.any(), Mockito.any(),
                        Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any(),
                        Mockito.any(), Mockito.any(), Mockito.any(), reportedAt.capture());
        Assertions.assertThat(reportedAt.getValue()).isNotNull().isAfterOrEqualTo(before);
    }

    private void stubUpsert(int applied) {
        Mockito.when(progressRepository.upsertProgress(
                Mockito.any(), Mockito.any(), Mockito.anyLong(), Mockito.any(), Mockito.any(),
                Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any(),
                Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any())).thenReturn(applied);
    }

    private ReaderItem item() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setContentKind("COMIC");
        return item;
    }

    private ReaderPage page(UUID itemId, UUID sourceId) {
        ReaderPage page = new ReaderPage();
        page.setId(PAGE_ID);
        page.setReaderItemId(itemId);
        page.setSourceId(sourceId);
        return page;
    }

    private ReaderItemSource source(UUID itemId) {
        ReaderItemSource source = new ReaderItemSource();
        source.setId(SOURCE_ID);
        source.setReaderItemId(itemId);
        return source;
    }

    private UpdateProgressRequest request(UUID pageId, UUID sourceId) {
        return requestWithMode("scroll", pageId, sourceId);
    }

    private UpdateProgressRequest requestWithMode(String readingMode) {
        return requestWithMode(readingMode, null, null);
    }

    private UpdateProgressRequest requestWithMode(String readingMode, UUID pageId, UUID sourceId) {
        return requestWithReport(readingMode, pageId, sourceId, REPORTED_AT);
    }

    private UpdateProgressRequest requestWithoutClientStamp() {
        return requestWithReport("scroll", null, null, null);
    }

    private UpdateProgressRequest requestWithReport(
            String readingMode, UUID pageId, UUID sourceId, Instant clientUpdatedAt) {
        return new UpdateProgressRequest(
                0,
                BigDecimal.valueOf(0.5),
                readingMode,
                "",
                pageId,
                1,
                "fingerprint",
                sourceId,
                3,
                "volume-1/chapter-1",
                1,
                0.25,
                clientUpdatedAt);
    }
}
