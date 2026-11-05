package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FilePurgeState;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileNodeScanQueryRepository;
import com.omninest.modules.search.service.SearchableFileQuery;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
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
     * 查询当前用户仍可搜索的文件名称。
     *
     * @param ownerUserId 当前用户 ID
     * @param candidateIds Lucene 返回的候选文件 ID
     * @return 以文件 ID 为键的当前文件名称
     */
    @Override
    public Map<UUID, String> findCurrentNames(UUID ownerUserId, Collection<UUID> candidateIds) {
        return fileNodeRepository.findSearchablePersonalNodes(
                        ownerUserId,
                        candidateIds,
                        FilePurgeState.NONE,
                        SpaceType.PERSONAL,
                        DERIVED_SOURCE_TYPE
                ).stream()
                .collect(Collectors.toMap(FileNode::getId, FileNode::getName));
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

    @Override
    public Map<UUID, String> findCurrentSharedNames(Collection<UUID> candidateIds) {
        return fileNodeRepository.findSearchableSharedNodes(
                        candidateIds,
                        FilePurgeState.NONE,
                        SpaceType.SHARED,
                        DERIVED_SOURCE_TYPE
                ).stream()
                .collect(Collectors.toMap(FileNode::getId, FileNode::getName));
    }
}
