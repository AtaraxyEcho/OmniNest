package com.omninest.modules.search.service;

import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.search.dto.SearchResultDto;
import com.omninest.modules.search.service.SearchableFileQuery.SearchableFileNode;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 文件搜索应用服务，将正文索引命中与数据库当前状态合并。
 *
 * <p>索引侧只回答「哪些内容对象命中、命中的是哪一段」，节点标识、文件名与可见性
 * 全部由数据库实时决定。因此重命名、移动目录、复制、软删除与回收站还原都不需要
 * 触碰索引：对象标识没变，它引用的节点变了也一样能搜到。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileSearchService {

    private static final int MAX_RESULTS = 50;
    private static final int CANDIDATE_MULTIPLIER = 3;
    private static final String SPACE_PERSONAL = "PERSONAL";
    private static final String SPACE_SHARED = "SHARED";
    /** 文件名命中没有正文摘要，给一个略高于纯正文命中的固定分，保证标题优先展示。 */
    private static final float TITLE_MATCH_SCORE = 3.0F;

    private final FileSearchIndexService fileSearchIndexService;
    private final SearchableFileQuery searchableFileQuery;
    private final SharedSpaceAccessQuery sharedSpaceAccessQuery;

    /**
     * 搜索当前用户个人空间与可见共享空间中的活动文件。
     *
     * @param ownerUserId 当前用户 ID
     * @param query 搜索关键词
     * @return 经数据库复核的搜索结果
     */
    public List<SearchResultDto> search(UUID ownerUserId, String query) {
        return search(ownerUserId, query, null);
    }

    /**
     * 按空间过滤搜索文件。
     *
     * <p>共享空间候选只有在用户具备共享空间浏览权限时才返回。</p>
     *
     * @param ownerUserId 当前用户 ID
     * @param query 搜索关键词
     * @param spaceType 空间类型（PERSONAL / SHARED / 空表示全部）
     * @return 经数据库复核的搜索结果
     */
    public List<SearchResultDto> search(UUID ownerUserId, String query, String spaceType) {
        if (query == null || query.isBlank()) {
            return List.of();
        }
        String normalizedSpace = normalizeSpaceType(spaceType);
        boolean includePersonal = normalizedSpace == null || SPACE_PERSONAL.equals(normalizedSpace);
        boolean includeShared = normalizedSpace == null || SPACE_SHARED.equals(normalizedSpace);
        if (includeShared && !sharedSpaceAccessQuery.canBrowse(ownerUserId)) {
            includeShared = false;
            if (!includePersonal) {
                return List.of();
            }
        }
        String indexFilter = includePersonal && includeShared
                ? null
                : (includeShared ? SPACE_SHARED : SPACE_PERSONAL);
        String trimmedQuery = query.trim();
        List<FileSearchIndexService.FileContentHit> hits = fileSearchIndexService.search(
                ownerUserId,
                trimmedQuery,
                MAX_RESULTS * CANDIDATE_MULTIPLIER,
                indexFilter
        );
        // 文件名以数据库为实时真值：重命名/移动后无需重建索引即可按新名字搜到。
        Map<UUID, String> titleMatches = searchableFileQuery.searchActiveFilesByName(
                ownerUserId,
                trimmedQuery,
                includePersonal,
                includeShared,
                MAX_RESULTS
        );
        if (hits.isEmpty() && titleMatches.isEmpty()) {
            return List.of();
        }
        Map<UUID, List<SearchableFileNode>> nodesByObject = groupByObjectId(hits, ownerUserId,
                includePersonal, includeShared);
        Map<UUID, SearchResultDto> results = new LinkedHashMap<>();
        for (FileSearchIndexService.FileContentHit hit : hits) {
            for (SearchableFileNode node : nodesByObject.getOrDefault(hit.fileObjectId(), List.of())) {
                if (results.size() >= MAX_RESULTS) {
                    break;
                }
                results.putIfAbsent(node.fileId(), new SearchResultDto(
                        node.fileId(),
                        node.name(),
                        hit.snippet(),
                        hit.score()
                ));
            }
        }
        for (Map.Entry<UUID, String> entry : titleMatches.entrySet()) {
            if (results.size() >= MAX_RESULTS) {
                break;
            }
            results.putIfAbsent(
                    entry.getKey(),
                    new SearchResultDto(entry.getKey(), entry.getValue(), null, TITLE_MATCH_SCORE)
            );
        }
        return List.copyOf(results.values());
    }

    /**
     * 按命中的内容对象批量解析当前节点。
     *
     * <p>一个对象可能被复制成多个节点（副本共享同一内容对象），每个副本都是独立结果；
     * 已删除或已换对象的历史命中在这里被过滤掉。</p>
     */
    private Map<UUID, List<SearchableFileNode>> groupByObjectId(
            List<FileSearchIndexService.FileContentHit> hits,
            UUID ownerUserId,
            boolean includePersonal,
            boolean includeShared
    ) {
        Map<UUID, List<SearchableFileNode>> nodesByObject = new LinkedHashMap<>();
        if (hits.isEmpty()) {
            return nodesByObject;
        }
        List<UUID> objectIds = new ArrayList<>(hits.size());
        hits.forEach(hit -> objectIds.add(hit.fileObjectId()));
        for (SearchableFileNode node : searchableFileQuery.findSearchableNodesByObjectIds(
                ownerUserId, objectIds, includePersonal, includeShared)) {
            nodesByObject.computeIfAbsent(node.fileObjectId(), key -> new ArrayList<>()).add(node);
        }
        return nodesByObject;
    }

    private String normalizeSpaceType(String spaceType) {
        if (spaceType == null || spaceType.isBlank()) {
            return null;
        }
        String normalized = spaceType.trim().toUpperCase(Locale.ROOT);
        if (!SPACE_PERSONAL.equals(normalized) && !SPACE_SHARED.equals(normalized)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "spaceType 仅支持 PERSONAL 或 SHARED");
        }
        return normalized;
    }
}
