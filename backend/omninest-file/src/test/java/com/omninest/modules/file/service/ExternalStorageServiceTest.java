package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.alibaba.fastjson2.JSONObject;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.rclone.RcloneGateway;
import com.omninest.modules.file.domain.ExternalStorageStatus;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.dto.CreateImportTaskRequest;
import com.omninest.modules.file.dto.ExternalFileListDto;
import com.omninest.modules.file.event.ExternalImportRequestedEvent;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import com.omninest.modules.file.repository.StorageImportTaskRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * ExternalStorageService 单元测试。
 *
 * @author OmniNest
 */
class ExternalStorageServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ACCOUNT_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final RcloneGateway rcloneGateway = mock(RcloneGateway.class);
    private final StorageExternalAccountRepository accountRepository =
            mock(StorageExternalAccountRepository.class);
    private final StorageImportTaskRepository importTaskRepository =
            mock(StorageImportTaskRepository.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final ExternalStorageCredentialService credentialService =
            mock(ExternalStorageCredentialService.class);
    private final SharedSpaceService sharedSpaceService = mock(SharedSpaceService.class);
    private final com.omninest.modules.file.config.ExternalStorageImportProperties importProperties =
            new com.omninest.modules.file.config.ExternalStorageImportProperties();
    private final ExternalStorageOAuthService oauthService = mock(ExternalStorageOAuthService.class);

    private final ExternalStorageService service = new ExternalStorageService(
            rcloneGateway, accountRepository,
            importTaskRepository, taskDispatchService, taskRecordService,
            credentialService, sharedSpaceService, importProperties, oauthService
    );

    @org.junit.jupiter.api.BeforeEach
    void setUpCredentialDecrypt() {
        when(credentialService.decryptToJson(org.mockito.ArgumentMatchers.anyString()))
                .thenAnswer(invocation -> invocation.getArgument(0));
    }

    @Test
    void browseExternalStorage_returnsFileList() {
        // 构造账户：S3 类型、ACTIVE 状态、有效凭证
        StorageExternalAccount account = buildAccount("S3", ExternalStorageStatus.ACTIVE.getValue());
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT_ID, OWNER_ID))
                .thenReturn(Optional.of(account));

        // 模拟 rclone remote 已存在（config/listremotes 返回带尾冒号的名称）
        String remoteName = "omni-" + ACCOUNT_ID.toString().replace("-", "").substring(0, 8);
        when(rcloneGateway.listRemoteNames()).thenReturn(List.of(remoteName + ":"));

        // 构造 Rclone 目录条目返回
        RcloneGateway.DirectoryEntry file = new RcloneGateway.DirectoryEntry(
                "report.pdf",
                "report.pdf",
                false,
                2048L,
                null,
                "application/pdf",
                null,
                Map.of("Name", "report.pdf", "IsDir", false, "Size", 2048L)
        );
        when(rcloneGateway.listDirectory(eq(remoteName + ":"), eq("documents"), eq(false)))
                .thenReturn(List.of(file));

        // 执行浏览
        ExternalFileListDto result = service.browse(OWNER_ID, ACCOUNT_ID, "/documents");

        // 验证返回文件列表
        assertThat(result.items()).hasSize(1);
        assertThat(result.items().get(0).name()).isEqualTo("report.pdf");
        assertThat(result.items().get(0).isDir()).isFalse();
        assertThat(result.items().get(0).sizeBytes()).isEqualTo(2048L);
        assertThat(result.remotePath()).isEqualTo("/documents");

        verify(rcloneGateway).listDirectory(eq(remoteName + ":"), eq("documents"), eq(false));
    }

    @Test
    void browseExternalStorage_throwsWhenAccountNotFound() {
        // 模拟账户不存在
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT_ID, OWNER_ID))
                .thenReturn(Optional.empty());

        // 验证抛出 NOT_FOUND 异常
        assertThatThrownBy(() -> service.browse(OWNER_ID, ACCOUNT_ID, "/documents"))
                .isInstanceOf(BusinessException.class)
                .satisfies(ex -> {
                    BusinessException bex = (BusinessException) ex;
                    assertThat(bex.errorCode()).isEqualTo(ErrorCode.NOT_FOUND);
                })
                .hasMessageContaining("外部存储账户不存在");
    }

    @Test
    void cancelImportTask_marksSystemTaskCancelled() {
        UUID importTaskId = UUID.fromString("30000000-0000-0000-0000-000000000001");
        UUID systemTaskId = UUID.fromString("40000000-0000-0000-0000-000000000001");
        StorageImportTask task = new StorageImportTask();
        task.setId(importTaskId);
        task.setTaskId(systemTaskId);
        task.setOwnerUserId(OWNER_ID);
        task.setStatus("RUNNING");
        when(importTaskRepository.findByIdAndOwnerUserId(importTaskId, OWNER_ID))
                .thenReturn(Optional.of(task));
        when(importTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.cancelImportTask(OWNER_ID, importTaskId);

        assertThat(task.getStatus()).isEqualTo("CANCELLED");
        verify(importTaskRepository).save(task);
        verify(taskRecordService).markCancelled(systemTaskId);
    }

    /**
     * 构造测试用外部存储账户。
     */
    private StorageExternalAccount buildAccount(String provider, String status) {
        StorageExternalAccount account = new StorageExternalAccount();
        account.setId(ACCOUNT_ID);
        account.setOwnerUserId(OWNER_ID);
        account.setProvider(provider);
        account.setDisplayName("测试存储");
        account.setEncryptedCredentials("{\"accessKey\":\"test\",\"secretKey\":\"test\"}");
        account.setStatus(status);
        return account;
    }

    @Test
    void createImportTaskEnqueuesThroughOutboxWithSystemTaskId() {
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT_ID, OWNER_ID))
                .thenReturn(Optional.of(buildAccount("WEBDAV", ExternalStorageStatus.ACTIVE.getValue())));
        when(importTaskRepository.save(any(StorageImportTask.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.createImportTask(OWNER_ID, ACCOUNT_ID,
                new CreateImportTaskRequest("/photos/vacation", null, null, null));

        ArgumentCaptor<UUID> recordIdCaptor = ArgumentCaptor.forClass(UUID.class);
        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> payloadCaptor = ArgumentCaptor.forClass(Map.class);
        verify(taskRecordService).createQueuedTask(
                recordIdCaptor.capture(),
                eq(OWNER_ID),
                eq("EXTERNAL_IMPORT"),
                eq(QueueNames.EXTERNAL_IMPORT_ROUTING_KEY),
                payloadCaptor.capture()
        );
        @SuppressWarnings("unchecked")
        ArgumentCaptor<ExternalImportRequestedEvent> eventCaptor =
                ArgumentCaptor.forClass(ExternalImportRequestedEvent.class);
        verify(taskDispatchService).enqueue(
                eq(recordIdCaptor.getValue()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.EXTERNAL_IMPORT_ROUTING_KEY),
                eventCaptor.capture()
        );
        assertThat(eventCaptor.getValue().taskId().toString())
                .isEqualTo(payloadCaptor.getValue().get("importTaskId"));
    }

    @Test
    void activateRemote_buildsTokenBlobForOAuthAccount() {
        StorageExternalAccount account = buildAccount("GDRIVE", ExternalStorageStatus.ACTIVE.getValue());
        account.setEncryptedCredentials(
                "{\"access_token\":\"at\",\"refresh_token\":\"rt\",\"token_type\":\"Bearer\","
                        + "\"expiry\":\"2026-09-26T00:00:00Z\"}");
        when(oauthService.findAppCredentials("GDRIVE")).thenReturn(Optional.of(
                new ExternalStorageOAuthService.ConnectorAppCredentials("cid", "csec")));

        service.activateRemote(account);

        String remoteName = "omni-" + ACCOUNT_ID.toString().replace("-", "").substring(0, 8);
        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, String>> paramsCaptor = ArgumentCaptor.forClass(Map.class);
        verify(rcloneGateway).createRemote(eq(remoteName), eq("drive"), paramsCaptor.capture());
        Map<String, String> params = paramsCaptor.getValue();
        assertThat(params).containsOnlyKeys("token", "client_id", "client_secret");
        assertThat(params.get("client_id")).isEqualTo("cid");
        assertThat(params.get("client_secret")).isEqualTo("csec");
        assertThat(JSONObject.parseObject(params.get("token")))
                .containsEntry("access_token", "at")
                .containsEntry("refresh_token", "rt")
                .containsEntry("token_type", "Bearer")
                .containsEntry("expiry", "2026-09-26T00:00:00Z");
    }

    @Test
    void activateRemote_omitsAppCredentialsForDropbox() {
        StorageExternalAccount account = buildAccount("DROPBOX", ExternalStorageStatus.ACTIVE.getValue());
        account.setEncryptedCredentials(
                "{\"access_token\":\"at\",\"refresh_token\":\"rt\",\"expiry\":\"2026-09-26T00:00:00Z\"}");

        service.activateRemote(account);

        String remoteName = "omni-" + ACCOUNT_ID.toString().replace("-", "").substring(0, 8);
        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, String>> paramsCaptor = ArgumentCaptor.forClass(Map.class);
        verify(rcloneGateway).createRemote(eq(remoteName), eq("dropbox"), paramsCaptor.capture());
        assertThat(paramsCaptor.getValue()).containsOnlyKeys("token");
        verify(oauthService, never()).findAppCredentials(any());
    }

    @Test
    void browse_recreatesRemoteAfterTokenRefresh() {
        StorageExternalAccount account = buildAccount("ONEDRIVE", ExternalStorageStatus.ACTIVE.getValue());
        account.setEncryptedCredentials("{\"access_token\":\"at\",\"refresh_token\":\"rt\"}");
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT_ID, OWNER_ID))
                .thenReturn(Optional.of(account));
        when(accountRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(oauthService.ensureAccessToken(account)).thenReturn(
                new ExternalStorageOAuthService.TokenRefreshResult(
                        JSONObject.parseObject("{\"access_token\":\"at2\"}"), true));
        when(oauthService.findAppCredentials("ONEDRIVE")).thenReturn(Optional.empty());
        String remoteName = "omni-" + ACCOUNT_ID.toString().replace("-", "").substring(0, 8);
        when(rcloneGateway.listRemoteNames()).thenReturn(List.of(remoteName + ":"));
        when(rcloneGateway.listDirectory(any(), any(), eq(false))).thenReturn(List.of());

        service.browse(OWNER_ID, ACCOUNT_ID, "/");

        // token 刷新后即使 remote 已存在也必须重建，使 rclone 拿到最新凭据
        verify(rcloneGateway).createRemote(eq(remoteName), eq("onedrive"), any());
    }

    @Test
    void activateRemote_rejectsLegacyAliyunAccountWithClearMessage() {
        StorageExternalAccount account = buildAccount("ALIYUN_DRIVE", ExternalStorageStatus.ACTIVE.getValue());

        assertThatThrownBy(() -> service.activateRemote(account))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("阿里云盘连接器已下架");
        verify(rcloneGateway, never()).createRemote(any(), any(), any());
    }

    @Test
    void listConnectors_reportsOAuthAppConfiguration() {
        when(oauthService.findAppCredentials("GDRIVE")).thenReturn(Optional.empty());
        when(oauthService.findAppCredentials("ONEDRIVE")).thenReturn(Optional.of(
                new ExternalStorageOAuthService.ConnectorAppCredentials("cid", "csec")));
        when(oauthService.findAppCredentials("DROPBOX")).thenReturn(Optional.of(
                new ExternalStorageOAuthService.ConnectorAppCredentials("cid", "csec")));

        var connectors = service.listConnectors();

        assertThat(connectors).extracting("code", "oauthConfigured").containsExactly(
                org.assertj.core.groups.Tuple.tuple("WEBDAV", true),
                org.assertj.core.groups.Tuple.tuple("S3", true),
                org.assertj.core.groups.Tuple.tuple("ONEDRIVE", true),
                org.assertj.core.groups.Tuple.tuple("GDRIVE", false),
                org.assertj.core.groups.Tuple.tuple("DROPBOX", true)
        );
    }
}
