package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.ratelimit.TokenBucketRateLimiter;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.upload.FileUploadSettings;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FileUploadPart;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.UploadStatus;
import com.omninest.modules.file.dto.CompleteFileUploadPartRequest;
import com.omninest.modules.file.dto.CompleteFileUploadRequest;
import com.omninest.modules.file.dto.CreateFileUploadSessionRequest;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.FileUploadPartRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.net.URI;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 文件上传会话服务测试。
 *
 * @author OmniNest
 */
class FileUploadSessionServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final UUID SESSION_ID = UUID.fromString("00000000-0000-0000-0000-000000000002");
    private static final UUID FILE_NODE_ID = UUID.fromString("00000000-0000-0000-0000-000000000003");
    private static final UUID FILE_OBJECT_ID = UUID.fromString("00000000-0000-0000-0000-000000000004");
    private static final UUID QUOTA_RESERVATION_ID =
            UUID.fromString("00000000-0000-0000-0000-000000000005");
    private static final UUID MEDIA_TASK_ID = UUID.fromString("00000000-0000-0000-0000-000000000006");
    private static final UUID SCAN_TASK_ID = UUID.fromString("00000000-0000-0000-0000-000000000007");

    private FileUploadSessionRepository uploadSessionRepository;
    private FileUploadPartRepository uploadPartRepository;
    private FileNodeRepository fileNodeRepository;
    private FileObjectRepository fileObjectRepository;
    private StorageQuotaService storageQuotaService;
    private ObjectStorageClient objectStorageClient;
    private FilePostProcessingTaskService postProcessingTaskService;
    private FileIngressLifecycleService ingressLifecycleService;
    private FileIngressScanTaskService ingressScanTaskService;
    private FileUploadSessionService service;
    private ConfigValueProvider configValueProvider;

    @BeforeEach
    void setUp() {
        uploadSessionRepository = mock(FileUploadSessionRepository.class);
        uploadPartRepository = mock(FileUploadPartRepository.class);
        fileNodeRepository = mock(FileNodeRepository.class);
        fileObjectRepository = mock(FileObjectRepository.class);
        storageQuotaService = mock(StorageQuotaService.class);
        objectStorageClient = mock(ObjectStorageClient.class);
        postProcessingTaskService = mock(FilePostProcessingTaskService.class);
        ingressScanTaskService = mock(FileIngressScanTaskService.class);
        ObjectStorageBuckets objectStorageBuckets = mock(ObjectStorageBuckets.class);
        when(objectStorageBuckets.userFiles()).thenReturn("user-files");
        when(objectStorageBuckets.quarantine()).thenReturn("file-quarantine");
        FileUploadSettings uploadSettings = mock(FileUploadSettings.class);
        when(uploadSettings.presignedUrlTtl()).thenReturn(Duration.ofHours(4));
        when(uploadSettings.sessionTtl()).thenReturn(Duration.ofHours(24));
        when(uploadSettings.maxPresignedPartsPerSecond()).thenReturn(4);
        when(uploadSettings.presignedPartBurstCapacity()).thenReturn(8);
        when(uploadSettings.bandwidthLimitEnabled()).thenReturn(true);
        TokenBucketRateLimiter bandwidthLimiter = mock(TokenBucketRateLimiter.class);
        ingressLifecycleService = mock(FileIngressLifecycleService.class);
        configValueProvider = mock(ConfigValueProvider.class);
        RuntimeConfigCache runtimeConfigCache = mock(RuntimeConfigCache.class);
        FileContentChangePublisher fileContentChangePublisher =
                new FileContentChangePublisher(postProcessingTaskService);
        when(runtimeConfigCache.get(anyString())).thenReturn(Optional.empty());
        when(ingressLifecycleService.open(any())).thenReturn(UUID.randomUUID());
        when(storageQuotaService.reserve(
                eq(OWNER_ID),
                eq("UPLOAD"),
                any(UUID.class),
                anyLong(),
                any(Instant.class)
        )).thenReturn(QUOTA_RESERVATION_ID);
        service = new FileUploadSessionService(
                uploadSessionRepository,
                uploadPartRepository,
                fileNodeRepository,
                fileObjectRepository,
                storageQuotaService,
                bandwidthLimiter,
                objectStorageClient,
                postProcessingTaskService,
                objectStorageBuckets,
                uploadSettings,
                ingressLifecycleService,
                ingressScanTaskService,
                configValueProvider,
                runtimeConfigCache,
                fileContentChangePublisher
        );
    }

    @Test
    void uploadPolicyUsesUploadSettingsContract() {
        var policy = service.uploadPolicy();

        assertThat(policy.uploadUrlTtlSeconds()).isEqualTo(Duration.ofHours(4).getSeconds());
        assertThat(policy.maxPartsPerSecond()).isEqualTo(4);
        assertThat(policy.bandwidthLimitEnabled()).isTrue();
    }

    @Test
    void uploadPolicyReadsCanonicalRateSwitchFromConfigCenter() {
        when(configValueProvider.findByKey("upload.rate.enabled"))
                .thenReturn(Optional.of("false"));

        assertThat(service.uploadPolicy().bandwidthLimitEnabled()).isFalse();
    }

    @Test
    void createSessionReturnsReusableActiveConflictDetails() {
        FileNode existingFile = fileNode("photo.jpg", "image/jpeg", 2048L);
        when(fileNodeRepository.findActiveNameConflict(OWNER_ID, null, "photo.jpg"))
                .thenReturn(Optional.of(existingFile));

        assertThatThrownBy(() -> service.createSession(OWNER_ID, new CreateFileUploadSessionRequest(
                null,
                "photo.jpg",
                2048L,
                "image/jpeg",
                null,
                null,
                null,
                null
        ))).isInstanceOfSatisfying(BusinessException.class, exception -> {
            assertThat(exception.errorCode()).isEqualTo(ErrorCode.CONFLICT);
            assertThat(exception.details()).containsEntry("existingFileId", FILE_NODE_ID.toString());
            assertThat(exception.details()).containsEntry("sizeBytes", 2048L);
            assertThat(exception.details()).containsEntry("mimeType", "image/jpeg");
        });
    }

    @Test
    void reprocessExistingFilePublishesMediaProcessingTasks() {
        FileNode file = fileNode("photo.jpg", "image/jpeg", 2048L);
        FileObject fileObject = new FileObject();
        fileObject.setId(FILE_OBJECT_ID);
        fileObject.setBucketName("user-files");
        fileObject.setObjectKey("users/owner/photo.jpg");
        fileObject.setMimeType("image/jpeg");
        fileObject.setSizeBytes(2048L);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(FILE_NODE_ID, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(fileObjectRepository.findById(FILE_OBJECT_ID)).thenReturn(Optional.of(fileObject));
        when(postProcessingTaskService.enqueueMediaAutoImport(any(FileUploadedEvent.class)))
                .thenReturn(MEDIA_TASK_ID);

        var result = service.reprocessExistingFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.id()).isEqualTo(FILE_NODE_ID);
        assertThat(result.mediaAutoImportTaskId()).isEqualTo(MEDIA_TASK_ID);
        verify(postProcessingTaskService).enqueueMediaAutoImport(any(FileUploadedEvent.class));
        ArgumentCaptor<FileUploadedEvent> postCaptor = ArgumentCaptor.forClass(FileUploadedEvent.class);
        verify(postProcessingTaskService).enqueuePostProcess(postCaptor.capture(), eq("image/jpeg"));
        assertThat(postCaptor.getValue().fileNodeId()).isEqualTo(FILE_NODE_ID);
    }

    @Test
    void createSessionReturnsUploadIdAndPartUrls() {
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(OWNER_ID, "video.mp4"))
                .thenReturn(false);
        when(objectStorageClient.initiateMultipartUpload(any(), eq("video/mp4"))).thenReturn("upload-123");
        when(uploadSessionRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(uploadPartRepository.saveAll(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(objectStorageClient.createMultipartUploadPartUrl(any(), eq("upload-123"), anyInt(), any()))
                .thenReturn(URI.create("http://minio/part"));

        var response = service.createSession(OWNER_ID, new CreateFileUploadSessionRequest(
                null,
                "video.mp4",
                20L * 1024 * 1024,
                "video/mp4",
                null,
                10 * 1024 * 1024,
                null,
                null
        ));

        assertThat(response.uploadId()).isEqualTo("upload-123");
        assertThat(response.partSizeBytes()).isEqualTo(10 * 1024 * 1024);
        assertThat(response.totalParts()).isEqualTo(2);
        assertThat(response.parts()).hasSize(2);
        assertThat(response.parts()).extracting("partNumber").containsExactly(1, 2);
    }

    @Test
    void createSession_skipsNameConflictWhenAsVersionOfFile() {
        UUID asVersionOfFileId = UUID.randomUUID();
        FileNode target = new FileNode();
        target.setId(asVersionOfFileId);
        target.setOwnerUserId(OWNER_ID);
        target.setName("video.mp4");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(asVersionOfFileId, OWNER_ID))
                .thenReturn(Optional.of(target));
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(OWNER_ID, "video.mp4"))
                .thenReturn(true);
        when(objectStorageClient.initiateMultipartUpload(any(), eq("video.mp4"))).thenReturn("upload-123");
        when(uploadSessionRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(uploadPartRepository.saveAll(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(objectStorageClient.createMultipartUploadPartUrl(any(), eq("upload-123"), anyInt(), any()))
                .thenReturn(URI.create("http://minio/part"));

        var response = service.createSession(OWNER_ID, new CreateFileUploadSessionRequest(
                null,
                "video.mp4",
                20L * 1024 * 1024,
                "video.mp4",
                null,
                10 * 1024 * 1024,
                null,
                asVersionOfFileId
        ));

        assertThat(response.uploadId()).isEqualTo("upload-123");
    }

    @Test
    void createSessionRejectsQuotaOverflow() {
        Mockito.doThrow(new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "存储配额不足"))
                .when(storageQuotaService).reserve(
                        eq(OWNER_ID),
                        eq("UPLOAD"),
                        any(UUID.class),
                        eq(50L),
                        any(Instant.class)
                );

        assertThatThrownBy(() -> service.createSession(OWNER_ID, new CreateFileUploadSessionRequest(
                null,
                "demo.pdf",
                50,
                "application/pdf",
                null,
                null,
                null,
                null
        ))).isInstanceOf(BusinessException.class)
                .hasMessageContaining("存储配额不足");
    }

    @Test
    void completePartStoresETagAndReturnsCompletedPartNumbers() {
        FileUploadSession session = session();
        FileUploadPart part = part(1, "PENDING", null);
        when(uploadSessionRepository.findByUploadIdAndOwnerUserId("upload-123", OWNER_ID))
                .thenReturn(Optional.of(session));
        when(uploadSessionRepository.findForUpdateByUploadIdAndOwnerUserId("upload-123", OWNER_ID))
                .thenReturn(Optional.of(session));
        when(uploadPartRepository.findByUploadSessionIdAndPartNumber(SESSION_ID, 1)).thenReturn(Optional.of(part));
        when(uploadPartRepository.findByUploadSessionIdOrderByPartNumber(SESSION_ID)).thenReturn(List.of(part));
        when(uploadPartRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(uploadSessionRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        var response = service.completePart(
                OWNER_ID,
                "upload-123",
                1,
                new CompleteFileUploadPartRequest(1, "\"etag-1\"")
        );

        assertThat(part.getETag()).isEqualTo("etag-1");
        assertThat(part.getStatus()).isEqualTo("COMPLETED");
        assertThat(response.completedPartNumbers()).containsExactly(1);
    }

    @Test
    void completeSessionDispatchesSecurityScanAndReturnsScanning() {
        FileUploadSession session = session();
        FileUploadPart part = part(1, "COMPLETED", "etag-1");
        when(uploadSessionRepository.findByUploadIdAndOwnerUserId("upload-123", OWNER_ID))
                .thenReturn(Optional.of(session));
        when(uploadSessionRepository.findForUpdateByUploadIdAndOwnerUserId("upload-123", OWNER_ID))
                .thenReturn(Optional.of(session));
        when(uploadPartRepository.findByUploadSessionIdOrderByPartNumber(SESSION_ID)).thenReturn(List.of(part));
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(OWNER_ID, "demo.pdf"))
                .thenReturn(false);
        when(uploadSessionRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(ingressScanTaskService.enqueueScanTask(any(), any(), any(), any())).thenReturn(SCAN_TASK_ID);

        var result = service.completeSession(OWNER_ID, "upload-123", new CompleteFileUploadRequest(null, List.of(), null));

        assertThat(result.status()).isEqualTo("SCANNING");
        assertThat(result.taskId()).isEqualTo(SCAN_TASK_ID);
        assertThat(result.fileNodeId()).isNull();
        assertThat(session.getStatus()).isEqualTo("SCANNING");
        verify(objectStorageClient).completeMultipartUpload(any(), eq("upload-123"), any());
        verify(ingressLifecycleService).open(any());
        verify(storageQuotaService).extendReservation(eq("UPLOAD"), eq(SESSION_ID), any(Instant.class));
        verify(fileNodeRepository, Mockito.never()).save(any());
        verify(objectStorageClient, Mockito.never()).copyObject(any(), any());
        verify(storageQuotaService, Mockito.never()).settleReservation(any(), any(), anyLong());
    }

    @Test
    void completeSessionIsIdempotentWhileScanning() {
        FileUploadSession session = session();
        session.setStatus(UploadStatus.SCANNING.getValue());
        session.setCompletionTaskId(SCAN_TASK_ID);
        when(uploadSessionRepository.findForUpdateByUploadIdAndOwnerUserId("upload-123", OWNER_ID))
                .thenReturn(Optional.of(session));

        var result = service.completeSession(
                OWNER_ID,
                "upload-123",
                new CompleteFileUploadRequest(null, List.of(), null)
        );

        assertThat(result.status()).isEqualTo("SCANNING");
        assertThat(result.taskId()).isEqualTo(SCAN_TASK_ID);
        assertThat(result.fileNodeId()).isNull();
        verify(ingressScanTaskService, Mockito.never()).enqueueScanTask(any(), any(), any(), any());
        verify(uploadSessionRepository, Mockito.never()).save(any());
        verify(objectStorageClient, Mockito.never()).completeMultipartUpload(any(), any(), any());
    }

    // ── 新增测试 ──

    @Test
    void createSession_returnsValidSession() {
        // 验证创建上传会话时返回的元数据正确（文件名、大小、分片数等）
        long sizeBytes = 20L * 1024 * 1024;
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(OWNER_ID, "video.mp4"))
                .thenReturn(false);
        when(objectStorageClient.initiateMultipartUpload(any(), eq("video/mp4"))).thenReturn("upload-456");
        when(uploadSessionRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(uploadPartRepository.saveAll(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(objectStorageClient.createMultipartUploadPartUrl(any(), eq("upload-456"), anyInt(), any()))
                .thenReturn(URI.create("http://minio/part"));

        var response = service.createSession(OWNER_ID, new CreateFileUploadSessionRequest(
                null,
                "video.mp4",
                sizeBytes,
                "video/mp4",
                null,
                10 * 1024 * 1024,
                null,
                null
        ));

        // 验证会话元数据
        assertThat(response.uploadId()).isEqualTo("upload-456");
        assertThat(response.fileName()).isEqualTo("video.mp4");
        assertThat(response.sizeBytes()).isEqualTo(sizeBytes);
        assertThat(response.partSizeBytes()).isEqualTo(10 * 1024 * 1024);
        assertThat(response.totalParts()).isEqualTo(2);
        assertThat(response.mimeType()).isEqualTo("video/mp4");
        assertThat(response.status()).isEqualTo("CREATED");
        assertThat(response.parts()).hasSize(2);
        verify(storageQuotaService).reserve(
                eq(OWNER_ID),
                eq("UPLOAD"),
                any(UUID.class),
                eq(sizeBytes),
                any(Instant.class)
        );
    }

    @Test
    void createSession_throwsWhenFileTooLarge() {
        // 验证文件大小超出配额时拒绝创建上传会话
        long oversizedBytes = 100L * 1024 * 1024;
        Mockito.doThrow(new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "存储配额不足"))
                .when(storageQuotaService).reserve(
                        eq(OWNER_ID),
                        eq("UPLOAD"),
                        any(UUID.class),
                        eq(oversizedBytes),
                        any(Instant.class)
                );

        assertThatThrownBy(() -> service.createSession(OWNER_ID, new CreateFileUploadSessionRequest(
                null,
                "huge-file.bin",
                oversizedBytes,
                "application/octet-stream",
                null,
                null,
                null,
                null
        ))).isInstanceOf(BusinessException.class)
                .hasMessageContaining("存储配额不足");

        // 不应调用对象存储初始化
        verify(objectStorageClient, Mockito.never()).initiateMultipartUpload(any(), any());
    }

    @Test
    void completeSession_throwsWhenPartsIncomplete() {
        // 验证存在未完成分片时拒绝完成上传会话
        FileUploadSession session = session();
        session.setTotalParts(2);
        session.setUploadedParts(1);
        FileUploadPart completedPart = part(1, "COMPLETED", "etag-1");
        FileUploadPart pendingPart = part(2, "PENDING", null);

        when(uploadSessionRepository.findByUploadIdAndOwnerUserId("upload-123", OWNER_ID))
                .thenReturn(Optional.of(session));
        when(uploadSessionRepository.findForUpdateByUploadIdAndOwnerUserId("upload-123", OWNER_ID))
                .thenReturn(Optional.of(session));
        when(uploadPartRepository.findByUploadSessionIdOrderByPartNumber(SESSION_ID))
                .thenReturn(List.of(completedPart, pendingPart));

        assertThatThrownBy(() -> service.completeSession(OWNER_ID, "upload-123",
                new CompleteFileUploadRequest(null, List.of(), null)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("存在未完成的上传分片");

        // 不应调用对象存储完成操作
        verify(objectStorageClient, Mockito.never()).completeMultipartUpload(any(), any(), any());
    }

    @Test
    void cancelCompletedSessionIsIdempotent() {
        FileUploadSession session = session();
        session.setStatus(UploadStatus.COMPLETED.getValue());
        when(uploadSessionRepository.findForUpdateByUploadIdAndOwnerUserId("upload-123", OWNER_ID))
                .thenReturn(Optional.of(session));

        service.cancelSession(OWNER_ID, "upload-123");

        verify(uploadPartRepository, Mockito.never()).deleteByUploadSessionId(SESSION_ID);
        verify(uploadSessionRepository, Mockito.never()).delete(session);
        verify(objectStorageClient, Mockito.never()).objectExists(any());
        verify(objectStorageClient, Mockito.never()).removeObject(any());
        verify(objectStorageClient, Mockito.never()).abortMultipartUpload(any(), any());
    }

    @Test
    void completeCompletedSessionReturnsExistingResultWithoutMutatingSession() {
        FileUploadSession session = session();
        session.setStatus(UploadStatus.COMPLETED.getValue());
        session.setResultFileNodeId(FILE_NODE_ID);
        session.setCompletionTaskId(MEDIA_TASK_ID);
        when(uploadSessionRepository.findForUpdateByUploadIdAndOwnerUserId("upload-123", OWNER_ID))
                .thenReturn(Optional.of(session));

        var result = service.completeSession(
                OWNER_ID,
                "upload-123",
                new CompleteFileUploadRequest(null, List.of(), null)
        );

        assertThat(result.status()).isEqualTo("COMPLETED");
        assertThat(result.fileNodeId()).isEqualTo(FILE_NODE_ID);
        assertThat(result.taskId()).isEqualTo(MEDIA_TASK_ID);
        verify(uploadSessionRepository, Mockito.never()).save(any());
        verify(objectStorageClient, Mockito.never()).copyObject(any(), any());
    }

    private FileUploadSession session() {

        FileUploadSession session = new FileUploadSession();
        session.setId(SESSION_ID);
        session.setOwnerUserId(OWNER_ID);
        session.setFileName("demo.pdf");
        session.setTotalSizeBytes(512);
        session.setPartSizeBytes(512);
        session.setTotalParts(1);
        session.setUploadedParts(0);
        session.setMimeType("application/pdf");
        session.setStatus("CREATED");
        session.setUploadId("upload-123");
        session.setTargetBucket("user-files");
        session.setTargetObjectKey("users/1/uploads/demo.pdf");
        session.setQuotaReservationId(QUOTA_RESERVATION_ID);
        session.setExpiresAt(Instant.now().plusSeconds(600));
        return session;
    }

    private FileNode fileNode(String name, String mimeType, long sizeBytes) {
        FileNode file = new FileNode();
        file.setId(FILE_NODE_ID);
        file.setOwnerUserId(OWNER_ID);
        file.setNodeType("FILE");
        file.setName(name);
        file.setNormalizedPath("/" + name);
        file.setMimeType(mimeType);
        file.setSizeBytes(sizeBytes);
        file.setCurrentObjectId(FILE_OBJECT_ID);
        file.setSpaceType(SpaceType.PERSONAL);
        return file;
    }

    private FileUploadPart part(int partNumber, String status, String eTag) {
        FileUploadPart part = new FileUploadPart();
        part.setUploadSessionId(SESSION_ID);
        part.setOwnerUserId(OWNER_ID);
        part.setPartNumber(partNumber);
        part.setSizeBytes(512);
        part.setStatus(status);
        part.setETag(eTag);
        return part;
    }
}
