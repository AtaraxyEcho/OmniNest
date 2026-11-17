package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.domain.ReaderReadingSession;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderReadingStatsDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderStatsOverviewDto;
import com.omninest.modules.reader.dto.ReaderDtos.RecordSessionRequest;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import com.omninest.modules.user.service.SystemInstanceConfigService;
import com.omninest.modules.reader.repository.ReaderReadingSessionRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.ZoneId;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Pageable;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

class ReaderStatsServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final ReaderReadingSessionRepository sessionRepository = mock(ReaderReadingSessionRepository.class);
    private final ReaderItemRepository itemRepository = mock(ReaderItemRepository.class);
    private final ReaderProgressRepository progressRepository = mock(ReaderProgressRepository.class);
    private final ReaderItemService itemService = mock(ReaderItemService.class);
    private final PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
    private final SystemInstanceConfigService systemInstanceConfigService = mock(SystemInstanceConfigService.class);
    private final SharedSpaceAccessQuery sharedSpaceAccessQuery = mock(SharedSpaceAccessQuery.class);
    private final FileMetadataQueryService fileMetadataQueryService = mock(FileMetadataQueryService.class);
    private final ReaderStatsService readerStatsService = new ReaderStatsService(
            sessionRepository, itemRepository, progressRepository, itemService,
            new TransactionTemplate(transactionManager), systemInstanceConfigService,
            sharedSpaceAccessQuery, fileMetadataQueryService);

    @BeforeEach
    void useSystemZone() {
        when(systemInstanceConfigService.timeZone()).thenReturn(ZoneId.systemDefault());
        lenient().when(sharedSpaceAccessQuery.canBrowse(OWNER_ID)).thenReturn(true);
    }

    @Test
    void recordSessionIgnoresConcurrentClientSessionDuplicate() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setTitle("测试书籍");
        item.setItemType("EPUB");
        when(itemService.requireItem(OWNER_ID, ITEM_ID)).thenReturn(item);
        when(sessionRepository.existsByOwnerUserIdAndClientSessionId(OWNER_ID, "session-1"))
                .thenReturn(false, true);
        when(sessionRepository.saveAndFlush(any(ReaderReadingSession.class)))
                .thenThrow(new DataIntegrityViolationException("duplicate client session"));

        RecordSessionRequest request = new RecordSessionRequest(
                " session-1 ",
                Instant.parse("2026-06-01T10:00:00Z"),
                Instant.parse("2026-06-01T10:05:00Z"),
                300
        );

        assertThatCode(() -> readerStatsService.recordSession(OWNER_ID, ITEM_ID, request)).doesNotThrowAnyException();
        verify(sessionRepository).saveAndFlush(any(ReaderReadingSession.class));
        ArgumentCaptor<TransactionDefinition> definition = ArgumentCaptor.forClass(TransactionDefinition.class);
        verify(transactionManager).getTransaction(definition.capture());
        assertThat(definition.getValue().getPropagationBehavior())
                .isEqualTo(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    @Test
    void recordSessionRethrowsNonDuplicateIntegrityViolation() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setTitle("测试书籍");
        item.setItemType("EPUB");
        when(itemService.requireItem(OWNER_ID, ITEM_ID)).thenReturn(item);
        when(sessionRepository.existsByOwnerUserIdAndClientSessionId(OWNER_ID, "session-1")).thenReturn(false);
        when(sessionRepository.saveAndFlush(any(ReaderReadingSession.class)))
                .thenThrow(new DataIntegrityViolationException("other constraint"));

        RecordSessionRequest request = new RecordSessionRequest(
                "session-1",
                Instant.parse("2026-06-01T10:00:00Z"),
                Instant.parse("2026-06-01T10:05:00Z"),
                300
        );

        assertThatThrownBy(() -> readerStatsService.recordSession(OWNER_ID, ITEM_ID, request))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void getStatsOverviewFillsDailyAxisAndCounts() {
        LocalDate today = LocalDate.now();
        when(sessionRepository.sumDailyMinutesSince(eq(OWNER_ID), any(Instant.class), any()))
                .thenReturn(List.of(dailyView(today, 25L), dailyView(today.minusDays(1), 40L)));
        ReaderItem inProgressItem = visibleItem(ITEM_ID, "测试书籍");
        ReaderProgress inProgress = progress(ITEM_ID, new BigDecimal("0.5"));
        when(progressRepository.countVisibleCompleted(OWNER_ID, SpaceType.SHARED)).thenReturn(1L);
        when(progressRepository.countVisibleInProgress(OWNER_ID, SpaceType.SHARED)).thenReturn(1L);
        when(itemRepository.countVisibleItems(OWNER_ID, SpaceType.SHARED)).thenReturn(2L);
        when(progressRepository.findVisibleInProgress(eq(OWNER_ID), eq(SpaceType.SHARED), any(Pageable.class)))
                .thenReturn(List.of(inProgress));
        when(itemRepository.findAllById(List.of(ITEM_ID))).thenReturn(List.of(inProgressItem));

        ReaderItemDto dto = new ReaderItemDto(
                ITEM_ID, null, "EPUB", "TEXT", "测试书籍", null, null, null, null,
                null, null, null, null, null, null, Instant.now(), Instant.now(), false, null,
                "PERSONAL", 0, "READY", null, null
        );
        when(itemService.toDto(eq(inProgressItem), eq(false), anyMap(), anyMap())).thenReturn(dto);

        ReaderStatsOverviewDto overview = readerStatsService.getStatsOverview(OWNER_ID, 14);

        assertThat(overview.dailyMinutes()).hasSize(14);
        assertThat(overview.dailyMinutes().get(overview.dailyMinutes().size() - 1).minutes()).isEqualTo(25);
        assertThat(overview.dailyMinutes().get(overview.dailyMinutes().size() - 2).minutes()).isEqualTo(40);
        assertThat(overview.completedCount()).isEqualTo(1L);
        assertThat(overview.inProgressCount()).isEqualTo(1L);
        assertThat(overview.totalItems()).isEqualTo(2L);
        assertThat(overview.inProgressItems()).hasSize(1);
        assertThat(overview.inProgressItems().get(0).id()).isEqualTo(ITEM_ID);
    }

    /**
     * 总藏书数、已完成数与在读列表必须取同一可见性判据：共享空间关闭后
     * 所有聚合都只统计个人条目，避免“已完成 + 在读”超过总数。
     */
    @Test
    void getStatsOverviewExcludesSharedSpaceWhenBrowseDenied() {
        when(sharedSpaceAccessQuery.canBrowse(OWNER_ID)).thenReturn(false);
        when(progressRepository.countVisibleCompleted(OWNER_ID, null)).thenReturn(1L);
        when(progressRepository.countVisibleInProgress(OWNER_ID, null)).thenReturn(0L);
        when(itemRepository.countVisibleItems(OWNER_ID, null)).thenReturn(1L);

        ReaderStatsOverviewDto overview = readerStatsService.getStatsOverview(OWNER_ID, 7);

        assertThat(overview.totalItems()).isEqualTo(1L);
        assertThat(overview.completedCount()).isEqualTo(1L);
        assertThat(overview.inProgressCount()).isZero();
        assertThat(overview.inProgressItems()).isEmpty();
        verify(progressRepository).findVisibleInProgress(eq(OWNER_ID), isNull(), any(Pageable.class));
    }

    @Test
    void getStatsOverviewClampsDaysToConfiguredBounds() {
        when(sessionRepository.sumDailyMinutesSince(eq(OWNER_ID), any(Instant.class), any()))
                .thenReturn(List.of());

        assertThat(readerStatsService.getStatsOverview(OWNER_ID, 999).dailyMinutes()).hasSize(30);
        assertThat(readerStatsService.getStatsOverview(OWNER_ID, 1).dailyMinutes()).hasSize(7);
    }

    @Test
    void getStatsAnchorsStreakOnTheLatestReadingDay() {
        // 清晨打开统计页时今天还没有会话：从今天起算会把连读几十天的用户显示成 0 天，
        // 而 totalBooksRead 也不能是藏书总数，否则"读完几本"永远虚高。
        LocalDate today = LocalDate.now();
        when(sessionRepository.distinctReadingDaysSince(eq(OWNER_ID), any(Instant.class), any()))
                .thenReturn(List.of(today.minusDays(1), today.minusDays(2), today.minusDays(3)));
        when(progressRepository.countVisibleCompleted(OWNER_ID, SpaceType.SHARED)).thenReturn(2L);

        ReaderReadingStatsDto stats = readerStatsService.getStats(OWNER_ID);

        assertThat(stats.currentStreak()).isEqualTo(3);
        assertThat(stats.totalBooksRead()).isEqualTo(2);
    }

    @Test
    void getStatsDropsStreakOnceTheChainIsBroken() {
        LocalDate today = LocalDate.now();
        when(sessionRepository.distinctReadingDaysSince(eq(OWNER_ID), any(Instant.class), any()))
                .thenReturn(List.of(today.minusDays(5), today.minusDays(6)));

        assertThat(readerStatsService.getStats(OWNER_ID).currentStreak()).isZero();
    }

    private ReaderItem visibleItem(UUID itemId, String title) {
        ReaderItem item = new ReaderItem();
        item.setId(itemId);
        item.setOwnerUserId(OWNER_ID);
        item.setTitle(title);
        item.setItemType("EPUB");
        return item;
    }

    private ReaderProgress progress(UUID readerItemId, BigDecimal percent) {
        ReaderProgress progress = new ReaderProgress();
        progress.setOwnerUserId(OWNER_ID);
        progress.setReaderItemId(readerItemId);
        progress.setProgressPercent(percent);
        progress.setUpdatedAt(Instant.now());
        return progress;
    }

    private ReaderReadingSessionRepository.DailyMinutesView dailyView(LocalDate day, long minutes) {
        return new ReaderReadingSessionRepository.DailyMinutesView() {
            @Override
            public LocalDate getDay() {
                return day;
            }

            @Override
            public long getMinutes() {
                return minutes;
            }
        };
    }
}
