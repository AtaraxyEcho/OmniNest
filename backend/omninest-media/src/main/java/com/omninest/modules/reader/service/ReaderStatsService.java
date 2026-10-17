package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.domain.ReaderReadingSession;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderDailyMinutesDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderReadingStatsDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderStatsOverviewDto;
import com.omninest.modules.reader.dto.ReaderDtos.RecordSessionRequest;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import com.omninest.modules.reader.repository.ReaderReadingSessionRepository;

import java.math.BigDecimal;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 阅读统计服务：记录阅读会话并计算统计数据。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderStatsService {

    private final ReaderReadingSessionRepository sessionRepository;
    private final ReaderItemRepository itemRepository;
    private final ReaderProgressRepository progressRepository;
    private final ReaderItemService itemService;
    private final TransactionTemplate transactionTemplate;

    /**
     * 记录一次阅读会话。
     *
     * @param ownerUserId  所有者用户 ID
     * @param readerItemId 阅读条目 ID
     * @param request      会话记录请求
     */
    public void recordSession(UUID ownerUserId, UUID readerItemId, RecordSessionRequest request) {
        if (request == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "会话记录请求参数不能为空");
        }
        if (request.durationSeconds() <= 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "会话时长必须大于 0");
        }
        itemService.requireItem(ownerUserId, readerItemId);

        String clientSessionId = normalizeClientSessionId(request.clientSessionId());
        if (clientSessionId != null
                && sessionRepository.existsByOwnerUserIdAndClientSessionId(ownerUserId, clientSessionId)) {
            log.debug("忽略重复阅读会话: userId={}, itemId={}, clientSessionId={}", ownerUserId, readerItemId, clientSessionId);
            return;
        }

        ReaderReadingSession session = new ReaderReadingSession();
        session.setOwnerUserId(ownerUserId);
        session.setReaderItemId(readerItemId);
        session.setClientSessionId(clientSessionId);
        session.setStartedAt(request.startedAt() != null ? request.startedAt() : Instant.now());
        session.setEndedAt(request.endedAt());
        session.setDurationSeconds(request.durationSeconds());
        try {
            saveInNewTransaction(session);
        } catch (DataIntegrityViolationException ex) {
            if (clientSessionId != null
                    && sessionRepository.existsByOwnerUserIdAndClientSessionId(ownerUserId, clientSessionId)) {
                log.debug("忽略并发重复阅读会话: userId={}, itemId={}, clientSessionId={}",
                        ownerUserId, readerItemId, clientSessionId);
                return;
            }
            throw ex;
        }
        log.debug("记录阅读会话: userId={}, itemId={}, duration={}s", ownerUserId, readerItemId, request.durationSeconds());
    }

    /**
     * 在独立新事务中写入阅读会话。
     *
     * <p>与书架、书签、批注、笔记同一写法：唯一键冲突会把所在 PostgreSQL 事务标为
     * aborted，冲突后还要在同一上下文里查一次是否重复，外层带事务时会直接抛
     * "current transaction is aborted"。
     */
    private void saveInNewTransaction(ReaderReadingSession session) {
        TransactionTemplate template = new TransactionTemplate(
                transactionTemplate.getTransactionManager());
        template.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        template.execute(status -> sessionRepository.saveAndFlush(session));
    }

    private String normalizeClientSessionId(String clientSessionId) {
        if (clientSessionId == null) {
            return null;
        }
        String trimmed = clientSessionId.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    /**
     * 获取用户的阅读统计数据。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 阅读统计 DTO
     */
    @Transactional(readOnly = true)
    public ReaderReadingStatsDto getStats(UUID ownerUserId) {
        // 使用服务器本地时区（自托管场景下即用户时区）
        ZoneId zone = ZoneId.systemDefault();
        // 今日起始时间
        Instant todayStart = LocalDate.now(zone).atStartOfDay(zone).toInstant();
        // 本周起始时间（周一）
        Instant weekStart = LocalDate.now(zone)
                .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                .atStartOfDay(zone)
                .toInstant();

        long totalSecondsToday = sessionRepository.sumDurationSecondsSince(ownerUserId, todayStart);
        long totalSecondsThisWeek = sessionRepository.sumDurationSecondsSince(ownerUserId, weekStart);

        // 计算连续阅读天数
        int currentStreak = calculateStreak(ownerUserId);

        return new ReaderReadingStatsDto(
                (int) (totalSecondsToday / 60),
                (int) (totalSecondsThisWeek / 60),
                currentStreak,
                // "已读数"指读到完成的条目，不是藏书总数
                (int) visibleProgress(ownerUserId).stream()
                        .filter(progress -> progress.getProgressPercent() != null
                                && progress.getProgressPercent().compareTo(BigDecimal.ONE) >= 0)
                        .count()
        );
    }

    /**
     * 统计母集：当前用户可见（个人 + 共享空间）且源文件未进回收站的条目，按 ID 索引。
     *
     * <p>进度行按用户存、条目可见性按文件节点判，两边不取同一个母集时：读过的共享书会让
     * "已完成 + 在读" 超过只按个人条目统计的总藏书数，进回收站的书还留在在读列表里。
     */
    private Map<UUID, ReaderItem> visibleItemsById(UUID ownerUserId) {
        return itemRepository.findItemsVisibleToUser(ownerUserId, SpaceType.SHARED).stream()
                .collect(Collectors.toMap(ReaderItem::getId, item -> item, (first, second) -> first));
    }

    /**
     * 只保留可见条目上的进度行。
     */
    private List<ReaderProgress> visibleProgress(UUID ownerUserId) {
        List<UUID> visibleItemIds = List.copyOf(visibleItemsById(ownerUserId).keySet());
        if (visibleItemIds.isEmpty()) {
            return List.of();
        }
        return progressRepository.findByOwnerUserIdAndReaderItemIdIn(ownerUserId, visibleItemIds);
    }

    /**
     * 计算连续阅读天数（从最近一次有记录的那天往回数）。
     *
     * <p>锚点必须是最近记录日而不是"今天"：清晨打开统计页时今天还没有满 10 秒的会话，
     * 从今天起算会让连续读了几十天的用户看到 0 天。
     */
    private int calculateStreak(UUID ownerUserId) {
        Instant ninetyDaysAgo = Instant.now().minusSeconds(90L * 24 * 3600);
        // 计算服务器本地时区的 UTC 偏移量（如 "+08:00"）
        ZoneId zone = ZoneId.systemDefault();
        String utcOffset = zone.getRules().getOffset(Instant.now()).getId();
        List<LocalDate> readingDays = sessionRepository.distinctReadingDaysSince(ownerUserId, ninetyDaysAgo, utcOffset);
        if (readingDays.isEmpty()) {
            return 0;
        }
        LocalDate today = LocalDate.now(zone);
        LocalDate latestDay = readingDays.getFirst();
        if (!latestDay.equals(today) && !latestDay.equals(today.minusDays(1))) {
            return 0;
        }
        int streak = 0;
        LocalDate expected = latestDay;
        for (LocalDate day : readingDays) {
            if (day.equals(expected)) {
                streak++;
                expected = expected.minusDays(1);
            } else if (day.isBefore(expected)) {
                break;
            }
        }
        return streak;
    }

    /**
     * 获取阅读统计概览：最近 N 天每日分钟数、完成/在读计数与在读列表。
     *
     * @param ownerUserId 所有者用户 ID
     * @param days        统计天数，夹紧到 [7, 30]
     * @return 统计概览 DTO
     */
    @Transactional(readOnly = true)
    public ReaderStatsOverviewDto getStatsOverview(UUID ownerUserId, int days) {
        int safeDays = Math.max(7, Math.min(days, 30));
        ZoneId zone = ZoneId.systemDefault();
        String utcOffset = zone.getRules().getOffset(Instant.now()).getId();
        LocalDate today = LocalDate.now(zone);
        Instant since = today.minusDays(safeDays - 1L).atStartOfDay(zone).toInstant();

        // 每日分钟数：先填零再累加聚合结果，保证连续日期轴
        Map<LocalDate, Long> minutesByDay = new LinkedHashMap<>();
        for (int i = safeDays - 1; i >= 0; i--) {
            minutesByDay.put(today.minusDays(i), 0L);
        }
        for (ReaderReadingSessionRepository.DailyMinutesView row :
                sessionRepository.sumDailyMinutesSince(ownerUserId, since, utcOffset)) {
            minutesByDay.computeIfPresent(row.getDay(), (key, value) -> value + row.getMinutes());
        }
        List<ReaderDailyMinutesDto> dailyMinutes = minutesByDay.entrySet().stream()
                .map(entry -> new ReaderDailyMinutesDto(entry.getKey(), entry.getValue().intValue()))
                .toList();

        Map<UUID, ReaderItem> visibleItems = visibleItemsById(ownerUserId);
        List<ReaderProgress> visibleProgressRows = visibleItems.isEmpty()
                ? List.of()
                : progressRepository.findByOwnerUserIdAndReaderItemIdIn(
                        ownerUserId, List.copyOf(visibleItems.keySet()));
        long completedCount = visibleProgressRows.stream()
                .filter(progress -> progress.getProgressPercent() != null
                        && progress.getProgressPercent().compareTo(BigDecimal.ONE) >= 0)
                .count();
        List<ReaderProgress> inProgress = visibleProgressRows.stream()
                .filter(progress -> progress.getProgressPercent() != null
                        && progress.getProgressPercent().compareTo(BigDecimal.ZERO) > 0
                        && progress.getProgressPercent().compareTo(BigDecimal.ONE) < 0)
                .sorted(Comparator.comparing(
                        ReaderProgress::getUpdatedAt, Comparator.nullsLast(Comparator.naturalOrder())).reversed())
                .toList();
        Map<UUID, ReaderProgress> progressMap = inProgress.stream()
                .collect(Collectors.toMap(ReaderProgress::getReaderItemId, p -> p, (first, second) -> first));
        List<ReaderItemDto> inProgressItems = inProgress.stream()
                .map(progress -> visibleItems.get(progress.getReaderItemId()))
                .filter(Objects::nonNull)
                .limit(12)
                .map(item -> itemService.toDto(item, false, null, progressMap))
                .toList();

        return new ReaderStatsOverviewDto(
                dailyMinutes,
                completedCount,
                inProgress.size(),
                // 三个口径共用同一个母集，否则读过的共享书会让"已完成 + 在读"超过总藏书数
                visibleItems.size(),
                inProgressItems
        );
    }
}
