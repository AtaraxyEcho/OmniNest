package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.security.Permissions;
import com.omninest.common.security.Roles;
import com.omninest.modules.configcenter.dto.ConfigEntryDto;
import com.omninest.modules.configcenter.service.ConfigCenterService;
import com.omninest.modules.quota.port.StorageMetricsQuery;
import com.omninest.modules.quota.port.StorageMetricsSnapshot;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.repository.AdminAnalyticsRepository;
import com.omninest.modules.user.repository.AuditLogAdminRepository;
import com.omninest.modules.user.repository.TaskRecordAdminRepository;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.port.ExternalStorageAdministration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Sort;

/**
 * 管理控制台聚合服务单元测试。
 *
 * @author OmniNest
 */
class AdminConsoleServiceTest {
    private final AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
    private final AuthRoleRepository authRoleRepository = mock(AuthRoleRepository.class);
    private final ConfigCenterService configCenterService = mock(ConfigCenterService.class);
    private final TaskRecordAdminRepository taskRecordRepository = mock(TaskRecordAdminRepository.class);
    private final ExternalStorageAdministration externalStorageAdministration =
            mock(ExternalStorageAdministration.class);
    private final AuditLogAdminRepository auditLogRepository = mock(AuditLogAdminRepository.class);
    private final StorageMetricsQuery storageMetricsQuery = mock(StorageMetricsQuery.class);
    private final AdminAnalyticsRepository analyticsRepository = mock(AdminAnalyticsRepository.class);
    private final StorageQuotaService storageQuotaService = mock(StorageQuotaService.class);
    private final AdminConsoleService service = new AdminConsoleService(
            authUserRepository,
            authRoleRepository,
            configCenterService,
            taskRecordRepository,
            externalStorageAdministration,
            auditLogRepository,
            storageMetricsQuery,
            analyticsRepository,
            storageQuotaService
    );

    @Test
    void summaryAggregatesUsersRolesConfigsTasksAndStorage() {
        AuthRole superAdminRole = role(Roles.SUPER_ADMIN, Permissions.SYSTEM_USER_MANAGE);
        AuthRole adminRole = role(Roles.ADMIN, Permissions.SYSTEM_USER_READ, Permissions.SYSTEM_CONFIG_READ);
        AuthRole memberRole = role(Roles.MEMBER, Permissions.FILE_READ);
        when(authUserRepository.count()).thenReturn(3L);
        when(authUserRepository.countByStatus("ACTIVE")).thenReturn(2L);
        when(authUserRepository.countByStatus("DISABLED")).thenReturn(1L);
        when(authUserRepository.countUsersByEnabledRole()).thenReturn(List.of(
                new Object[]{Roles.SUPER_ADMIN, 1L},
                new Object[]{Roles.ADMIN, 1L},
                new Object[]{Roles.MEMBER, 1L}
        ));
        when(authRoleRepository.findAllWithPermissions(Sort.by(Sort.Direction.ASC, "code")))
                .thenReturn(List.of(adminRole, memberRole, superAdminRole));
        when(configCenterService.list()).thenReturn(List.of(
                new ConfigEntryDto("rate-limit.default-limit", "120", "NUMBER", "security", "HOT", Instant.now(), null),
                new ConfigEntryDto(
                        "storage.minio.endpoint",
                        "http://localhost:9000",
                        "STRING",
                        "storage",
                        "RESTART_REQUIRED",
                        Instant.now(),
                        null
                )
        ));
        when(taskRecordRepository.countByStatus("QUEUED")).thenReturn(3L);
        when(taskRecordRepository.countByStatus("RUNNING")).thenReturn(1L);
        when(taskRecordRepository.countByStatus("COMPLETED")).thenReturn(8L);
        when(taskRecordRepository.countByStatus("FAILED")).thenReturn(1L);
        when(taskRecordRepository.countByStatus("CANCELLED")).thenReturn(2L);
        when(taskRecordRepository.countByStatus("DLQ")).thenReturn(1L);
        when(storageMetricsQuery.systemMetrics())
                .thenReturn(new StorageMetricsSnapshot(12, 4, 10, 4096));
        when(externalStorageAdministration.countAccounts()).thenReturn(2L);

        var summary = service.summary();

        assertThat(summary.users().total()).isEqualTo(3);
        assertThat(summary.users().active()).isEqualTo(2);
        assertThat(summary.users().disabled()).isEqualTo(1);
        assertThat(summary.users().roleCounts()).containsEntry(Roles.SUPER_ADMIN, 1L);
        assertThat(summary.roles()).extracting("code").containsExactly(Roles.ADMIN, Roles.MEMBER, Roles.SUPER_ADMIN);
        assertThat(summary.roles().get(0).permissionCount()).isEqualTo(2);
        assertThat(summary.configs().total()).isEqualTo(2);
        assertThat(summary.configs().hot()).isEqualTo(1);
        assertThat(summary.configs().restartRequired()).isEqualTo(1);
        assertThat(summary.tasks().total()).isEqualTo(16);
        assertThat(summary.tasks().failed()).isEqualTo(1);
        assertThat(summary.tasks().dlq()).isEqualTo(1);
        assertThat(summary.storage().fileCount()).isEqualTo(12);
        assertThat(summary.storage().folderCount()).isEqualTo(4);
        assertThat(summary.storage().objectCount()).isEqualTo(10);
        assertThat(summary.storage().usedBytes()).isEqualTo(4096);
        assertThat(summary.storage().externalAccountCount()).isEqualTo(2);
        assertThat(summary.health()).anySatisfy(item -> {
            assertThat(item.name()).isEqualTo("任务队列");
            assertThat(item.status()).isEqualTo("WARN");
        });
    }

    private AuthRole role(String code, String... permissionCodes) {
        AuthRole role = new AuthRole();
        role.setId(UUID.randomUUID());
        role.setCode(code);
        role.setName(code);
        for (String permissionCode : permissionCodes) {
            AuthPermission permission = new AuthPermission();
            permission.setId(UUID.randomUUID());
            permission.setCode(permissionCode);
            permission.setName(permissionCode);
            permission.setModule("system");
            role.getPermissions().add(permission);
        }
        return role;
    }
}
