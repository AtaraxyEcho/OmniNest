package com.omninest.app.architecture;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.file.repository.FileMetricsRepository;
import com.omninest.modules.file.service.FileStorageMetricsService;
import com.omninest.modules.notification.service.NotificationService;
import com.omninest.modules.quota.port.AdminActorVerifier;
import com.omninest.modules.quota.service.RuntimeStorageQuotaPolicy;
import com.omninest.modules.quota.service.StorageQuotaReservationService;
import com.omninest.modules.quota.service.StorageQuotaService;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

/**
 * 配额服务与文件存储指标服务的 Spring 依赖装配测试。
 *
 * @author OmniNest
 */
class QuotaMetricsWiringTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withBean(ConfigValueProvider.class, () -> mock(ConfigValueProvider.class))
            .withBean(RuntimeConfigCache.class, () -> mock(RuntimeConfigCache.class))
            .withBean(UserAccountQuery.class, () -> mock(UserAccountQuery.class))
            .withBean(UserStorageCommand.class, () -> mock(UserStorageCommand.class))
            .withBean(AdminAuditRecorder.class, () -> mock(AdminAuditRecorder.class))
            .withBean(NotificationService.class, () -> mock(NotificationService.class))
            .withBean(FileMetricsRepository.class, () -> mock(FileMetricsRepository.class))
            .withBean(ReadThroughCache.class, () -> mock(ReadThroughCache.class))
            .withBean(StorageQuotaReservationService.class, () -> mock(StorageQuotaReservationService.class))
            .withBean(AdminActorVerifier.class, () -> mock(AdminActorVerifier.class))
            .withUserConfiguration(
                    RuntimeStorageQuotaPolicy.class,
                    StorageQuotaService.class,
                    FileStorageMetricsService.class
            );

    @Test
    void quotaAndFileMetricsBeansStartWithoutDependencyCycle() {
        contextRunner.run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context).hasSingleBean(StorageQuotaService.class);
            assertThat(context).hasSingleBean(FileStorageMetricsService.class);
        });
    }
}
