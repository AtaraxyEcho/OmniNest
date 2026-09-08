package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderDashboardDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDto;
import com.omninest.modules.reader.repository.ReaderBookshelfRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 阅读仪表盘服务单元测试：验证"继续阅读"逻辑。
 */
@ExtendWith(MockitoExtension.class)
class ReaderDashboardServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_IN_PROGRESS = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_COMPLETED = UUID.fromString("20000000-0000-0000-0000-000000000002");

    @Mock
    private ReaderItemService itemService;
    @Mock
    private ReaderItemRepository itemRepository;
    @Mock
    private ReaderProgressRepository progressRepository;
    @Mock
    private ReaderBookshelfRepository bookshelfRepository;
    @Mock
    private FileMetadataQueryService fileMetadataQueryService;

    @InjectMocks
    private ReaderDashboardService dashboardService;

    @Test
    @DisplayName("继续阅读应包含阅读中的书籍（progress > 0 且 < 1）")
    void should_include_in_progress_books_in_continue_reading() {
        // Given: 阅读中和已完成两本书
        ReaderItem inProgressItem = createItem(ITEM_IN_PROGRESS, Instant.now());
        ReaderItem completedItem = createItem(ITEM_COMPLETED, Instant.now().minusSeconds(3600));

        when(itemRepository.findItemsVisibleToUser(OWNER_ID, SpaceType.SHARED))
            .thenReturn(List.of(inProgressItem, completedItem));

        ReaderProgress inProgress = createProgress(ITEM_IN_PROGRESS, new BigDecimal("0.5"));
        ReaderProgress completed = createProgress(ITEM_COMPLETED, BigDecimal.ONE);

        List<UUID> itemIds = List.of(ITEM_IN_PROGRESS, ITEM_COMPLETED);
        when(progressRepository.findByOwnerUserIdAndReaderItemIdIn(eq(OWNER_ID), anyList()))
            .thenReturn(List.of(inProgress, completed));
        when(bookshelfRepository.findByOwnerUserIdAndReaderItemIdIn(eq(OWNER_ID), anyList()))
            .thenReturn(Collections.emptyList());
        when(fileMetadataQueryService.findAllByIds(anyList()))
            .thenReturn(Collections.emptyList());
        when(itemService.toDto(eq(inProgressItem), eq(false), anyMap(), anyMap()))
            .thenReturn(createMockDto(ITEM_IN_PROGRESS));
        when(itemService.toDto(eq(completedItem), eq(false), anyMap(), anyMap()))
            .thenReturn(createMockDto(ITEM_COMPLETED));

        // When: 获取仪表盘数据
        ReaderDashboardDto dashboard = dashboardService.getDashboard(OWNER_ID);

        // Then: 继续阅读应只包含阅读中的书籍
        assertThat(dashboard.continueReading()).hasSize(1);
        assertThat(dashboard.continueReading().get(0).id()).isEqualTo(ITEM_IN_PROGRESS);
    }

    @Test
    @DisplayName("继续阅读不应包含已完成的书籍（progress = 1.0）")
    void should_not_include_completed_books_in_continue_reading() {
        // Given: 只有一本已完成的书籍
        ReaderItem completedItem = createItem(ITEM_COMPLETED, Instant.now());

        when(itemRepository.findItemsVisibleToUser(OWNER_ID, SpaceType.SHARED))
            .thenReturn(List.of(completedItem));

        ReaderProgress completed = createProgress(ITEM_COMPLETED, BigDecimal.ONE);

        when(progressRepository.findByOwnerUserIdAndReaderItemIdIn(eq(OWNER_ID), anyList()))
            .thenReturn(List.of(completed));
        when(bookshelfRepository.findByOwnerUserIdAndReaderItemIdIn(eq(OWNER_ID), anyList()))
            .thenReturn(Collections.emptyList());
        when(fileMetadataQueryService.findAllByIds(anyList()))
            .thenReturn(Collections.emptyList());
        when(itemService.toDto(eq(completedItem), eq(false), anyMap(), anyMap()))
            .thenReturn(createMockDto(ITEM_COMPLETED));

        // When: 获取仪表盘数据
        ReaderDashboardDto dashboard = dashboardService.getDashboard(OWNER_ID);

        // Then: 继续阅读应为空
        assertThat(dashboard.continueReading()).isEmpty();
    }

    @Test
    @DisplayName("继续阅读不应包含未开始的书籍（progress = 0）")
    void should_not_include_not_started_books_in_continue_reading() {
        // Given: 只有一本未开始的书籍
        ReaderItem notStartedItem = createItem(ITEM_IN_PROGRESS, Instant.now());

        when(itemRepository.findItemsVisibleToUser(OWNER_ID, SpaceType.SHARED))
            .thenReturn(List.of(notStartedItem));

        ReaderProgress notStarted = createProgress(ITEM_IN_PROGRESS, BigDecimal.ZERO);

        when(progressRepository.findByOwnerUserIdAndReaderItemIdIn(eq(OWNER_ID), anyList()))
            .thenReturn(List.of(notStarted));
        when(bookshelfRepository.findByOwnerUserIdAndReaderItemIdIn(eq(OWNER_ID), anyList()))
            .thenReturn(Collections.emptyList());
        when(fileMetadataQueryService.findAllByIds(anyList()))
            .thenReturn(Collections.emptyList());
        when(itemService.toDto(eq(notStartedItem), eq(false), anyMap(), anyMap()))
            .thenReturn(createMockDto(ITEM_IN_PROGRESS));

        // When: 获取仪表盘数据
        ReaderDashboardDto dashboard = dashboardService.getDashboard(OWNER_ID);

        // Then: 继续阅读应为空
        assertThat(dashboard.continueReading()).isEmpty();
    }

    @Test
    @DisplayName("继续阅读不应包含没有进度记录的书籍")
    void should_not_include_books_without_progress() {
        // Given: 一本没有进度记录的书籍
        ReaderItem noProgressItem = createItem(ITEM_IN_PROGRESS, Instant.now());

        when(itemRepository.findItemsVisibleToUser(OWNER_ID, SpaceType.SHARED))
            .thenReturn(List.of(noProgressItem));

        // 没有进度记录
        when(progressRepository.findByOwnerUserIdAndReaderItemIdIn(eq(OWNER_ID), anyList()))
            .thenReturn(Collections.emptyList());
        when(bookshelfRepository.findByOwnerUserIdAndReaderItemIdIn(eq(OWNER_ID), anyList()))
            .thenReturn(Collections.emptyList());
        when(fileMetadataQueryService.findAllByIds(anyList()))
            .thenReturn(Collections.emptyList());
        when(itemService.toDto(eq(noProgressItem), eq(false), anyMap(), anyMap()))
            .thenReturn(createMockDto(ITEM_IN_PROGRESS));

        // When: 获取仪表盘数据
        ReaderDashboardDto dashboard = dashboardService.getDashboard(OWNER_ID);

        // Then: 继续阅读应为空
        assertThat(dashboard.continueReading()).isEmpty();
    }

    private ReaderItem createItem(UUID id, Instant updatedAt) {
        ReaderItem item = new ReaderItem();
        item.setId(id);
        item.setOwnerUserId(OWNER_ID);
        item.setTitle("Test Book");
        item.setItemType("EPUB");
        item.setUpdatedAt(updatedAt);
        return item;
    }

    private ReaderProgress createProgress(UUID itemId, BigDecimal percent) {
        ReaderProgress progress = new ReaderProgress();
        progress.setOwnerUserId(OWNER_ID);
        progress.setReaderItemId(itemId);
        progress.setProgressPercent(percent);
        return progress;
    }

    private ReaderItemDto createMockDto(UUID id) {
        return new ReaderItemDto(
            id, "EPUB", "TEXT", "Test Book", null, null, null, null,
            null, null, Instant.now(), false, null, "PERSONAL", 0,
            "READY", null, null
        );
    }
}
