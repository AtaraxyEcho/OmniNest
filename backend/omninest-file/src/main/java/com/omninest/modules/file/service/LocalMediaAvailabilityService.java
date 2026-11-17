package com.omninest.modules.file.service;

import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileContentRef;
import com.omninest.modules.file.dto.LocalMediaExistingRef;
import com.omninest.modules.file.repository.FileContentRefRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 本地媒体引用的扫描观察和缺失确认边界。
 */
@Service
@RequiredArgsConstructor
public class LocalMediaAvailabilityService {
    private static final List<String> UNAVAILABLE_STATUSES = List.of("MISSING_PENDING", "MISSING", "BLOCKED");

    private final FileContentRefRepository contentRefRepository;

    /** 批量读取已登记引用，用于候选去重和变化识别。 */
    @Transactional(readOnly = true)
    public Map<String, LocalMediaExistingRef> findExisting(
            UUID ownerUserId,
            UUID storageLocationId,
            Collection<String> relativePaths
    ) {
        if (relativePaths.isEmpty()) {
            return Map.of();
        }
        return contentRefRepository
                .findByOwnerUserIdAndStorageLocationIdAndRelativePathIn(
                        ownerUserId,
                        storageLocationId,
                        relativePaths
                )
                .stream()
                .map(this::toDto)
                .collect(Collectors.toUnmodifiableMap(LocalMediaExistingRef::relativePath, Function.identity()));
    }

    /** 标记本次发现中确实存在的已登记引用。 */
    @Transactional(rollbackFor = Exception.class)
    public int observe(
            UUID ownerUserId,
            UUID storageLocationId,
            UUID scanRunId,
            Collection<String> relativePaths
    ) {
        if (relativePaths.isEmpty()) {
            return 0;
        }
        return contentRefRepository.markObservedInScan(
                ownerUserId,
                storageLocationId,
                scanRunId,
                Instant.now(),
                relativePaths
        );
    }

    /**
     * 仅在来源完整成功遍历后推进缺失状态。
     */
    @Transactional(rollbackFor = Exception.class)
    public int finishSuccessfulScan(
            UUID ownerUserId,
            UUID storageLocationId,
            String sourceRelativeRoot,
            UUID scanRunId,
            int requiredConfirmations,
            Duration gracePeriod
    ) {
        // 前缀是真实目录名，不是模式：库里存在 S01_E01 这类目录名时，未转义的 _ 会当成
        // 单字符通配、% 当成任意串，把兄弟目录的引用一起标成缺失。下面四个消费方都声明
        // escape '\'，与此处口径配对（含 countUnavailableInSubtree）。
        String rawPrefix = ".".equals(sourceRelativeRoot) ? "" : sourceRelativeRoot + "/";
        String prefix = LikePatterns.escapeSpecials(rawPrefix);
        contentRefRepository.advanceMissingPending(ownerUserId, storageLocationId, prefix, scanRunId);
        contentRefRepository.confirmMissing(
                ownerUserId,
                storageLocationId,
                prefix,
                requiredConfirmations,
                Instant.now().minus(gracePeriod)
        );
        contentRefRepository.markMissingPending(
                ownerUserId,
                storageLocationId,
                prefix,
                scanRunId,
                Instant.now()
        );
        return Math.toIntExact(contentRefRepository
                .countUnavailableInSubtree(
                        ownerUserId,
                        storageLocationId,
                        prefix,
                        UNAVAILABLE_STATUSES
                ));
    }

    private LocalMediaExistingRef toDto(FileContentRef reference) {
        return new LocalMediaExistingRef(
                reference.getFileNodeId(),
                reference.getRelativePath(),
                reference.getProviderEtag(),
                reference.getAvailabilityStatus()
        );
    }
}
