package com.omninest.modules.search.service;

import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.search.dto.SearchResultDto;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 文件搜索应用服务，按数据库当前文件名实时匹配活动文件。
 *
 * <p>文件正文索引已下线。文件名与可见性以 PostgreSQL 为唯一事实来源，因此重命名、
 * 移动目录、复制、软删除与回收站还原都不需要重建索引，也不会让搜索结果过期。</p>
 */
@Service
@RequiredArgsConstructor
public class FileSearchService {

    private static final int MAX_RESULTS = 50;
    private static final String SPACE_PERSONAL = "PERSONAL";
    private static final String SPACE_SHARED = "SHARED";
    private static final double TITLE_MATCH_SCORE = 3.0F;

    private final SearchableFileQuery searchableFileQuery;
    private final SharedSpaceAccessQuery sharedSpaceAccessQuery;

    /**
     * 搜索当前用户个人空间与可见共享空间中的活动文件。
     *
     * @param ownerUserId 当前用户 ID
     * @param query 搜索关键词
     * @return 文件名命中的文件
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
     * @return 文件名命中的文件
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
        Map<UUID, String> titleMatches = searchableFileQuery.searchActiveFilesByName(
                ownerUserId,
                query.trim(),
                includePersonal,
                includeShared,
                MAX_RESULTS
        );
        List<SearchResultDto> results = new ArrayList<>();
        for (Map.Entry<UUID, String> entry : titleMatches.entrySet()) {
            if (results.size() >= MAX_RESULTS) {
                break;
            }
            results.add(new SearchResultDto(entry.getKey(), entry.getValue(), null, TITLE_MATCH_SCORE));
        }
        return List.copyOf(results);
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
