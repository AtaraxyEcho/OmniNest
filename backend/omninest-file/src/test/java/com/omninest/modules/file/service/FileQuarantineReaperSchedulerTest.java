package com.omninest.modules.file.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.FileIngressItem;
import com.omninest.modules.file.domain.FileIngressStatus;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.repository.FileIngressItemRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.PageImpl;

/**
 * 隔离滞留对象回收调度测试。
 *
 * @author OmniNest
 */
class FileQuarantineReaperSchedulerTest {
    private static final UUID OWNER_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID SESSION_ID = UUID.fromString("22222222-2222-2222-2222-222222222223");
    private static final UUID ASSET_ID = UUID.fromString("22222222-2222-2222-2222-222222222224");

    private FileIngressItemRepository ingressItemRepository;
    private ObjectStorageClient objectStorageClient;
    private FileUploadCancellationService fileUploadCancellationService;
    private FileUploadSessionRepository uploadSessionRepository;
    private StorageQuotaService storageQuotaService;
    private FileQuarantineReaperScheduler scheduler;

    @BeforeEach
    void setUp() {
        ingressItemRepository = mock(FileIngressItemRepository.class);
        objectStorageClient = mock(ObjectStorageClient.class);
        fileUploadCancellationService = mock(FileUploadCancellationService.class);
        uploadSessionRepository = mock(FileUploadSessionRepository.class);
        storageQuotaService = mock(StorageQuotaService.class);
        ConfigValueProvider configValueProvider = mock(ConfigValueProvider.class);
        RuntimeConfigCache runtimeConfigCache = mock(RuntimeConfigCache.class);
        when(runtimeConfigCache.get(anyString())).thenReturn(Optional.empty());
        when(configValueProvider.findByKey(anyString())).thenReturn(Optional.empty());
        scheduler = new FileQuarantineReaperScheduler(
                ingressItemRepository,
                objectStorageClient,
                fileUploadCancellationService,
                uploadSessionRepository,
                storageQuotaService,
                configValueProvider,
                runtimeConfigCache
        );
    }

    @Test
    void reapsExpiredTerminalItemsAndCancelsLinkedSession() {
        FileIngressItem item = item(FileIngressStatus.REJECTED);
        FileUploadSession session = new FileUploadSession();
        session.setId(SESSION_ID);
        session.setOwnerUserId(OWNER_ID);
        session.setUploadId("upload-123");
        session.setStatus("SCANNING");
        when(ingressItemRepository.findByStatusInAndUpdatedAtBefore(any(), any(Instant.class), any()))
                .thenReturn(new PageImpl<>(List.of(item)));
        when(ingressItemRepository.deleteByIdAndStatusIn(any(), any())).thenReturn(1);
        when(uploadSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session));

        scheduler.reapExpiredQuarantineItems();

        verify(objectStorageClient).removeObject(any(ObjectStorageKey.class));
        verify(ingressItemRepository).deleteByIdAndStatusIn(eq(item.getId()), any());
        verify(fileUploadCancellationService).forceCancelForCleanup(OWNER_ID, "upload-123");
        verify(storageQuotaService, never()).releaseReservation(anyString(), any());
    }

    @Test
    void skipsCancelForCompletedSession() {
        FileIngressItem item = item(FileIngressStatus.FAILED);
        FileUploadSession session = new FileUploadSession();
        session.setId(SESSION_ID);
        session.setOwnerUserId(OWNER_ID);
        session.setUploadId("upload-123");
        session.setStatus("COMPLETED");
        when(ingressItemRepository.findByStatusInAndUpdatedAtBefore(any(), any(Instant.class), any()))
                .thenReturn(new PageImpl<>(List.of(item)));
        when(ingressItemRepository.deleteByIdAndStatusIn(any(), any())).thenReturn(1);
        when(uploadSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session));

        scheduler.reapExpiredQuarantineItems();

        verify(objectStorageClient).removeObject(any(ObjectStorageKey.class));
        verify(fileUploadCancellationService, never()).forceCancelForCleanup(any(), anyString());
    }

    @Test
    void skipsObjectsWhenRecordWasPromotedBetweenQueryAndDelete() {
        FileIngressItem item = item(FileIngressStatus.SCANNING);
        when(ingressItemRepository.findByStatusInAndUpdatedAtBefore(any(), any(Instant.class), any()))
                .thenReturn(new PageImpl<>(List.of(item)));
        when(ingressItemRepository.deleteByIdAndStatusIn(any(), any())).thenReturn(0);

        scheduler.reapExpiredQuarantineItems();

        verify(objectStorageClient, never()).removeObject(any(ObjectStorageKey.class));
        verify(fileUploadCancellationService, never()).forceCancelForCleanup(any(), anyString());
        verify(storageQuotaService, never()).releaseReservation(anyString(), any());
    }

    @Test
    void releasesBackdropReservationForReapedIngress() {
        FileIngressItem item = item(FileIngressStatus.FAILED);
        item.setSourceType("BACKDROP");
        item.setSourceTaskId(ASSET_ID);
        item.setUploadSessionId(null);
        when(ingressItemRepository.findByStatusInAndUpdatedAtBefore(any(), any(Instant.class), any()))
                .thenReturn(new PageImpl<>(List.of(item)));
        when(ingressItemRepository.deleteByIdAndStatusIn(any(), any())).thenReturn(1);

        scheduler.reapExpiredQuarantineItems();

        verify(storageQuotaService).releaseReservation("BACKDROP_UPLOAD", ASSET_ID);
    }

    @Test
    void continuesWhenSingleItemReapFails() {
        FileIngressItem failed = item(FileIngressStatus.FAILED);
        FileIngressItem rejected = item(FileIngressStatus.REJECTED);
        rejected.setId(UUID.randomUUID());
        rejected.setUploadSessionId(null);
        rejected.setSourceType("UPLOAD");
        when(ingressItemRepository.findByStatusInAndUpdatedAtBefore(any(), any(Instant.class), any()))
                .thenReturn(new PageImpl<>(List.of(failed, rejected)));
        when(ingressItemRepository.deleteByIdAndStatusIn(eq(failed.getId()), any()))
                .thenThrow(new RuntimeException("database down"));
        when(ingressItemRepository.deleteByIdAndStatusIn(eq(rejected.getId()), any())).thenReturn(1);

        scheduler.reapExpiredQuarantineItems();

        verify(ingressItemRepository).deleteByIdAndStatusIn(eq(rejected.getId()), any());
        verify(objectStorageClient).removeObject(any(ObjectStorageKey.class));
    }

    private FileIngressItem item(FileIngressStatus status) {
        FileIngressItem item = new FileIngressItem();
        item.setId(UUID.randomUUID());
        item.setOwnerUserId(OWNER_ID);
        item.setSourceType("UPLOAD");
        item.setUploadSessionId(SESSION_ID);
        item.setQuarantineBucket("file-quarantine");
        item.setQuarantineObjectKey("uploads/1/demo.pdf");
        item.setStatus(status);
        item.setUpdatedAt(Instant.now().minusSeconds(60));
        return item;
    }
}
