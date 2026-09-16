package com.omninest.modules.file.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
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
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 隔离滞留对象回收调度测试。
 *
 * @author OmniNest
 */
class FileQuarantineReaperSchedulerTest {
    private static final UUID OWNER_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID SESSION_ID = UUID.fromString("22222222-2222-2222-2222-222222222223");

    private FileIngressItemRepository ingressItemRepository;
    private ObjectStorageClient objectStorageClient;
    private FileUploadSessionService fileUploadSessionService;
    private FileUploadSessionRepository uploadSessionRepository;
    private FileQuarantineReaperScheduler scheduler;

    @BeforeEach
    void setUp() {
        ingressItemRepository = mock(FileIngressItemRepository.class);
        objectStorageClient = mock(ObjectStorageClient.class);
        fileUploadSessionService = mock(FileUploadSessionService.class);
        uploadSessionRepository = mock(FileUploadSessionRepository.class);
        ConfigValueProvider configValueProvider = mock(ConfigValueProvider.class);
        RuntimeConfigCache runtimeConfigCache = mock(RuntimeConfigCache.class);
        when(runtimeConfigCache.get(anyString())).thenReturn(java.util.Optional.empty());
        when(configValueProvider.findByKey(anyString())).thenReturn(java.util.Optional.empty());
        scheduler = new FileQuarantineReaperScheduler(
                ingressItemRepository,
                objectStorageClient,
                fileUploadSessionService,
                uploadSessionRepository,
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
        when(ingressItemRepository.findByStatusInAndUpdatedAtBefore(any(), any(Instant.class)))
                .thenReturn(List.of(item));
        when(uploadSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session));

        scheduler.reapExpiredQuarantineItems();

        verify(objectStorageClient).removeObject(any(ObjectStorageKey.class));
        verify(ingressItemRepository).delete(item);
        verify(fileUploadSessionService).cancelSession(OWNER_ID, "upload-123");
    }

    @Test
    void skipsCancelForCompletedSession() {
        FileIngressItem item = item(FileIngressStatus.FAILED);
        FileUploadSession session = new FileUploadSession();
        session.setId(SESSION_ID);
        session.setOwnerUserId(OWNER_ID);
        session.setUploadId("upload-123");
        session.setStatus("COMPLETED");
        when(ingressItemRepository.findByStatusInAndUpdatedAtBefore(any(), any(Instant.class)))
                .thenReturn(List.of(item));
        when(uploadSessionRepository.findById(SESSION_ID)).thenReturn(Optional.of(session));

        scheduler.reapExpiredQuarantineItems();

        verify(objectStorageClient).removeObject(any(ObjectStorageKey.class));
        verify(ingressItemRepository).delete(item);
        verify(fileUploadSessionService, never()).cancelSession(any(), anyString());
    }

    @Test
    void continuesWhenSingleItemReapFails() {
        FileIngressItem failed = item(FileIngressStatus.FAILED);
        FileIngressItem rejected = item(FileIngressStatus.REJECTED);
        rejected.setUploadSessionId(null);
        when(ingressItemRepository.findByStatusInAndUpdatedAtBefore(any(), any(Instant.class)))
                .thenReturn(List.of(failed, rejected));
        org.mockito.Mockito.doThrow(new RuntimeException("minio down"))
                .doNothing()
                .when(objectStorageClient).removeObject(any(ObjectStorageKey.class));

        scheduler.reapExpiredQuarantineItems();

        verify(ingressItemRepository).delete(rejected);
        verify(ingressItemRepository, never()).delete(failed);
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
