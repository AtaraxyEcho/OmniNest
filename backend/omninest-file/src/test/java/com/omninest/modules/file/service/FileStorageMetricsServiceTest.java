package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.repository.FileMetricsRepository;
import com.omninest.modules.file.repository.FileUserUsageProjection;
import com.omninest.modules.quota.QuotaStatus;
import com.omninest.modules.quota.port.StorageQuotaPolicy;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.function.Supplier;
import org.junit.jupiter.api.Test;

/**
 * 文件存储指标服务测试。
 *
 * @author OmniNest
 */
class FileStorageMetricsServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final FileMetricsRepository fileMetricsRepository = mock(FileMetricsRepository.class);
    private final UserAccountQuery userAccountQuery = mock(UserAccountQuery.class);
    private final StorageQuotaPolicy storageQuotaPolicy = mock(StorageQuotaPolicy.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class, invocation -> {
        if ("getOrLoad".equals(invocation.getMethod().getName())) {
            Supplier<?> loader = invocation.getArgument(2);
            return loader.get();
        }
        return null;
    });
    private final FileStorageMetricsService service = new FileStorageMetricsService(
            fileMetricsRepository,
            userAccountQuery,
            storageQuotaPolicy,
            readThroughCache
    );

    /**
     * 验证全局指标被组合成结构化 DTO。
     */
    @Test
    void systemMetricsReturnsStructuredResult() {
        when(fileMetricsRepository.countFileNodesByType("FILE")).thenReturn(12L);
        when(fileMetricsRepository.countFileNodesByType("FOLDER")).thenReturn(4L);
        when(fileMetricsRepository.countFileObjects()).thenReturn(10L);
        when(fileMetricsRepository.sumFileObjectSizeBytes()).thenReturn(4096L);

        var result = service.systemMetrics();

        assertThat(result.fileCount()).isEqualTo(12);
        assertThat(result.folderCount()).isEqualTo(4);
        assertThat(result.objectCount()).isEqualTo(10);
        assertThat(result.usedBytes()).isEqualTo(4096);
    }

    /**
     * 验证用户用量投影被转换为类型安全映射。
     */
    @Test
    void actualUsageByUserReturnsTypedMap() {
        FileUserUsageProjection row = mock(FileUserUsageProjection.class);
        when(row.getUserId()).thenReturn(USER_ID);
        when(row.getTotalBytes()).thenReturn(2048L);
        when(fileMetricsRepository.sumFileSizeForUsers(List.of(USER_ID))).thenReturn(List.of(row));

        assertThat(service.actualUsageByUsers(List.of(USER_ID))).containsEntry(USER_ID, 2048L);
    }

    @Test
    void userStorageStatsAggregatesQuotaAndFileTypes() {
        UserAccountSummary user = new UserAccountSummary(
                USER_ID,
                "owner",
                Set.of(),
                false,
                1024L * 1024L,
                4096L
        );
        when(userAccountQuery.findById(USER_ID)).thenReturn(Optional.of(user));
        when(fileMetricsRepository.countFoldersByOwnerUserIdAndSpaceType(USER_ID, SpaceType.PERSONAL))
                .thenReturn(1L);
        when(fileMetricsRepository.countFilesByOwnerUserIdAndSpaceType(USER_ID, SpaceType.PERSONAL))
                .thenReturn(2L);
        when(fileMetricsRepository.aggregateFileStatsByMimeTypeAndSpaceType(USER_ID, SpaceType.PERSONAL))
                .thenReturn(List.of(
                        new Object[]{"video/mp4", 1L, 2048L},
                        new Object[]{"application/pdf", 1L, 1024L}
                ));
        when(storageQuotaPolicy.resolveStatus(anyLong(), anyLong(), anyBoolean()))
                .thenReturn(QuotaStatus.NORMAL);

        var result = service.userStorageStats(USER_ID);

        assertThat(result.quotaBytes()).isEqualTo(1024L * 1024L);
        assertThat(result.usedBytes()).isEqualTo(4096L);
        assertThat(result.quotaStatus()).isEqualTo("NORMAL");
        assertThat(result.totalFiles()).isEqualTo(2);
        assertThat(result.totalFolders()).isEqualTo(1);
        assertThat(result.typeDistribution())
                .extracting("category")
                .containsExactlyInAnyOrder("视频", "文档", "历史版本与回收站");
        assertThat(result.typeDistribution())
                .filteredOn(stat -> "历史版本与回收站".equals(stat.category()))
                .singleElement()
                .satisfies(stat -> assertThat(stat.sizeBytes()).isEqualTo(1024L));
    }
}
