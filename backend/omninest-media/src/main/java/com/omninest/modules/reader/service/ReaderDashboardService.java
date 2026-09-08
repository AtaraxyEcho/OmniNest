package com.omninest.modules.reader.service;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.reader.domain.ReaderBookshelf;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderDashboardDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDto;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderOverviewDto;
import com.omninest.modules.reader.repository.ReaderBookshelfRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import java.math.BigDecimal;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
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

    private final ReaderItemService itemService;
    private final ReaderItemRepository itemRepository;
    private final ReaderProgressRepository progressRepository;
    private final ReaderBookshelfRepository bookshelfRepository;
    private final FileMetadataQueryService fileMetadataQueryService;

    /**
     * 获取阅读仪表盘数据。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 仪表盘 DTO
     */
    public ReaderDashboardDto getDashboard(UUID ownerUserId) {
        // 查询用户可见的所有条目（个人空间 + 共享空间）
        List<ReaderItem> allItems = itemRepository.findItemsVisibleToUser(ownerUserId, SpaceType.SHARED);
        int totalItems = allItems.size();

        List<UUID> allItemIds = allItems.stream().map(ReaderItem::getId).toList();

        // 批量查询所有进度记录（1 次查询替代 N 次）
        Map<UUID, ReaderProgress> progressMap = progressRepository
                .findByOwnerUserIdAndReaderItemIdIn(ownerUserId, allItemIds)
                .stream()
                .collect(Collectors.toMap(ReaderProgress::getReaderItemId, p -> p));

        // 批量查询所有书架记录（1 次查询替代 N 次）
        Set<UUID> bookshelfItemIds = bookshelfRepository
                .findByOwnerUserIdAndReaderItemIdIn(ownerUserId, allItemIds)
                .stream()
                .map(ReaderBookshelf::getReaderItemId)
                .collect(Collectors.toSet());

        // 批量查询文件节点空间类型（1 次查询替代 N 次）
        List<UUID> fileNodeIds = allItems.stream()
                .map(ReaderItem::getFileNodeId)
                .filter(Objects::nonNull)
                .distinct()
                .toList();
        Map<UUID, String> spaceTypeMap = fileMetadataQueryService.findAllByIds(fileNodeIds)
                .stream()
                .collect(Collectors.toMap(
                        FileDescriptor::id,
                        file -> file.spaceType().getValue()
                ));

        // 继续阅读：进度 > 0 且 < 100%，按 updatedAt 降序
        List<ReaderItemDto> continueReading = allItems.stream()
                .filter(item -> {
                    ReaderProgress progress = progressMap.get(item.getId());
                    if (progress == null) {
                        return false;
                    }
                    BigDecimal percent = progress.getProgressPercent();
                    return percent.compareTo(BigDecimal.ZERO) > 0 && percent.compareTo(BigDecimal.ONE) < 0;
                })
                .sorted(Comparator.comparing(ReaderItem::getUpdatedAt).reversed())
                .limit(12)
                .map(item -> toDto(ownerUserId, item, bookshelfItemIds, spaceTypeMap, progressMap))
                .toList();

        // 最近条目：按 updatedAt 降序取前 12
        List<ReaderItemDto> recentItems = allItems.stream()
                .limit(12)
                .map(item -> toDto(ownerUserId, item, bookshelfItemIds, spaceTypeMap, progressMap))
                .toList();

        ReaderOverviewDto overview = new ReaderOverviewDto(totalItems, continueReading.size());
        return new ReaderDashboardDto(overview, continueReading, recentItems);
    }

    /**
     * 实体转 DTO（使用预加载的书架集合、空间类型与进度映射，避免逐条查询）。
     */
    private ReaderItemDto toDto(
            UUID ownerUserId,
            ReaderItem item,
            Set<UUID> bookshelfItemIds,
            Map<UUID, String> spaceTypeMap,
            Map<UUID, ReaderProgress> progressMap
    ) {
        boolean onBookshelf = bookshelfItemIds.contains(item.getId());
        return itemService.toDto(item, onBookshelf, spaceTypeMap, progressMap);
    }
}
