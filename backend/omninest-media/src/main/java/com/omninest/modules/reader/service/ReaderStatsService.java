package com.omninest.modules.reader.service;

import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
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
import com.omninest.modules.user.service.SystemInstanceConfigService;
import com.omninest.modules.reader.repository.ReaderReadingSessionRepository;

import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.PageRequest;
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
    private final SystemInstanceConfigService systemInstanceConfigService;
    private final SharedSpaceAccessQuery sharedSpaceAccessQuery;
    private final FileMetadataQueryService fileMetadataQueryService;

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
        ZoneId zone = systemInstanceConfigService.timeZone();
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
                (int) progressRepository.countVisibleCompleted(ownerUserId, sharedVisibility(ownerUserId))
        );
    }

    /**
     * PostgreSQL 的 {@code AT TIME ZONE} 需要 IANA 名称；JVM 在 UTC 下可能返回
     * 仅用于偏移的 {@code "Z"}，直接传入会报错，统一归一为 {@code "UTC"}。
     */
    private String zoneDatabaseId(ZoneId zone) {
        String id = zone.getId();
        return "Z".equals(id) ? "UTC" : id;
    }

    /**
     * 计算连续阅读天数（从最近一次有记录的那天往回数）。
     *
     * <p>锚点必须是最近记录日而不是"今天"：清晨打开统计页时今天还没有满 10 秒的会话，
     * 从今天起算会让连续读了几十天的用户看到 0 天。
     */
    private int calculateStreak(UUID ownerUserId) {
        Instant ninetyDaysAgo = Instant.now().minusSeconds(90L * 24 * 3600);
        ZoneId zone = systemInstanceConfigService.timeZone();
        List<LocalDate> readingDays = sessionRepository.distinctReadingDaysSince(
                ownerUserId, ninetyDaysAgo, zoneDatabaseId(zone));
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
        ZoneId zone = systemInstanceConfigService.timeZone();
        LocalDate today = LocalDate.now(zone);
        Instant since = today.minusDays(safeDays - 1L).atStartOfDay(zone).toInstant();

        // 每日分钟数：先填零再累加聚合结果，保证连续日期轴
        Map<LocalDate, Long> minutesByDay = new LinkedHashMap<>();
        for (int i = safeDays - 1; i >= 0; i--) {
            minutesByDay.put(today.minusDays(i), 0L);
        }
        for (ReaderReadingSessionRepository.DailyMinutesView row :
                sessionRepository.sumDailyMinutesSince(ownerUserId, since, zoneDatabaseId(zone))) {
            minutesByDay.computeIfPresent(row.getDay(), (key, value) -> value + row.getMinutes());
        }
        List<ReaderDailyMinutesDto> dailyMinutes = minutesByDay.entrySet().stream()
                .map(entry -> new ReaderDailyMinutesDto(entry.getKey(), entry.getValue().intValue()))
                .toList();

        SpaceType sharedType = sharedVisibility(ownerUserId);
        long completedCount = progressRepository.countVisibleCompleted(ownerUserId, sharedType);
        long inProgressCount = progressRepository.countVisibleInProgress(ownerUserId, sharedType);
        long totalItems = itemRepository.countVisibleItems(ownerUserId, sharedType);

        // 在读列表只取前 12 条；三个计数各自走 COUNT，不能把全部条目加载进 JVM。
        List<ReaderProgress> inProgress = progressRepository.findVisibleInProgress(
                ownerUserId, sharedType, PageRequest.of(0, 12));
        Map<UUID, ReaderProgress> progressMap = inProgress.stream()
                .collect(Collectors.toMap(ReaderProgress::getReaderItemId, p -> p, (first, second) -> first));
        Map<UUID, ReaderItem> itemsById = itemRepository.findAllById(
                        inProgress.stream().map(ReaderProgress::getReaderItemId).toList())
                .stream()
                .collect(Collectors.toMap(ReaderItem::getId, item -> item));
        List<ReaderItem> inProgressItemList = inProgress.stream()
                .map(progress -> itemsById.get(progress.getReaderItemId()))
                .filter(Objects::nonNull)
                .toList();
        // 书架标记必须查库回填：写死 false 会让统计页"在读"列表上的加书架按钮
        // 全部显示成未加入，点一次就把已收藏的书重复加入书架。
        Set<UUID> bookshelfItemIds = itemService.bookshelfItemIds(
                ownerUserId, inProgressItemList.stream().map(ReaderItem::getId).toList());
        List<UUID> fileNodeIds = inProgressItemList.stream()
                .map(ReaderItem::getFileNodeId)
                .filter(Objects::nonNull)
                .distinct()
                .toList();
        Map<UUID, String> spaceTypeMap = fileNodeIds.isEmpty()
                ? Map.of()
                : fileMetadataQueryService.findAllByIds(fileNodeIds).stream()
                        .collect(Collectors.toMap(
                                FileDescriptor::id,
                                file -> file.spaceType().getValue()
                        ));
        List<ReaderItemDto> inProgressItems = inProgressItemList.stream()
                .map(item -> itemService.toDto(
                        item, bookshelfItemIds.contains(item.getId()), spaceTypeMap, progressMap))
                .toList();

        return new ReaderStatsOverviewDto(
                dailyMinutes,
                completedCount,
                inProgressCount,
                // 三个口径共用同一个可见性判据，否则读过的共享书会让"已完成 + 在读"超过总藏书数
                totalItems,
                inProgressItems
        );
    }

    private SpaceType sharedVisibility(UUID ownerUserId) {
        return sharedSpaceAccessQuery.canBrowse(ownerUserId) ? SpaceType.SHARED : null;
    }
}
