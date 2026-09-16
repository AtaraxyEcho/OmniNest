package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.MalwareScanGateway.Status;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.file.domain.FileIngressItem;
import com.omninest.modules.file.domain.FileIngressStatus;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.UploadStatus;
import com.omninest.modules.file.event.FileSecurityScanRequestedEvent;
import com.omninest.modules.file.repository.FileIngressItemRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.file.service.FileIngressSafetyService.InspectionResult;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 文件安全扫描晋升服务测试。
 *
 * @author OmniNest
 */
class FileIngressPromotionServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final UUID SESSION_ID = UUID.fromString("00000000-0000-0000-0000-000000000002");
    private static final UUID INGRESS_ID = UUID.fromString("00000000-0000-0000-0000-000000000003");
    private static final String SHA256 = "a".repeat(64);

    private FileIngressItemRepository ingressItemRepository;
    private FileIngressLifecycleService ingressLifecycleService;
    private FileIngressSafetyService ingressSafetyService;
    private FileUploadSessionRepository uploadSessionRepository;
    private FileObjectRepository fileObjectRepository;
    private FileNodeRepository fileNodeRepository;
    private FilePostProcessingTaskService postProcessingTaskService;
    private StorageQuotaService storageQuotaService;
    private ObjectStorageClient objectStorageClient;
    private NotificationPublisher notificationPublisher;
    private FileIngressPromotionService service;

    @BeforeEach
    void setUp() {
        ingressItemRepository = mock(FileIngressItemRepository.class);
        ingressLifecycleService = mock(FileIngressLifecycleService.class);
        ingressSafetyService = mock(FileIngressSafetyService.class);
        uploadSessionRepository = mock(FileUploadSessionRepository.class);
        fileObjectRepository = mock(FileObjectRepository.class);
        fileNodeRepository = mock(FileNodeRepository.class);
        FileManagerService fileManagerService = mock(FileManagerService.class);
        postProcessingTaskService = mock(FilePostProcessingTaskService.class);
        FileContentChangePublisher fileContentChangePublisher = new FileContentChangePublisher(postProcessingTaskService);
        storageQuotaService = mock(StorageQuotaService.class);
        objectStorageClient = mock(ObjectStorageClient.class);
        UserSyncEventRecorder syncEventRecorder = mock(UserSyncEventRecorder.class);
        notificationPublisher = mock(NotificationPublisher.class);
        TransactionTemplate transactionTemplate =
                new TransactionTemplate(mock(PlatformTransactionManager.class));
        service = new FileIngressPromotionService(
                ingressItemRepository,
                ingressLifecycleService,
                ingressSafetyService,
                uploadSessionRepository,
                fileObjectRepository,
                fileNodeRepository,
                fileManagerService,
                fileContentChangePublisher,
                storageQuotaService,
                objectStorageClient,
                syncEventRecorder,
                notificationPublisher,
                transactionTemplate
        );
    }

    @Test
    void processPromotesCleanIngressAndCompletesSession() {
        FileIngressItem item = ingressItem(FileIngressStatus.PENDING_SCAN, null);
        FileUploadSession session = session();
        when(ingressItemRepository.findById(INGRESS_ID)).thenReturn(Optional.of(item));
        when(uploadSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session));
        when(ingressSafetyService.inspect(any(ObjectStorageKey.class), anyLong(), anyString(), any(UUID.class)))
                .thenReturn(new InspectionResult(Status.CLEAN, "文件安全", SHA256));
        when(fileObjectRepository.save(any())).thenAnswer(invocation -> {
            FileObject object = invocation.getArgument(0);
            object.setId(UUID.randomUUID());
            return object;
        });
        when(fileNodeRepository.save(any())).thenAnswer(invocation -> {
            FileNode node = invocation.getArgument(0);
            node.setId(UUID.randomUUID());
            return node;
        });
        when(postProcessingTaskService.enqueueMediaAutoImport(any())).thenReturn(UUID.randomUUID());

        service.process(event(null));

        assertThat(session.getStatus()).isEqualTo("COMPLETED");
        verify(ingressLifecycleService).markScanning(INGRESS_ID);
        verify(ingressLifecycleService).markClean(INGRESS_ID, SHA256);
        verify(ingressLifecycleService).markAvailable(eq(INGRESS_ID), any(UUID.class));
        verify(objectStorageClient).copyObject(any(), any());
        verify(objectStorageClient).removeObject(any(ObjectStorageKey.class));
        verify(storageQuotaService).settleReservation("UPLOAD", SESSION_ID, 512L);
        verify(postProcessingTaskService).enqueueMediaAutoImport(any());
        verify(notificationPublisher, never()).notifyOrLog(any(), anyString(), anyString(), anyString(), any());
    }

    @Test
    void processSkipsAlreadyAvailableIngress() {
        FileIngressItem item = ingressItem(FileIngressStatus.AVAILABLE, SHA256);
        when(ingressItemRepository.findById(INGRESS_ID)).thenReturn(Optional.of(item));

        service.process(event(null));

        verify(ingressLifecycleService, never()).markScanning(any());
        verify(ingressSafetyService, never()).inspect(any(), anyLong(), anyString(), any());
    }

    @Test
    void processResumesFromCleanWithoutRescan() {
        FileIngressItem item = ingressItem(FileIngressStatus.CLEAN, SHA256);
        FileUploadSession session = session();
        when(ingressItemRepository.findById(INGRESS_ID)).thenReturn(Optional.of(item));
        when(uploadSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session));
        when(fileObjectRepository.save(any())).thenAnswer(invocation -> {
            FileObject object = invocation.getArgument(0);
            object.setId(UUID.randomUUID());
            return object;
        });
        when(fileNodeRepository.save(any())).thenAnswer(invocation -> {
            FileNode node = invocation.getArgument(0);
            node.setId(UUID.randomUUID());
            return node;
        });
        when(postProcessingTaskService.enqueueMediaAutoImport(any())).thenReturn(UUID.randomUUID());

        service.process(event(null));

        verify(ingressLifecycleService, never()).markScanning(any());
        verify(ingressSafetyService, never()).inspect(any(), anyLong(), anyString(), any());
        verify(ingressLifecycleService).markAvailable(eq(INGRESS_ID), any(UUID.class));
        assertThat(session.getStatus()).isEqualTo("COMPLETED");
    }

    @Test
    void processRejectsInfectedFileAndSettlesSession() {
        FileIngressItem item = ingressItem(FileIngressStatus.PENDING_SCAN, null);
        FileUploadSession session = session();
        when(ingressItemRepository.findById(INGRESS_ID)).thenReturn(Optional.of(item));
        when(uploadSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session));
        when(ingressSafetyService.inspect(any(ObjectStorageKey.class), anyLong(), anyString(), any(UUID.class)))
                .thenReturn(new InspectionResult(Status.INFECTED, "Eicar-Signature FOUND", SHA256));

        assertThatThrownBy(() -> service.process(event(null)))
                .isInstanceOf(FileIngressRejectedException.class);

        verify(ingressLifecycleService).markFailed(eq(INGRESS_ID), eq(true), anyString(), anyString());
        assertThat(session.getStatus()).isEqualTo("REJECTED");
        assertThat(session.getQuotaReservationId()).isNull();
        verify(storageQuotaService).releaseReservation("UPLOAD", SESSION_ID);
        verify(notificationPublisher).notifyOrLog(any(), anyString(), anyString(), anyString(), any());
        verify(objectStorageClient, never()).copyObject(any(), any());
        verify(fileNodeRepository, never()).save(any());
    }

    @Test
    void processRejectsShaMismatch() {
        FileIngressItem item = ingressItem(FileIngressStatus.PENDING_SCAN, null);
        FileUploadSession session = session();
        when(ingressItemRepository.findById(INGRESS_ID)).thenReturn(Optional.of(item));
        when(uploadSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session));
        when(ingressSafetyService.inspect(any(ObjectStorageKey.class), anyLong(), anyString(), any(UUID.class)))
                .thenReturn(new InspectionResult(Status.CLEAN, "文件安全", SHA256));

        assertThatThrownBy(() -> service.process(event("b".repeat(64))))
                .isInstanceOf(FileIngressRejectedException.class);

        verify(ingressLifecycleService).markFailed(eq(INGRESS_ID), eq(false), anyString(), anyString());
        assertThat(session.getStatus()).isEqualTo("REJECTED");
        verify(objectStorageClient, never()).copyObject(any(), any());
    }

    @Test
    void processRetriesScanErrors() {
        FileIngressItem item = ingressItem(FileIngressStatus.PENDING_SCAN, null);
        when(ingressItemRepository.findById(INGRESS_ID)).thenReturn(Optional.of(item));
        when(ingressSafetyService.inspect(any(ObjectStorageKey.class), anyLong(), anyString(), any(UUID.class)))
                .thenThrow(new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "ClamAV 安全扫描不可用，文件保持隔离"));

        assertThatCode(() -> service.process(event(null)))
                .isInstanceOf(BusinessException.class);

        verify(ingressLifecycleService).markScanning(INGRESS_ID);
        verify(ingressLifecycleService, never()).markFailed(any(), anyBoolean(), anyString(), anyString());
        verify(ingressLifecycleService, never()).markClean(any(), anyString());
        verify(notificationPublisher, never()).notifyOrLog(any(), anyString(), anyString(), anyString(), any());
    }

    @Test
    void processSkipsMissingIngressItem() {
        when(ingressItemRepository.findById(INGRESS_ID)).thenReturn(Optional.empty());

        service.process(event(null));

        verify(ingressLifecycleService, never()).markScanning(any());
        verify(ingressSafetyService, never()).inspect(any(), anyLong(), anyString(), any());
        Mockito.verifyNoInteractions(objectStorageClient);
    }

    private FileSecurityScanRequestedEvent event(String declaredSha256) {
        return new FileSecurityScanRequestedEvent(UUID.randomUUID(), OWNER_ID, INGRESS_ID, null, declaredSha256);
    }

    private FileIngressItem ingressItem(FileIngressStatus status, String sha256) {
        FileIngressItem item = new FileIngressItem();
        item.setId(INGRESS_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setSourceType("UPLOAD");
        item.setUploadSessionId(SESSION_ID);
        item.setQuarantineBucket("file-quarantine");
        item.setQuarantineObjectKey("uploads/1/demo.pdf");
        item.setTargetBucket("user-files");
        item.setTargetObjectKey("users/1/files/demo.pdf");
        item.setTargetParentId(null);
        item.setTargetName("demo.pdf");
        item.setSizeBytes(512L);
        item.setMimeType("application/pdf");
        item.setStatus(status);
        item.setSha256(sha256);
        return item;
    }

    private FileUploadSession session() {
        FileUploadSession session = new FileUploadSession();
        session.setId(SESSION_ID);
        session.setOwnerUserId(OWNER_ID);
        session.setFileName("demo.pdf");
        session.setTotalSizeBytes(512);
        session.setTotalParts(1);
        session.setMimeType("application/pdf");
        session.setStatus(UploadStatus.SCANNING.getValue());
        session.setQuotaReservationId(UUID.fromString("00000000-0000-0000-0000-000000000005"));
        session.setSpaceType(SpaceType.PERSONAL);
        return session;
    }
}
