package com.omninest.modules.search.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.modules.search.dto.SearchResultDto;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 文件搜索应用服务，将 Lucene 候选结果与数据库当前状态合并。
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
     * <p>共享空间候选只有在用户具备共享空间浏览权限时才返回；单空间过滤时
     * 仍需复核节点状态，避免索引残留把已删除或已进入永久删除的文件带出来。</p>
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
        List<SearchResultDto> candidates = fileSearchIndexService.search(
                ownerUserId,
                query.trim(),
                MAX_RESULTS * CANDIDATE_MULTIPLIER,
                indexFilter
        );
        if (candidates.isEmpty()) {
            return List.of();
        }
        List<UUID> candidateIds = candidates.stream().map(SearchResultDto::fileId).toList();
        Map<UUID, String> currentNames = new LinkedHashMap<>();
        if (includePersonal) {
            currentNames.putAll(searchableFileQuery.findCurrentNames(ownerUserId, candidateIds));
        }
        if (includeShared) {
            currentNames.putAll(searchableFileQuery.findCurrentSharedNames(candidateIds));
        }
        Map<UUID, SearchResultDto> results = new LinkedHashMap<>();
        for (SearchResultDto candidate : candidates) {
            String currentName = currentNames.get(candidate.fileId());
            if (currentName == null) {
                continue;
            }
            SearchResultDto existing = results.get(candidate.fileId());
            if (existing == null || candidate.score() > existing.score()) {
                results.put(candidate.fileId(), new SearchResultDto(
                        candidate.fileId(),
                        currentName,
                        candidate.snippet(),
                        candidate.score()
                ));
            }
            if (results.size() >= MAX_RESULTS) {
                break;
            }
        }
        return List.copyOf(results.values());
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
