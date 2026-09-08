package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.domain.ReaderReadingSession;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderStatsOverviewDto;
import com.omninest.modules.reader.dto.ReaderDtos.RecordSessionRequest;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import com.omninest.modules.reader.repository.ReaderReadingSessionRepository;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

class ReaderStatsServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final ReaderReadingSessionRepository sessionRepository = mock(ReaderReadingSessionRepository.class);
    private final ReaderItemRepository itemRepository = mock(ReaderItemRepository.class);
    private final ReaderProgressRepository progressRepository = mock(ReaderProgressRepository.class);
    private final ReaderItemService itemService = mock(ReaderItemService.class);
    private final ReaderStatsService readerStatsService =
            new ReaderStatsService(sessionRepository, itemRepository, progressRepository, itemService);

    @Test
    void recordSessionIgnoresConcurrentClientSessionDuplicate() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setTitle("测试书籍");
        item.setItemType("EPUB");
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
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
    }

    @Test
    void recordSessionRethrowsNonDuplicateIntegrityViolation() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setTitle("测试书籍");
        item.setItemType("EPUB");
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
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
        when(itemRepository.countByOwnerUserId(OWNER_ID)).thenReturn(2L);
        LocalDate today = LocalDate.now();
        when(sessionRepository.sumDailyMinutesSince(eq(OWNER_ID), any(Instant.class), any()))
                .thenReturn(List.of(dailyView(today, 25L), dailyView(today.minusDays(1), 40L)));
        when(progressRepository.countByOwnerUserIdAndProgressPercentGreaterThanEqual(OWNER_ID, BigDecimal.ONE))
                .thenReturn(1L);
        ReaderProgress inProgress = new ReaderProgress();
        inProgress.setOwnerUserId(OWNER_ID);
        inProgress.setReaderItemId(ITEM_ID);
        inProgress.setProgressPercent(new BigDecimal("0.5"));
        inProgress.setUpdatedAt(Instant.now());
        when(progressRepository.findByOwnerUserIdAndProgressPercentGreaterThanAndProgressPercentLessThan(
                OWNER_ID, BigDecimal.ZERO, BigDecimal.ONE)).thenReturn(List.of(inProgress));

        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setTitle("测试书籍");
        item.setItemType("EPUB");
        when(itemRepository.findAllById(any())).thenReturn(List.of(item));
        ReaderItemDto dto = new ReaderItemDto(
                ITEM_ID, "EPUB", "TEXT", "测试书籍", null, null, null, null,
                null, null, Instant.now(), Instant.now(), false, null, "PERSONAL", 0, "READY", null, null
        );
        when(itemService.toDto(eq(item), eq(false), isNull(), anyMap())).thenReturn(dto);

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

    @Test
    void getStatsOverviewClampsDaysToConfiguredBounds() {
        when(itemRepository.countByOwnerUserId(OWNER_ID)).thenReturn(0L);
        when(sessionRepository.sumDailyMinutesSince(eq(OWNER_ID), any(Instant.class), any()))
                .thenReturn(List.of());
        when(progressRepository.countByOwnerUserIdAndProgressPercentGreaterThanEqual(OWNER_ID, BigDecimal.ONE))
                .thenReturn(0L);
        when(progressRepository.findByOwnerUserIdAndProgressPercentGreaterThanAndProgressPercentLessThan(
                OWNER_ID, BigDecimal.ZERO, BigDecimal.ONE)).thenReturn(List.of());

        assertThat(readerStatsService.getStatsOverview(OWNER_ID, 999).dailyMinutes()).hasSize(30);
        assertThat(readerStatsService.getStatsOverview(OWNER_ID, 1).dailyMinutes()).hasSize(7);
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
