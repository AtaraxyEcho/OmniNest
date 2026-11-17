package com.omninest.modules.file.service;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileStorageStatsDto;
import com.omninest.modules.file.dto.FileTypeStatsDto;
import com.omninest.modules.file.repository.FileMetricsRepository;
import com.omninest.modules.file.repository.FileUserUsageProjection;
import com.omninest.modules.quota.port.StorageMetricsQuery;
import com.omninest.modules.quota.port.StorageMetricsSnapshot;
import com.omninest.modules.quota.port.StorageQuotaPolicy;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件存储指标服务，向其他模块提供结构化聚合结果。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileStorageMetricsService implements StorageMetricsQuery {

    private final FileMetricsRepository fileMetricsRepository;
    private final UserAccountQuery userAccountQuery;
    private final StorageQuotaPolicy storageQuotaPolicy;
    private final ReadThroughCache readThroughCache;

    /**
     * 查询全局文件存储指标。
     *
     * @return 全局存储指标
     */
    @Transactional(readOnly = true)
    @Override
    public StorageMetricsSnapshot systemMetrics() {
        return new StorageMetricsSnapshot(
                fileMetricsRepository.countFileNodesByType(NodeType.FILE.getValue()),
                fileMetricsRepository.countFileNodesByType(NodeType.FOLDER.getValue()),
                fileMetricsRepository.countFileObjects(),
                fileMetricsRepository.sumFileObjectSizeBytes()
        );
    }

    /**
     * 查询指定用户在个人空间的实际存储用量。
     *
     * @param userIds 用户标识集合
     * @return 以用户 ID 为键的实际用量
     */
    @Transactional(readOnly = true)
    @Override
    public Map<UUID, Long> actualUsageByUsers(Collection<UUID> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, Long> usage = new LinkedHashMap<>();
        for (FileUserUsageProjection row : fileMetricsRepository.sumFileSizeForUsers(userIds)) {
            usage.put(row.getUserId(), row.getTotalBytes());
        }
        return Map.copyOf(usage);
    }

    /**
     * 查询用户个人空间的存储统计。
     *
     * @param ownerUserId 所有者用户 ID
     * @return 用户存储统计
     */
    @Transactional(readOnly = true)
    public FileStorageStatsDto userStorageStats(UUID ownerUserId) {
        String cacheKey = "omninest:storage:stats:" + ownerUserId;
        return readThroughCache.getOrLoad(
                cacheKey,
                Duration.ofMinutes(2),
                () -> loadUserStorageStats(ownerUserId),
                FileStorageStatsDto.class
        );
    }

    private FileStorageStatsDto loadUserStorageStats(UUID ownerUserId) {
        UserAccountSummary user = userAccountQuery.findById(ownerUserId).orElse(null);
        long totalFolders = fileMetricsRepository.countFoldersByOwnerUserIdAndSpaceType(
                ownerUserId,
                SpaceType.PERSONAL
        );
        long totalFiles = fileMetricsRepository.countFilesByOwnerUserIdAndSpaceType(
                ownerUserId,
                SpaceType.PERSONAL
        );
        List<Object[]> rows = fileMetricsRepository.aggregateFileStatsByMimeTypeAndSpaceType(
                ownerUserId,
                SpaceType.PERSONAL
        );
        Map<String, long[]> typeStats = new LinkedHashMap<>();
        for (Object[] row : rows) {
            String mimeType = row[0] != null ? row[0].toString() : null;
            long count = ((Number) row[1]).longValue();
            long size = ((Number) row[2]).longValue();
            String category = resolveCategory(mimeType);
            long[] totals = typeStats.computeIfAbsent(category, key -> new long[2]);
            totals[0] += count;
            totals[1] += size;
        }
        List<FileTypeStatsDto> distribution = typeStats.entrySet()
                .stream()
                .map(entry -> new FileTypeStatsDto(
                        entry.getKey(),
                        entry.getValue()[0],
                        entry.getValue()[1]
                ))
                .toList();
        long activeBytes = typeStats.values().stream().mapToLong(value -> value[1]).sum();
        // 文件页的已用量必须与配额账本一致：账本还包含回收站、历史版本与背景/编辑派生
        // 原片，而按 MIME 聚合只覆盖活跃的个人文件。差额单列一类，避免进度条失真。
        long usedBytes = user == null ? activeBytes : user.usedBytes();
        if (usedBytes > activeBytes) {
            List<FileTypeStatsDto> withHistory = new ArrayList<>(distribution);
            withHistory.add(new FileTypeStatsDto("历史版本与回收站", 0L, usedBytes - activeBytes));
            distribution = List.copyOf(withHistory);
        }
        boolean superAdmin = user != null && user.superAdmin();
        long quotaBytes = superAdmin ? -1L : (user == null ? 0L : user.quotaBytes());
        String quotaStatus = storageQuotaPolicy.resolveStatus(
                usedBytes,
                quotaBytes,
                superAdmin
        ).getValue();
        return new FileStorageStatsDto(
                (int) totalFiles,
                (int) totalFolders,
                usedBytes,
                quotaBytes,
                quotaStatus,
                distribution
        );
    }

    private String resolveCategory(String mimeType) {
        String value = mimeType == null ? "" : mimeType.toLowerCase(Locale.ROOT);
        if (value.startsWith("image/")) {
            return "图片";
        }
        if (value.startsWith("video/")) {
            return "视频";
        }
        if (value.startsWith("audio/")) {
            return "音频";
        }
        if (value.contains("pdf") || value.contains("document") || value.contains("text")) {
            return "文档";
        }
        if (value.contains("zip") || value.contains("rar") || value.contains("7z")) {
            return "压缩包";
        }
        return "其他";
    }
}
