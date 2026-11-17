package com.omninest.worker.index;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.dto.FileObjectDescriptor;
import com.omninest.modules.file.event.FileRestoredEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.photos.service.PhotoThumbnailService;
import java.io.ByteArrayInputStream;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 文件恢复源对象校验和缩略图修复测试。
 *
 * @author OmniNest
 */
class FileRestoreDerivedAssetServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID FILE_OBJECT_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final ObjectStorageKey OBJECT_KEY = new ObjectStorageKey("files", "owner/photo.jpg");

    private final FileLifecycleGuard lifecycleGuard = Mockito.mock(FileLifecycleGuard.class);
    private final FileMetadataQueryService metadataQueryService = Mockito.mock(FileMetadataQueryService.class);
    private final ObjectStorageClient objectStorageClient = Mockito.mock(ObjectStorageClient.class);
    private final PhotoThumbnailService thumbnailService = Mockito.mock(PhotoThumbnailService.class);
    private final FileRestoreDerivedAssetService service = new FileRestoreDerivedAssetService(
            lifecycleGuard,
            metadataQueryService,
            objectStorageClient,
            thumbnailService
    );

    @Test
    void validateAndRepairRegeneratesMissingImageThumbnail() {
        FileRestoredEvent event = event();
        stubSource("image/jpeg", true);
        Mockito.when(thumbnailService.hasStoredThumbnail(OWNER_ID, FILE_NODE_ID)).thenReturn(false);
        Mockito.when(objectStorageClient.getObject(OBJECT_KEY))
                .thenReturn(new ByteArrayInputStream(new byte[]{1, 2, 3}));
        Mockito.when(thumbnailService.generateAndStore(
                Mockito.eq(OWNER_ID),
                Mockito.eq(FILE_NODE_ID),
                Mockito.any(),
                Mockito.eq("photo.jpg")
        )).thenReturn(UUID.randomUUID());

        service.validateAndRepair(event);

        Mockito.verify(thumbnailService).generateAndStore(
                Mockito.eq(OWNER_ID),
                Mockito.eq(FILE_NODE_ID),
                Mockito.any(),
                Mockito.eq("photo.jpg")
        );
    }

    @Test
    void validateAndRepairSkipsExistingThumbnail() {
        FileRestoredEvent event = event();
        stubSource("image/jpeg", true);
        Mockito.when(thumbnailService.hasStoredThumbnail(OWNER_ID, FILE_NODE_ID)).thenReturn(true);

        service.validateAndRepair(event);

        Mockito.verify(thumbnailService, Mockito.never()).generateAndStore(
                Mockito.any(), Mockito.any(), Mockito.any(), Mockito.any()
        );
    }

    @Test
    void validateAndRepairRejectsMissingPhysicalSourceObject() {
        FileRestoredEvent event = event();
        stubSource("image/jpeg", false);

        assertThatThrownBy(() -> service.validateAndRepair(event))
                .isInstanceOf(BusinessException.class)
                .satisfies(exception -> {
                    BusinessException businessException = (BusinessException) exception;
                    assertThat(businessException.errorCode())
                            .isEqualTo(ErrorCode.FILE_OBJECT_MISSING);
                });
    }

    private void stubSource(String mimeType, boolean objectExists) {
        Mockito.when(lifecycleGuard.requireOwnedWritable(OWNER_ID, FILE_NODE_ID))
                .thenReturn(file(mimeType));
        Mockito.when(metadataQueryService.findObjectById(FILE_OBJECT_ID))
                .thenReturn(Optional.of(fileObject()));
        Mockito.when(objectStorageClient.objectExists(OBJECT_KEY)).thenReturn(objectExists);
    }

    private FileDescriptor file(String mimeType) {
        return new FileDescriptor(
                FILE_NODE_ID,
                OWNER_ID,
                null,
                "FILE",
                "photo.jpg",
                "/photo.jpg",
                mimeType,
                1024L,
                FILE_OBJECT_ID,
                "LOCAL",
                false,
                false,
                SpaceType.PERSONAL,
                OWNER_ID,
                Instant.now(),
                Instant.now()
        );
    }

    private FileObjectDescriptor fileObject() {
        return new FileObjectDescriptor(
                FILE_OBJECT_ID,
                OBJECT_KEY.bucket(),
                OBJECT_KEY.objectKey(),
                "sha256",
                1024L,
                "image/jpeg"
        );
    }

    private FileRestoredEvent event() {
        return new FileRestoredEvent(FILE_NODE_ID, OWNER_ID, "photo.jpg", Instant.now());
    }
}
