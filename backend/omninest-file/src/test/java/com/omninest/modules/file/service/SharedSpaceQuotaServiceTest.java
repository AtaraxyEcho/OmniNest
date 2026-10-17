package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SharedSpaceUsage;
import com.omninest.modules.file.dto.SharedSpaceUsageDto;
import com.omninest.modules.file.repository.SharedSpaceUsageRepository;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 共享空间配额服务测试。
 *
 * @author OmniNest
 */
class SharedSpaceQuotaServiceTest {

    private final SharedSpaceUsageRepository usageRepository = mock(SharedSpaceUsageRepository.class);
    private final ConfigValueProvider configValueProvider = mock(ConfigValueProvider.class);

    private SharedSpaceQuotaService service;

    @BeforeEach
    void setUp() {
        service = new SharedSpaceQuotaService(usageRepository, configValueProvider);
    }

    // ── checkQuota ─────────────────────────────────────────────────────

    @Nested
    @DisplayName("checkQuota()")
    class CheckQuotaTests {

        @Test
        @DisplayName("未超限：不抛异常")
        void checkQuota_withinLimit_doesNotThrow() {
            SharedSpaceUsage usage = usage(5000L, 5);
            when(usageRepository.findFirstBy()).thenReturn(Optional.of(usage));
            stubConfig("10000");

            service.checkQuota(3000L);
        }

        @Test
        @DisplayName("刚好满：不抛异常")
        void checkQuota_exactlyAtLimit_doesNotThrow() {
            SharedSpaceUsage usage = usage(7000L, 5);
            when(usageRepository.findFirstBy()).thenReturn(Optional.of(usage));
            stubConfig("10000");

            service.checkQuota(3000L);
        }

        @Test
        @DisplayName("超限：抛出 FILE_QUOTA_EXCEEDED")
        void checkQuota_exceedsLimit_throws() {
            SharedSpaceUsage usage = usage(8000L, 5);
            when(usageRepository.findFirstBy()).thenReturn(Optional.of(usage));
            stubConfig("10000");

            assertThatThrownBy(() -> service.checkQuota(3000L))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FILE_QUOTA_EXCEEDED);
        }

        @Test
        @DisplayName("无配置时使用默认值 100GB")
        void checkQuota_noConfig_usesDefault() {
            SharedSpaceUsage usage = usage(50L * 1024 * 1024 * 1024, 100);
            when(usageRepository.findFirstBy()).thenReturn(Optional.of(usage));
            when(configValueProvider.findByKey("shared_space.max_bytes"))
                    .thenReturn(Optional.empty());

            // 50GB + 60GB = 110GB > 100GB default
            assertThatThrownBy(() -> service.checkQuota(60L * 1024 * 1024 * 1024))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FILE_QUOTA_EXCEEDED);
        }

        @Test
        @DisplayName("0 表示无限制且不读取用量记录")
        void checkQuota_zeroLimit_isUnlimited() {
            stubConfig("0");

            service.checkQuota(Long.MAX_VALUE);

            verify(usageRepository, times(0)).findFirstBy();
        }
    }

    // ── increaseUsage ──────────────────────────────────────────────────

    @Nested
    @DisplayName("increaseUsage()")
    class IncreaseUsageTests {

        @Test
        @DisplayName("正常增加：按容量上限守卫的单条原子更新")
        void increaseUsage_appliesGuardedAtomicUpdate() {
            SharedSpaceUsage usage = usage(5000L, 5);
            when(usageRepository.findFirstBy()).thenReturn(Optional.of(usage));
            stubConfig("10000");
            when(usageRepository.tryIncreaseUsage(
                    eq(usage.getId()), eq(1024L), eq(2L), eq(10000L), any(Instant.class)))
                    .thenReturn(1);

            service.increaseUsage(1024L, 2L);

            ArgumentCaptor<Instant> nowCaptor = ArgumentCaptor.captor();
            verify(usageRepository).tryIncreaseUsage(
                    eq(usage.getId()), eq(1024L), eq(2L), eq(10000L), nowCaptor.capture());
            assertThat(nowCaptor.getValue()).isNotNull();
        }

        @Test
        @DisplayName("未配置上限：用足够大的天花板代替无界比较，避免相加溢出")
        void increaseUsage_unlimitedConfigUsesCeiling() {
            SharedSpaceUsage usage = usage(5000L, 5);
            when(usageRepository.findFirstBy()).thenReturn(Optional.of(usage));
            stubConfig("0");
            when(usageRepository.tryIncreaseUsage(any(), anyLong(), anyLong(), anyLong(), any()))
                    .thenReturn(1);

            service.increaseUsage(1024L, 1L);

            verify(usageRepository).tryIncreaseUsage(
                    eq(usage.getId()), eq(1024L), eq(1L), eq(Long.MAX_VALUE / 4), any(Instant.class));
        }

        @Test
        @DisplayName("条件更新 0 行即容量不足，不再依赖读后写的乐观锁重试")
        void increaseUsage_rejectedByGuardThrowsQuotaExceeded() {
            SharedSpaceUsage usage = usage(9500L, 5);
            when(usageRepository.findFirstBy()).thenReturn(Optional.of(usage));
            stubConfig("10000");
            when(usageRepository.tryIncreaseUsage(any(), anyLong(), anyLong(), anyLong(), any()))
                    .thenReturn(0);

            assertThatThrownBy(() -> service.increaseUsage(1024L, 1L))
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.FILE_QUOTA_EXCEEDED);
        }

        @Test
        @DisplayName("零增量不触库")
        void increaseUsage_zeroDeltaIsNoop() {
            service.increaseUsage(0L, 0L);

            verifyNoInteractions(usageRepository);
        }
    }

    // ── decreaseUsage ──────────────────────────────────────────────────

    @Nested
    @DisplayName("decreaseUsage()")
    class DecreaseUsageTests {

        @Test
        @DisplayName("正常减少：按传入的字节与文件数原子扣减")
        void decreaseUsage_appliesAtomicDecrease() {
            SharedSpaceUsage usage = usage(5000L, 5);
            when(usageRepository.findFirstBy()).thenReturn(Optional.of(usage));

            service.decreaseUsage(1024L, 3L);

            verify(usageRepository).decreaseUsage(eq(usage.getId()), eq(1024L), eq(3L), any(Instant.class));
        }

        @Test
        @DisplayName("零增量不触库")
        void decreaseUsage_zeroDeltaIsNoop() {
            service.decreaseUsage(0L, 0L);

            verifyNoInteractions(usageRepository);
        }
    }

    // ── getUsageDto ────────────────────────────────────────────────────

    @Nested
    @DisplayName("getUsageDto()")
    class GetUsageDtoTests {

        @Test
        @DisplayName("返回正确的 DTO")
        void getUsageDto_returnsCorrectDto() {
            SharedSpaceUsage usage = usage(5000L, 10);
            when(usageRepository.findFirstBy()).thenReturn(Optional.of(usage));
            stubConfig("20000");

            SharedSpaceUsageDto dto = service.getUsageDto();

            assertThat(dto.usedBytes()).isEqualTo(5000L);
            assertThat(dto.maxBytes()).isEqualTo(20000L);
            assertThat(dto.fileCount()).isEqualTo(10L);
        }

        @Test
        @DisplayName("用量记录不存在时抛出 INTERNAL_ERROR")
        void getUsageDto_noRecord_throws() {
            when(usageRepository.findFirstBy()).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.getUsageDto())
                    .isInstanceOf(BusinessException.class)
                    .extracting(ex -> ((BusinessException) ex).errorCode())
                    .isEqualTo(ErrorCode.INTERNAL_ERROR);
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private SharedSpaceUsage usage(long usedBytes, long fileCount) {
        SharedSpaceUsage usage = new SharedSpaceUsage();
        usage.setId(UUID.randomUUID());
        usage.setUsedBytes(usedBytes);
        usage.setFileCount(fileCount);
        usage.setVersion(0);
        return usage;
    }

    private void stubConfig(String value) {
        when(configValueProvider.findByKey("shared_space.max_bytes"))
                .thenReturn(Optional.of(value));
    }
}
