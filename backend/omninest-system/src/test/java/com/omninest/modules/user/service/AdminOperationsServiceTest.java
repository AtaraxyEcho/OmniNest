package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.tuple;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.runtime.WorkerRuntimeRegistry;
import com.omninest.common.runtime.WorkerRuntimeState;
import com.omninest.common.security.Permissions;
import com.omninest.common.security.Roles;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.modules.configcenter.dto.ConfigEntryDto;
import com.omninest.modules.configcenter.dto.ConfigHistoryDto;
import com.omninest.modules.configcenter.service.ConfigCenterService;
import com.omninest.modules.task.repository.TaskDispatchRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRedispatchService;
import com.omninest.modules.user.domain.AuditLog;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AdminOperationsDto;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.user.repository.AdminConsoleMetricsRepository;
import com.omninest.modules.user.repository.AdminAnalyticsRepository;
import com.omninest.modules.user.repository.AuditLogAdminRepository;
import com.omninest.modules.user.repository.TaskRecordAdminRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.repository.AuthLoginAuditRepository;
import com.omninest.modules.user.repository.AuthPermissionRepository;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.port.ExternalStorageAccountSummary;
import com.omninest.modules.user.port.ExternalStorageAdministration;
import jakarta.persistence.NoResultException;
import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.boot.health.actuate.endpoint.HealthEndpoint;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

class AdminOperationsServiceTest {
    private final AuthRoleRepository authRoleRepository = mock(AuthRoleRepository.class);
    private final AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
    private final AuthPermissionRepository authPermissionRepository = mock(AuthPermissionRepository.class);
    private final ConfigCenterService configCenterService = mock(ConfigCenterService.class);
    private final AdminConsoleMetricsRepository metricsRepository = mock(AdminConsoleMetricsRepository.class);
    private final TaskRecordAdminRepository taskRecordRepository = mock(TaskRecordAdminRepository.class);
    private final ExternalStorageAdministration externalStorageAdministration =
            mock(ExternalStorageAdministration.class);
    private final AuditLogAdminRepository auditLogAdminRepository = mock(AuditLogAdminRepository.class);
    private final AdminAuditLogService auditLogService = mock(AdminAuditLogService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final TaskDispatchRepository taskDispatchRepository = mock(TaskDispatchRepository.class);
    private final TaskRedispatchService taskRedispatchService =
            new TaskRedispatchService(taskDispatchService, taskDispatchRepository);
    private final ObjectStorageBuckets objectStorageBuckets = createObjectStorageBuckets();
    private final HealthEndpoint healthEndpoint = mock(HealthEndpoint.class);
    private final ActiveSessionRepository activeSessionRepository = mock(ActiveSessionRepository.class);
    private final AuthLoginAuditRepository loginAuditRepository = mock(AuthLoginAuditRepository.class);
    private final SessionRevocationService sessionRevocationService = mock(SessionRevocationService.class);
    private final UserSessionRevocationService userSessionRevocationService =
            mock(UserSessionRevocationService.class);
    private final WorkerRuntimeRegistry workerRuntimeRegistry = availableWorkerRuntimeRegistry();
    private final AdminOperationsService service = new AdminOperationsService(
            authRoleRepository,
            authUserRepository,
            authPermissionRepository,
            configCenterService,
            metricsRepository,
            taskRecordRepository,
            externalStorageAdministration,
            auditLogAdminRepository,
            auditLogService,
            taskRedispatchService,
            objectStorageBuckets,
            healthEndpoint,
            activeSessionRepository,
            loginAuditRepository,
            sessionRevocationService,
            userSessionRevocationService,
            workerRuntimeRegistry
    );
    private final UUID actorUserId = UUID.fromString("99999999-9999-9999-9999-999999999999");

    private void givenFreshAdminActor() {
        AuthUser actor = new AuthUser();
        actor.setId(actorUserId);
        actor.setStatus("ACTIVE");
        actor.getRoles().add(role(Roles.ADMIN, permission(Permissions.SYSTEM_USER_READ, "system")));
        when(authUserRepository.findWithRolesAndPermissionsById(actorUserId)).thenReturn(Optional.of(actor));
    }

    @Test
    void rolesReturnsRolePermissionDetails() {
        AuthRole admin = role(Roles.ADMIN, permission(Permissions.SYSTEM_USER_READ, "system"));
        AuthPermission manageUsers = permission(Permissions.SYSTEM_USER_MANAGE, "system");
        when(authRoleRepository.findAllWithPermissions(Sort.by(Sort.Direction.ASC, "code"))).thenReturn(List.of(admin));
        when(authPermissionRepository.findAll(Sort.by(Sort.Direction.ASC, "module", "code")))
                .thenReturn(List.of(manageUsers));

        AdminOperationsDto.RoleManagementView view = service.roles();

        assertThat(view.roles()).hasSize(1);
        assertThat(view.roles().get(0).code()).isEqualTo(Roles.ADMIN);
        assertThat(view.roles().get(0).permissions()).containsExactly(Permissions.SYSTEM_USER_READ);
        assertThat(view.permissions()).extracting("code").containsExactly(Permissions.SYSTEM_USER_MANAGE);
    }

    @Test
    void updateRolePermissionsReplacesMutableRolePermissions() {
        givenFreshAdminActor();
        AuthRole admin = role(Roles.ADMIN, permission(Permissions.SYSTEM_USER_READ, "system"));
        AuthPermission manageUsers = permission(Permissions.SYSTEM_USER_MANAGE, "system");
        AuthUser affectedUser = new AuthUser();
        affectedUser.setId(UUID.fromString("10000000-0000-0000-0000-000000000001"));
        when(authRoleRepository.findByCode(Roles.ADMIN)).thenReturn(Optional.of(admin));
        when(authPermissionRepository.findByCodeIn(Set.of(Permissions.SYSTEM_USER_MANAGE)))
                .thenReturn(Set.of(manageUsers));
        when(authUserRepository.findAllByRoles_Code(Roles.ADMIN)).thenReturn(List.of(affectedUser));

        AdminOperationsDto.RoleDetail updated = service.updateRolePermissions(
                actorUserId,
                Roles.ADMIN,
                new AdminOperationsDto.UpdateRolePermissionsRequest(Set.of(Permissions.SYSTEM_USER_MANAGE))
        );

        assertThat(updated.permissions()).containsExactly(Permissions.SYSTEM_USER_MANAGE);
        assertThat(admin.getPermissions()).containsExactly(manageUsers);
        verify(userSessionRevocationService).revokeAll(List.of(affectedUser.getId()), "管理员更新角色权限");
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_ROLE_PERMISSIONS_UPDATE"), eq("auth_roles"), eq(admin.getId()),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("oldValue", List.of(Permissions.SYSTEM_USER_READ))
                .containsEntry("newValue", List.of(Permissions.SYSTEM_USER_MANAGE))
                .containsEntry("changeBy", actorUserId.toString());
    }

    @Test
    void updateRolePermissionsRejectsSuperAdmin() {
        givenFreshAdminActor();
        assertThatThrownBy(() -> service.updateRolePermissions(
                actorUserId,
                Roles.SUPER_ADMIN,
                new AdminOperationsDto.UpdateRolePermissionsRequest(Set.of(Permissions.SYSTEM_USER_READ))
        ))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    void updateRolePermissionsRejectsActorWithoutAdminRole() {
        AuthUser actor = new AuthUser();
        actor.setId(actorUserId);
        actor.setStatus("ACTIVE");
        actor.getRoles().add(role(Roles.MEMBER, permission(Permissions.SYSTEM_USER_READ, "system")));
        when(authUserRepository.findWithRolesAndPermissionsById(actorUserId)).thenReturn(Optional.of(actor));

        assertThatThrownBy(() -> service.updateRolePermissions(
                actorUserId,
                Roles.ADMIN,
                new AdminOperationsDto.UpdateRolePermissionsRequest(Set.of(Permissions.SYSTEM_USER_MANAGE))
        ))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    void createRoleClonesTemplatePermissionsAndWritesAudit() {
        givenFreshAdminActor();
        AuthPermission userRead = permission(Permissions.SYSTEM_USER_READ, "system");
        AuthPermission userManage = permission(Permissions.SYSTEM_USER_MANAGE, "system");
        AuthRole template = role(Roles.MEMBER, userRead, userManage);
        when(authRoleRepository.existsByCode("ROLE_MEDIA_CURATOR")).thenReturn(false);
        when(authRoleRepository.findWithPermissionsByCode(Roles.MEMBER)).thenReturn(Optional.of(template));

        AdminOperationsDto.RoleDetail created = service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest(
                        " role_media_curator ", "媒体策展人", "自定义角色", "member")
        );

        assertThat(created.code()).isEqualTo("ROLE_MEDIA_CURATOR");
        assertThat(created.name()).isEqualTo("媒体策展人");
        assertThat(created.builtIn()).isFalse();
        assertThat(created.enabled()).isTrue();
        assertThat(created.permissions())
                .containsExactly(Permissions.SYSTEM_USER_MANAGE, Permissions.SYSTEM_USER_READ);
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_ROLE_CREATE"), eq("auth_roles"), isNull(),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("code", "ROLE_MEDIA_CURATOR")
                .containsEntry("baseTemplate", "MEMBER")
                .containsEntry("permissionCount", 2);
    }

    @Test
    void createRoleSupportsNoneTemplate() {
        givenFreshAdminActor();
        when(authRoleRepository.existsByCode("ROLE_EMPTY")).thenReturn(false);

        AdminOperationsDto.RoleDetail created = service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_EMPTY", "空角色", null, null)
        );

        assertThat(created.permissions()).isEmpty();
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_ROLE_CREATE"), eq("auth_roles"), isNull(),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("baseTemplate", "NONE")
                .containsEntry("permissionCount", 0);
    }

    @Test
    void createRoleRejectsInvalidCodeFormat() {
        givenFreshAdminActor();

        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ADMIN", "管理员", null, "none")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("ROLE_")
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_MEDIA-CURATOR", "非法字符", null, "none")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_" + "X".repeat(64), "超长编码", null, "none")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    @Test
    void createRoleRejectsDuplicateCode() {
        givenFreshAdminActor();
        when(authRoleRepository.existsByCode("ROLE_MEDIA_CURATOR")).thenReturn(true);

        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_MEDIA_CURATOR", "媒体策展人", null, "none")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.CONFLICT);
    }

    @Test
    void createRoleRejectsUnknownBaseTemplate() {
        givenFreshAdminActor();

        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_MEDIA_CURATOR", "媒体策展人", null, "superadmin")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    @Test
    void createRoleRejectsMissingTemplateRole() {
        givenFreshAdminActor();
        when(authRoleRepository.existsByCode("ROLE_MEDIA_CURATOR")).thenReturn(false);
        when(authRoleRepository.findWithPermissionsByCode(Roles.MEMBER)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.createRole(
                actorUserId,
                new AdminOperationsDto.CreateRoleRequest("ROLE_MEDIA_CURATOR", "媒体策展人", null, "member")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.INTERNAL_ERROR);
    }

    @Test
    void deleteRoleRemovesCustomRoleAndClearsPermissionBindings() {
        givenFreshAdminActor();
        AuthRole custom = role("ROLE_MEDIA_CURATOR",
                permission(Permissions.SYSTEM_USER_READ, "system"),
                permission(Permissions.SYSTEM_USER_MANAGE, "system"));
        custom.setBuiltIn(false);
        when(authRoleRepository.findWithPermissionsByCode("ROLE_MEDIA_CURATOR")).thenReturn(Optional.of(custom));
        when(authUserRepository.existsByRoles_Code("ROLE_MEDIA_CURATOR")).thenReturn(false);

        service.deleteRole(actorUserId, "role_media_curator");

        assertThat(custom.getPermissions()).isEmpty();
        verify(authRoleRepository).delete(custom);
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_ROLE_DELETE"), eq("auth_roles"), eq(custom.getId()),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("code", "ROLE_MEDIA_CURATOR")
                .containsEntry("permissionCount", 2);
    }

    @Test
    void deleteRoleRejectsBuiltinRole() {
        givenFreshAdminActor();
        AuthRole builtin = role(Roles.ADMIN, permission(Permissions.SYSTEM_USER_READ, "system"));
        when(authRoleRepository.findWithPermissionsByCode(Roles.ADMIN)).thenReturn(Optional.of(builtin));

        assertThatThrownBy(() -> service.deleteRole(actorUserId, Roles.ADMIN))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
        verify(authRoleRepository, never()).delete(any(AuthRole.class));
    }

    @Test
    void deleteRoleRejectsRoleWithBoundUsers() {
        givenFreshAdminActor();
        AuthRole custom = role("ROLE_MEDIA_CURATOR");
        custom.setBuiltIn(false);
        when(authRoleRepository.findWithPermissionsByCode("ROLE_MEDIA_CURATOR")).thenReturn(Optional.of(custom));
        when(authUserRepository.existsByRoles_Code("ROLE_MEDIA_CURATOR")).thenReturn(true);

        assertThatThrownBy(() -> service.deleteRole(actorUserId, "ROLE_MEDIA_CURATOR"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("解绑")
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.RESOURCE_IN_USE);
        verify(authRoleRepository, never()).delete(any(AuthRole.class));
    }

    @Test
    void deleteRoleRejectsMissingRole() {
        givenFreshAdminActor();
        when(authRoleRepository.findWithPermissionsByCode("ROLE_GONE")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.deleteRole(actorUserId, "ROLE_GONE"))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    @Test
    void operationsReturnTasksLogsStorageAndExternalStorageRows() {
        UUID taskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        UUID logId = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
        UUID ownerUserId = UUID.fromString("dddddddd-dddd-dddd-dddd-dddddddddddd");
        List<Object[]> taskRows = Collections.singletonList(
                new Object[]{taskId, "FILE_INDEX", "FAILED", 30, "omninest.file.index", "索引失败", 2,
                        Instant.parse("2026-05-20T10:00:00Z"), Instant.parse("2026-05-20T10:10:00Z"),
                        ownerUserId, "member-it"}
        );
        doReturn(taskRows).when(taskRecordRepository).findRecent(100);
        var auditLog = new AuditLog();
        auditLog.setId(logId);
        auditLog.setAction("LOGIN");
        auditLog.setResourceType("auth_users");
        auditLog.setIpAddress("127.0.0.1");
        auditLog.setCreatedAt(Instant.parse("2026-05-20T09:00:00Z"));
        when(auditLogAdminRepository.findAllByOrderByCreatedAtDesc(any())).thenReturn(List.of(auditLog));
        UUID externalId = UUID.fromString("cccccccc-cccc-cccc-cccc-cccccccccccc");
        ExternalStorageAccountSummary externalAccount = new ExternalStorageAccountSummary(
                externalId,
                ownerUserId,
                "S3",
                "冷备桶",
                "ACTIVE",
                Instant.parse("2026-05-20T09:00:00Z"),
                Instant.parse("2026-05-20T10:00:00Z")
        );
        when(externalStorageAdministration.listAccounts()).thenReturn(List.of(externalAccount));

        var taskView = service.tasks();
        assertThat(taskView.items()).extracting("id").containsExactly(taskId);
        assertThat(taskView.items())
                .extracting(AdminOperationsDto.TaskRecordItem::ownerUserId,
                        AdminOperationsDto.TaskRecordItem::ownerLabel)
                .containsExactly(tuple(ownerUserId, "member-it"));
        assertThat(service.logs().items()).extracting("id").containsExactly(logId);
        assertThat(service.storage().buckets())
                .extracting(AdminOperationsDto.BucketItem::name)
                .containsExactly("user-files", "derived-assets");
        assertThat(service.externalStorage().items()).extracting("id").containsExactly(externalId);
        verify(taskRecordRepository).findRecent(100);
        ArgumentCaptor<Pageable> auditPage = ArgumentCaptor.forClass(Pageable.class);
        verify(auditLogAdminRepository).findAllByOrderByCreatedAtDesc(auditPage.capture());
        assertThat(auditPage.getValue().getPageSize()).isEqualTo(100);
    }

    @Test
    void retryTaskOnlyAllowsFailedCancelledOrDlqTasks() {
        UUID taskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        UUID fileNodeId = UUID.fromString("11111111-1111-1111-1111-111111111111");
        UUID fileObjectId = UUID.fromString("22222222-2222-2222-2222-222222222222");
        String payload = """
                {
                  "fileNodeId": "%s",
                  "fileObjectId": "%s",
                  "ownerUserId": "%s",
                  "bucket": "user-files",
                  "objectKey": "objects/a.mp3",
                  "fileName": "a.mp3",
                  "mimeType": "audio/mpeg",
                  "sizeBytes": 1024,
                  "occurredAt": "2026-06-01T10:00:00Z"
                }
                """.formatted(fileNodeId, fileObjectId, actorUserId);
        List<Object[]> taskRow = Collections.singletonList(
                new Object[]{taskId, "FILE_INDEX", "FAILED", 80, "file.index", "失败", 1,
                        Instant.now(), Instant.now(), payload}
        );
        doReturn(taskRow).when(taskRecordRepository).findByIdRaw(taskId);
        when(metricsRepository.updateTaskStatusReturning(eq(taskId), eq("QUEUED"), eq(0))).thenReturn(
                new AdminOperationsDto.TaskRecordItem(
                        taskId,
                        "FILE_INDEX",
                        "更新文件索引",
                        "QUEUED",
                        0,
                        "file.index",
                        null,
                        1,
                        Instant.now(),
                        Instant.now(),
                        actorUserId,
                        "admin-it"
                )
        );

        var retried = service.retryTask(actorUserId, taskId);

        assertThat(retried.status()).isEqualTo("QUEUED");
        assertThat(retried.progress()).isZero();

        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(taskDispatchService).enqueue(
                eq(taskId), eq(QueueNames.TASK_EXCHANGE), eq("file.index"), payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("fileNodeId", fileNodeId.toString())
                .containsEntry("fileObjectId", fileObjectId.toString())
                .containsEntry("ownerUserId", actorUserId.toString())
                .containsEntry("bucket", "user-files")
                .containsEntry("objectKey", "objects/a.mp3");
        verify(auditLogService).record(actorUserId, "ADMIN_TASK_RETRY", "sys_tasks", taskId);
    }

    @Test
    void retryTaskRejectsMissingReplayPayload() {
        UUID taskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        List<Object[]> taskRow = Collections.singletonList(
                new Object[]{taskId, "FILE_INDEX", "FAILED", 80, "file.index", "失败", 1,
                        Instant.now(), Instant.now(), "{}"}
        );
        doReturn(taskRow).when(taskRecordRepository).findByIdRaw(taskId);

        assertThatThrownBy(() -> service.retryTask(actorUserId, taskId))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("任务缺少可重试载荷字段");
    }

    @Test
    void retryTaskRebuildsMusicScrapePayloadFromSystemTask() {
        UUID taskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        String payload = """
                {
                  "jobId": "%s",
                  "ownerUserId": "%s",
                  "force": true
                }
                """.formatted(taskId, actorUserId);
        List<Object[]> taskRow = Collections.singletonList(
                new Object[]{taskId, "MUSIC_SCRAPE", "FAILED", 80, QueueNames.MUSIC_SCRAPE_ROUTING_KEY, "失败", 1,
                        Instant.now(), Instant.now(), payload}
        );
        doReturn(taskRow).when(taskRecordRepository).findByIdRaw(taskId);
        when(metricsRepository.updateTaskStatusReturning(eq(taskId), eq("QUEUED"), eq(0))).thenReturn(
                new AdminOperationsDto.TaskRecordItem(
                        taskId,
                        "MUSIC_SCRAPE",
                        "抓取音乐元数据",
                        "QUEUED",
                        0,
                        QueueNames.MUSIC_SCRAPE_ROUTING_KEY,
                        null,
                        1,
                        Instant.now(),
                        Instant.now(),
                        actorUserId,
                        "admin-it"
                )
        );

        service.retryTask(actorUserId, taskId);

        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(taskDispatchService).enqueue(
                eq(taskId),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.MUSIC_SCRAPE_ROUTING_KEY),
                payloadCaptor.capture()
        );
        assertThat(payloadCaptor.getValue())
                .containsEntry("jobId", taskId.toString())
                .containsEntry("ownerUserId", actorUserId.toString())
                .containsEntry("force", true);
    }

    @Test
    void retryTaskUsesExternalImportBusinessTaskId() {
        UUID systemTaskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        UUID importTaskId = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
        String payload = """
                {
                  "importTaskId": "%s",
                  "externalAccountId": "cccccccc-cccc-cccc-cccc-cccccccccccc",
                  "sourcePath": "/remote/books",
                  "targetParentId": "",
                  "spaceType": "PRIVATE"
                }
                """.formatted(importTaskId);
        List<Object[]> taskRow = Collections.singletonList(
                new Object[]{systemTaskId, "EXTERNAL_IMPORT", "FAILED", 80,
                        QueueNames.EXTERNAL_IMPORT_ROUTING_KEY, "失败", 1,
                        Instant.now(), Instant.now(), payload}
        );
        doReturn(taskRow).when(taskRecordRepository).findByIdRaw(systemTaskId);
        when(metricsRepository.updateTaskStatusReturning(eq(systemTaskId), eq("QUEUED"), eq(0))).thenReturn(
                new AdminOperationsDto.TaskRecordItem(
                        systemTaskId,
                        "EXTERNAL_IMPORT",
                        "导入外部存储内容",
                        "QUEUED",
                        0,
                        QueueNames.EXTERNAL_IMPORT_ROUTING_KEY,
                        null,
                        1,
                        Instant.now(),
                        Instant.now(),
                        null,
                        null
                )
        );

        service.retryTask(actorUserId, systemTaskId);

        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(taskDispatchService).enqueue(
                eq(systemTaskId),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.EXTERNAL_IMPORT_ROUTING_KEY),
                payloadCaptor.capture()
        );
        assertThat(payloadCaptor.getValue()).containsEntry("taskId", importTaskId.toString());
    }

    @Test
    void monitoringReturnsOperationalSnapshot() {
        UUID logId = UUID.fromString("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
        when(taskRecordRepository.countByStatus("RUNNING")).thenReturn(2L);
        when(taskRecordRepository.countByStatus("QUEUED")).thenReturn(5L);
        when(taskRecordRepository.countByStatus("FAILED")).thenReturn(1L);
        when(taskRecordRepository.countByStatus("DLQ")).thenReturn(1L);
        when(auditLogAdminRepository.countSince(any())).thenReturn(12L);
        var auditLog = new AuditLog();
        auditLog.setId(logId);
        auditLog.setActorUserId(actorUserId);
        auditLog.setAction("ADMIN_CONFIG_UPDATE");
        auditLog.setResourceType("config_entries");
        auditLog.setIpAddress("127.0.0.1");
        auditLog.setCreatedAt(Instant.parse("2026-05-20T09:00:00Z"));
        when(auditLogAdminRepository.findAllByOrderByCreatedAtDesc(any())).thenReturn(List.of(auditLog));

        AdminOperationsDto.MonitoringView view = service.monitoring();

        assertThat(view.overview().activeTasks()).isEqualTo(2);
        assertThat(view.overview().queueDepth()).isEqualTo(5);
        assertThat(view.overview().todayRequests()).isEqualTo(12);
        assertThat(view.components()).extracting("name").contains("PostgreSQL", "RabbitMQ", "MinIO", "Worker");
        AdminOperationsDto.MonitoringComponent worker = view.components().stream()
                .filter(component -> "Worker".equals(component.name()))
                .findFirst()
                .orElseThrow();
        assertThat(worker.detail()).containsEntry("activeInstanceCount", 1);
        assertThat(view.alerts()).isNotEmpty();
        assertThat(view.auditRecent()).extracting("id").containsExactly(logId);
        assertThat(view.series()).extracting("metric").contains("cpu", "memory", "jvmHeap", "tasks");
        assertThat(view.series()).allSatisfy(series -> assertThat(series.points()).hasSize(1));
        assertThat(view.metrics()).extracting("name").contains("队列待处理", "死信任务");
    }

    @Test
    void updateConfigDelegatesToConfigCenter() {
        givenFreshAdminActor();
        when(configCenterService.auditContext("rate-limit.default-limit"))
                .thenReturn(new ConfigCenterService.ConfigAuditContext(false, "120"));
        when(configCenterService.update("rate-limit.default-limit", "180", "调整默认限流", actorUserId)).thenReturn(
                new ConfigEntryDto("rate-limit.default-limit", "180", "STRING", "runtime", "HOT", Instant.now(), null)
        );

        var updated = service.updateConfig(
                actorUserId,
                "rate-limit.default-limit",
                new AdminOperationsDto.UpdateConfigRequest("180", "调整默认限流")
        );

        assertThat(updated.value()).isEqualTo("180");
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_CONFIG_UPDATE"), eq("config_entries"), isNull(),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("key", "rate-limit.default-limit")
                .containsEntry("oldValue", "120")
                .containsEntry("newValue", "180")
                .containsEntry("reason", "调整默认限流")
                .containsEntry("changeBy", actorUserId.toString());
    }

    @Test
    void updateConfigMasksSensitiveValuesInAuditPayload() {
        givenFreshAdminActor();
        when(configCenterService.auditContext("integration.musicbrainz.token"))
                .thenReturn(new ConfigCenterService.ConfigAuditContext(true, "v1:cipher:secret"));
        when(configCenterService.update("integration.musicbrainz.token", "new-token", null, actorUserId)).thenReturn(
                new ConfigEntryDto("integration.musicbrainz.token", null, "STRING", "integration", "HOT",
                        Instant.now(), null)
        );

        service.updateConfig(
                actorUserId,
                "integration.musicbrainz.token",
                new AdminOperationsDto.UpdateConfigRequest("new-token", null)
        );

        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_CONFIG_UPDATE"), eq("config_entries"), isNull(),
                payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("oldValue", ConfigHistoryDto.MASK)
                .containsEntry("newValue", ConfigHistoryDto.MASK)
                .containsKey("reason")
                .doesNotContainEntry("newValue", "new-token")
                .doesNotContainEntry("oldValue", "v1:cipher:secret");
    }

    @Test
    void cancelTaskCancelsQueuedTaskAndRecordsReason() {
        UUID taskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        doReturn(rawTaskRow(taskId, "QUEUED")).when(taskRecordRepository).findByIdRaw(taskId);
        when(metricsRepository.updateTaskTerminalReturning(taskId, "CANCELLED", "QUEUED", "cancelled by admin"))
                .thenReturn(taskRecordItem(taskId, "CANCELLED"));

        var cancelled = service.cancelTask(actorUserId, taskId);

        assertThat(cancelled.status()).isEqualTo("CANCELLED");
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_TASK_CANCEL"), eq("sys_tasks"), eq(taskId), payloadCaptor.capture());
        assertThat(payloadCaptor.getValue())
                .containsEntry("reason", "cancelled by admin")
                .containsEntry("previousStatus", "QUEUED");
    }

    @Test
    void cancelTaskRejectsRunningTask() {
        UUID taskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        doReturn(rawTaskRow(taskId, "RUNNING")).when(taskRecordRepository).findByIdRaw(taskId);

        assertThatThrownBy(() -> service.cancelTask(actorUserId, taskId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.TASK_STATUS_ILLEGAL);
    }

    @Test
    void cancelTaskRejectsMissingTask() {
        UUID taskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        doReturn(List.of()).when(taskRecordRepository).findByIdRaw(taskId);

        assertThatThrownBy(() -> service.cancelTask(actorUserId, taskId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    @Test
    void cancelTaskReportsConcurrentStateChange() {
        UUID taskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        doReturn(rawTaskRow(taskId, "QUEUED")).when(taskRecordRepository).findByIdRaw(taskId);
        when(metricsRepository.updateTaskTerminalReturning(taskId, "CANCELLED", "QUEUED", "cancelled by admin"))
                .thenThrow(new NoResultException());

        assertThatThrownBy(() -> service.cancelTask(actorUserId, taskId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.TASK_STATUS_ILLEGAL);
    }

    @Test
    void discardDlqTaskMarksDiscardedTerminalWithoutOverwritingError() {
        UUID taskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        doReturn(rawTaskRow(taskId, "DLQ")).when(taskRecordRepository).findByIdRaw(taskId);
        when(metricsRepository.updateTaskTerminalReturning(taskId, "DISCARDED", "DLQ", null))
                .thenReturn(taskRecordItem(taskId, "DISCARDED"));

        var discarded = service.discardDlqTask(actorUserId, taskId);

        assertThat(discarded.status()).isEqualTo("DISCARDED");
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(auditLogService).recordWithPayload(
                eq(actorUserId), eq("ADMIN_TASK_DLQ_DISCARD"), eq("sys_tasks"), eq(taskId), payloadCaptor.capture());
        assertThat(payloadCaptor.getValue()).containsEntry("previousStatus", "DLQ");
    }

    @Test
    void discardDlqTaskRejectsNonDlqTask() {
        UUID taskId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        doReturn(rawTaskRow(taskId, "FAILED")).when(taskRecordRepository).findByIdRaw(taskId);

        assertThatThrownBy(() -> service.discardDlqTask(actorUserId, taskId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.TASK_STATUS_ILLEGAL);
    }

    @Test
    void cleanupPreviewsCountWithSameCutoffAsCleanup() {
        when(auditLogAdminRepository.countCreatedBefore(any())).thenReturn(7L);
        when(loginAuditRepository.countCreatedBefore(any())).thenReturn(3L);
        when(activeSessionRepository.countInactiveBefore(any())).thenReturn(5L);

        assertThat(service.previewCleanupAuditLogs(30)).isEqualTo(7);
        assertThat(service.previewCleanupLoginAuditLogs(30)).isEqualTo(3);
        assertThat(service.previewCleanupSessions(30)).isEqualTo(5);
    }

    @Test
    void cleanupPreviewsRejectOutOfRangeRetentionDays() {
        assertThatThrownBy(() -> service.previewCleanupAuditLogs(-1))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
        assertThatThrownBy(() -> service.previewCleanupLoginAuditLogs(3651))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
        assertThatThrownBy(() -> service.previewCleanupSessions(-1))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    private List<Object[]> rawTaskRow(UUID taskId, String status) {
        return Collections.singletonList(new Object[]{
                taskId, "FILE_INDEX", status, 0, "file.index", null, 0,
                Instant.parse("2026-06-01T10:00:00Z"), Instant.parse("2026-06-01T10:00:00Z"), "{}"
        });
    }

    private AdminOperationsDto.TaskRecordItem taskRecordItem(UUID taskId, String status) {
        return new AdminOperationsDto.TaskRecordItem(
                taskId,
                "FILE_INDEX",
                "更新文件索引",
                status,
                0,
                "file.index",
                null,
                0,
                Instant.parse("2026-06-01T10:00:00Z"),
                Instant.parse("2026-06-01T10:00:00Z"),
                null,
                null
        );
    }

    private static WorkerRuntimeRegistry availableWorkerRuntimeRegistry() {
        WorkerRuntimeRegistry registry = mock(WorkerRuntimeRegistry.class);
        when(registry.activeInstances()).thenReturn(List.of(new WorkerRuntimeState(
                "worker-1",
                Instant.parse("2026-05-20T08:00:00Z"),
                Map.of(
                        WorkerRuntimeState.PHOTO_AI_CAPABILITY,
                        WorkerRuntimeState.CapabilityStatus.disabled("照片 AI 已关闭")
                )
        )));
        return registry;
    }

    @Test
    void sessionAndLoginAuditQueriesAreBoundedInDatabase() {
        when(activeSessionRepository.findAllByOrderByCreatedAtDesc(any())).thenReturn(List.of());
        when(loginAuditRepository.findAllByOrderByCreatedAtDesc(any())).thenReturn(List.of());

        service.allSessions();
        service.loginAuditLogs();

        ArgumentCaptor<Pageable> sessionPage = ArgumentCaptor.forClass(Pageable.class);
        verify(activeSessionRepository).findAllByOrderByCreatedAtDesc(sessionPage.capture());
        assertThat(sessionPage.getValue().getPageSize()).isEqualTo(500);
        ArgumentCaptor<Pageable> loginAuditPage = ArgumentCaptor.forClass(Pageable.class);
        verify(loginAuditRepository).findAllByOrderByCreatedAtDesc(loginAuditPage.capture());
        assertThat(loginAuditPage.getValue().getPageSize()).isEqualTo(500);
    }

    private static ObjectStorageBuckets createObjectStorageBuckets() {
        ObjectStorageBuckets buckets = mock(ObjectStorageBuckets.class);
        when(buckets.userFiles()).thenReturn("user-files");
        when(buckets.derivedAssets()).thenReturn("derived-assets");
        return buckets;
    }

    private AuthRole role(String code, AuthPermission... permissions) {
        AuthRole role = new AuthRole();
        role.setId(UUID.randomUUID());
        role.setCode(code);
        role.setName(code);
        role.getPermissions().addAll(List.of(permissions));
        return role;
    }

    private AuthPermission permission(String code, String module) {
        AuthPermission permission = new AuthPermission();
        permission.setId(UUID.randomUUID());
        permission.setCode(code);
        permission.setName(code);
        permission.setModule(module);
        return permission;
    }
}
