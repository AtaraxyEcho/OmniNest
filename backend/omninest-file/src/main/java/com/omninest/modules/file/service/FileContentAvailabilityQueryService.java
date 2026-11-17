package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileContentRef;
import com.omninest.modules.file.repository.FileContentRefRepository;
import java.util.Collection;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 向业务模块提供文件内容可用性批量查询，避免业务模块直接依赖 File Repository。
 */
@Service
@RequiredArgsConstructor
public class FileContentAvailabilityQueryService {
    private final FileContentRefRepository fileContentRefRepository;

    /**
     * 批量查询文件节点的内容可用状态。
     *
     * @param fileNodeIds 文件节点标识
     * @return 文件节点标识到可用状态的映射
     */
    @Transactional(readOnly = true)
    public Map<UUID, String> findAvailabilityByFileNodeIds(Collection<UUID> fileNodeIds) {
        var distinctIds = fileNodeIds.stream().filter(Objects::nonNull).distinct().toList();
        if (distinctIds.isEmpty()) {
            return Map.of();
        }
        return fileContentRefRepository.findByFileNodeIdIn(distinctIds).stream()
                .collect(Collectors.toUnmodifiableMap(
                        FileContentRef::getFileNodeId,
                        FileContentRef::getAvailabilityStatus,
                        (left, right) -> left
                ));
    }
}
