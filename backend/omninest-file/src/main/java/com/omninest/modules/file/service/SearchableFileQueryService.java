package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileNodeScanQueryRepository;
import com.omninest.modules.search.service.SearchableFileQuery;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

/**
 * 使用文件元数据实现搜索候选的可见状态复核。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class SearchableFileQueryService implements SearchableFileQuery {
    private static final String DERIVED_SOURCE_TYPE = "DERIVED";

    private final FileNodeRepository fileNodeRepository;
    private final FileNodeScanQueryRepository fileNodeScanQueryRepository;

    /**
     * 按内容对象标识解析当前可搜索的文件节点。
     *
     * @param ownerUserId 当前用户 ID
     * @param fileObjectIds 正文命中的内容对象标识
     * @param includePersonal 是否包含个人空间
     * @param includeShared 是否包含共享空间
     * @return 当前可搜索的文件节点
     */
    @Override
    public Collection<SearchableFileNode> findSearchableNodesByObjectIds(
            UUID ownerUserId,
            Collection<UUID> fileObjectIds,
            boolean includePersonal,
            boolean includeShared
    ) {
        if (fileObjectIds == null || fileObjectIds.isEmpty()) {
            return List.of();
        }
        List<FileNode> nodes = new ArrayList<>();
        if (includePersonal) {
            nodes.addAll(fileNodeRepository.findSearchablePersonalNodesByObjectIds(
                    ownerUserId,
                    fileObjectIds,
                    FilePurgeState.NONE,
                    SpaceType.PERSONAL,
                    DERIVED_SOURCE_TYPE
            ));
        }
        if (includeShared) {
            nodes.addAll(fileNodeRepository.findSearchableSharedNodesByObjectIds(
                    fileObjectIds,
                    FilePurgeState.NONE,
                    SpaceType.SHARED,
                    DERIVED_SOURCE_TYPE
            ));
        }
        return nodes.stream()
                .map(node -> new SearchableFileNode(
                        node.getId(), node.getCurrentObjectId(), node.getName()))
                .toList();
    }

    @Override
    public Map<UUID, String> searchActiveFilesByName(
            UUID ownerUserId,
            String query,
            boolean includePersonal,
            boolean includeShared,
            int limit
    ) {
        if (query == null || query.isBlank() || limit <= 0) {
            return Map.of();
        }
        String escapedQuery = escapeLikeQuery(query.trim());
        PageRequest page = PageRequest.of(0, limit);
        Map<UUID, String> matches = new LinkedHashMap<>();
        if (includePersonal) {
            fileNodeScanQueryRepository.searchActivePersonalFilesByName(
                            ownerUserId,
                            escapedQuery,
                            FilePurgeState.NONE,
                            SpaceType.PERSONAL,
                            DERIVED_SOURCE_TYPE,
                            page)
                    .forEach(node -> matches.put(node.getId(), node.getName()));
        }
        if (includeShared) {
            fileNodeScanQueryRepository.searchActiveSharedFilesByName(
                            escapedQuery,
                            FilePurgeState.NONE,
                            SpaceType.SHARED,
                            DERIVED_SOURCE_TYPE,
                            page)
                    .forEach(node -> matches.putIfAbsent(node.getId(), node.getName()));
        }
        return matches;
    }

    private static String escapeLikeQuery(String query) {
        return query.replace("\\", "\\\\")
                .replace("%", "\\%")
                .replace("_", "\\_");
    }
}
