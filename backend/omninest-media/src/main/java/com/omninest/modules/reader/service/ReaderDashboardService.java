package com.omninest.modules.reader.service;

import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderDashboardDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderOverviewDto;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 阅读仪表盘服务：聚合概览、继续阅读、最近条目。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ReaderDashboardService {

    /** 仪表盘卡片条数上限。 */
    private static final int DASHBOARD_CARD_LIMIT = 12;

    private final ReaderItemService itemService;
    private final ReaderItemRepository itemRepository;
    private final ReaderProgressRepository progressRepository;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final SharedSpaceAccessQuery sharedSpaceAccessQuery;

    /**
     * 获取阅读仪表盘数据。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 仪表盘 DTO
     */
    public ReaderDashboardDto getDashboard(UUID ownerUserId) {
        SpaceType sharedType = sharedVisibility(ownerUserId);
        long totalItems = itemRepository.countVisibleItems(ownerUserId, sharedType);
        long inProgressCount = progressRepository.countVisibleInProgress(ownerUserId, sharedType);

        // 继续阅读只取前 12 条；概览计数使用独立 COUNT，不能停在 12。
        List<ReaderProgress> inProgressRows = progressRepository.findVisibleInProgress(
                ownerUserId, sharedType, PageRequest.of(0, DASHBOARD_CARD_LIMIT));
        List<ReaderItem> continueItems = loadOrderedItems(inProgressRows);
        Map<UUID, ReaderProgress> progressMap = inProgressRows.stream()
                .collect(Collectors.toMap(
                        ReaderProgress::getReaderItemId,
                        progress -> progress,
                        (first, second) -> first,
                        LinkedHashMap::new
                ));

        List<ReaderItemDto> continueReading = toDtos(ownerUserId, continueItems, progressMap);
        List<ReaderItemDto> recentItems = itemService.listItemsPage(
                ownerUserId, null, null, null, false, 0, DASHBOARD_CARD_LIMIT).getContent();

        ReaderOverviewDto overview = new ReaderOverviewDto((int) totalItems, (int) inProgressCount);
        return new ReaderDashboardDto(overview, continueReading, recentItems);
    }

    /**
     * 按进度行顺序回表取条目，已删除或不可见的条目直接丢弃。
     */
    private List<ReaderItem> loadOrderedItems(List<ReaderProgress> progressRows) {
        if (progressRows.isEmpty()) {
            return List.of();
        }
        Map<UUID, ReaderItem> itemsById = itemRepository
                .findAllById(progressRows.stream().map(ReaderProgress::getReaderItemId).toList())
                .stream()
                .collect(Collectors.toMap(ReaderItem::getId, item -> item));
        return progressRows.stream()
                .map(progress -> itemsById.get(progress.getReaderItemId()))
                .filter(Objects::nonNull)
                .toList();
    }

    /**
     * 批量补齐书架、空间类型与进度后转 DTO，避免逐条查询。
     */
    private List<ReaderItemDto> toDtos(
            UUID ownerUserId,
            List<ReaderItem> items,
            Map<UUID, ReaderProgress> progressMap
    ) {
        if (items.isEmpty()) {
            return List.of();
        }
        List<UUID> itemIds = items.stream().map(ReaderItem::getId).toList();
        Set<UUID> bookshelfItemIds = itemService.bookshelfItemIds(ownerUserId, itemIds);
        List<UUID> fileNodeIds = items.stream()
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
        return items.stream()
                .map(item -> itemService.toDto(
                        item,
                        bookshelfItemIds.contains(item.getId()),
                        spaceTypeMap,
                        progressMap
                ))
                .toList();
    }

    private SpaceType sharedVisibility(UUID ownerUserId) {
        return sharedSpaceAccessQuery.canBrowse(ownerUserId) ? SpaceType.SHARED : null;
    }
}
