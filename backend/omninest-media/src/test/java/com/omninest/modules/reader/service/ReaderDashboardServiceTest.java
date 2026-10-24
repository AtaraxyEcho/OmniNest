package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderDashboardDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDto;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;

/**
 * 阅读仪表盘服务单元测试：验证"继续阅读"逻辑与有界查询。
 */
@ExtendWith(MockitoExtension.class)
class ReaderDashboardServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_IN_PROGRESS = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_OTHER = UUID.fromString("20000000-0000-0000-0000-000000000002");

    @Mock
    private ReaderItemService itemService;
    @Mock
    private ReaderItemRepository itemRepository;
    @Mock
    private ReaderProgressRepository progressRepository;
    @Mock
    private FileMetadataQueryService fileMetadataQueryService;
    @Mock
    private SharedSpaceAccessQuery sharedSpaceAccessQuery;

    @InjectMocks
    private ReaderDashboardService dashboardService;

    @BeforeEach
    void setUp() {
        lenient().when(sharedSpaceAccessQuery.canBrowse(OWNER_ID)).thenReturn(true);
        lenient().when(itemService.listItemsPage(
                        any(), any(), any(), any(), anyBoolean(), anyInt(), anyInt()))
                .thenReturn(emptyPage());
        lenient().when(itemService.bookshelfItemIds(any(), any())).thenReturn(Set.of());
    }

    @Test
    @DisplayName("继续阅读应包含阅读中的书籍，并使用有界 Top-N 查询")
    void should_include_in_progress_books_in_continue_reading() {
        ReaderItem inProgressItem = createItem(ITEM_IN_PROGRESS);
        ReaderProgress inProgress = createProgress(ITEM_IN_PROGRESS, new BigDecimal("0.5"), Instant.now());
        when(itemRepository.countVisibleItems(OWNER_ID, SpaceType.SHARED)).thenReturn(1L);
        when(progressRepository.countVisibleInProgress(OWNER_ID, SpaceType.SHARED)).thenReturn(1L);
        when(progressRepository.findVisibleInProgress(
                eq(OWNER_ID), eq(SpaceType.SHARED), any(Pageable.class)))
                .thenReturn(List.of(inProgress));
        when(itemRepository.findAllById(List.of(ITEM_IN_PROGRESS))).thenReturn(List.of(inProgressItem));
        when(itemService.toDto(eq(inProgressItem), eq(false), anyMap(), anyMap()))
                .thenReturn(createMockDto(ITEM_IN_PROGRESS));

        ReaderDashboardDto dashboard = dashboardService.getDashboard(OWNER_ID);

        assertThat(dashboard.continueReading()).hasSize(1);
        assertThat(dashboard.continueReading().get(0).id()).isEqualTo(ITEM_IN_PROGRESS);
        assertThat(dashboard.overview().totalItems()).isEqualTo(1);
        assertThat(dashboard.overview().continueCount()).isEqualTo(1);
        verify(progressRepository).findVisibleInProgress(
                OWNER_ID, SpaceType.SHARED, PageRequest.of(0, 12));
    }

    @Test
    @DisplayName("没有阅读中的进度行时继续阅读为空")
    void should_return_empty_continue_reading_without_in_progress_rows() {
        when(itemRepository.countVisibleItems(OWNER_ID, SpaceType.SHARED)).thenReturn(2L);
        when(progressRepository.countVisibleInProgress(OWNER_ID, SpaceType.SHARED)).thenReturn(0L);
        when(progressRepository.findVisibleInProgress(
                eq(OWNER_ID), eq(SpaceType.SHARED), any(Pageable.class)))
                .thenReturn(List.of());

        ReaderDashboardDto dashboard = dashboardService.getDashboard(OWNER_ID);

        assertThat(dashboard.continueReading()).isEmpty();
        assertThat(dashboard.overview().totalItems()).isEqualTo(2);
    }

    /**
     * 继续阅读按最近阅读时间排序。
     *
     * <p>上报进度只写 {@code reader_progress.updated_at}，不推进 {@code reader_items.updated_at}；
     * 仓储按进度更新时间倒序返回，服务必须保持该顺序。
     */
    @Test
    @DisplayName("继续阅读保持仓储返回的进度更新时间顺序")
    void should_keep_repository_progress_order() {
        ReaderItem recentlyReadItem = createItem(ITEM_IN_PROGRESS);
        ReaderItem staleItem = createItem(ITEM_OTHER);
        ReaderProgress recentlyRead = createProgress(
                ITEM_IN_PROGRESS, new BigDecimal("0.4"), Instant.parse("2026-09-09T00:00:00Z"));
        ReaderProgress stale = createProgress(
                ITEM_OTHER, new BigDecimal("0.6"), Instant.parse("2026-02-02T00:00:00Z"));
        when(progressRepository.findVisibleInProgress(
                eq(OWNER_ID), eq(SpaceType.SHARED), any(Pageable.class)))
                .thenReturn(List.of(recentlyRead, stale));
        when(itemRepository.findAllById(List.of(ITEM_IN_PROGRESS, ITEM_OTHER)))
                .thenReturn(List.of(staleItem, recentlyReadItem));
        when(itemService.toDto(eq(recentlyReadItem), eq(false), anyMap(), anyMap()))
                .thenReturn(createMockDto(ITEM_IN_PROGRESS));
        when(itemService.toDto(eq(staleItem), eq(false), anyMap(), anyMap()))
                .thenReturn(createMockDto(ITEM_OTHER));

        ReaderDashboardDto dashboard = dashboardService.getDashboard(OWNER_ID);

        assertThat(dashboard.continueReading())
                .extracting(ReaderItemDto::id)
                .containsExactly(ITEM_IN_PROGRESS, ITEM_OTHER);
    }

    @Test
    @DisplayName("共享空间关闭时仪表盘只查询个人条目")
    void should_exclude_shared_space_when_browse_denied() {
        when(sharedSpaceAccessQuery.canBrowse(OWNER_ID)).thenReturn(false);
        when(progressRepository.findVisibleInProgress(eq(OWNER_ID), isNull(), any(Pageable.class)))
                .thenReturn(List.of());

        dashboardService.getDashboard(OWNER_ID);

        verify(progressRepository).countVisibleInProgress(OWNER_ID, null);
        verify(progressRepository).findVisibleInProgress(eq(OWNER_ID), isNull(), any(Pageable.class));
        verify(itemRepository).countVisibleItems(OWNER_ID, null);
    }

    private Page<ReaderItemDto> emptyPage() {
        return new PageImpl<>(List.of(), PageRequest.of(0, 12), 0);
    }

    private ReaderItem createItem(UUID id) {
        ReaderItem item = new ReaderItem();
        item.setId(id);
        item.setOwnerUserId(OWNER_ID);
        item.setTitle("Test Book");
        item.setItemType("EPUB");
        item.setUpdatedAt(Instant.now());
        return item;
    }

    private ReaderProgress createProgress(UUID itemId, BigDecimal percent, Instant updatedAt) {
        ReaderProgress progress = new ReaderProgress();
        progress.setOwnerUserId(OWNER_ID);
        progress.setReaderItemId(itemId);
        progress.setProgressPercent(percent);
        progress.setUpdatedAt(updatedAt);
        return progress;
    }

    private ReaderItemDto createMockDto(UUID id) {
        return new ReaderItemDto(
                id, null, "EPUB", "TEXT", "Test Book", null, null, null, null,
                null, null, null, null, null, null, Instant.now(), Instant.now(), false, null,
                "PERSONAL", 0, "READY", null, null
        );
    }
}
