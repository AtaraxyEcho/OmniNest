package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.config.PhotoMediaLimitsProperties;
import com.omninest.modules.photos.domain.PhotoEditVersion;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.dto.PhotoDtos.EditRequest;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoEditVersionDto;
import com.omninest.modules.photos.repository.PhotoEditVersionRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.function.Consumer;
import java.awt.image.BufferedImage;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;

/**
 * 照片编辑文件化输入输出和临时文件生命周期测试。
 *
 * @author OmniNest
 */
class PhotoEditServiceTest {

    private final PhotoEditVersionRepository editVersionRepository = mock(PhotoEditVersionRepository.class);
    private final PhotoItemRepository photoItemRepository = mock(PhotoItemRepository.class);
    private final DerivedAssetStorageService storageService = mock(DerivedAssetStorageService.class);
    private final MediaSyncEventService syncEventService = mock(MediaSyncEventService.class);
    private final PhotoSourceFileService sourceFileService = mock(PhotoSourceFileService.class);
    private final PhotoInputGuard inputGuard = new PhotoInputGuard(new PhotoMediaLimitsProperties());
    private final StorageQuotaService storageQuotaService = mock(StorageQuotaService.class);
    private final FileMetadataQueryService fileMetadataQueryService = mock(FileMetadataQueryService.class);
    private final PlatformTransactionManager txManager = mock(PlatformTransactionManager.class);
    private final TransactionTemplate transactionTemplate = new TransactionTemplate(txManager);
    private final PhotoEditService service = new PhotoEditService(
            editVersionRepository,
            photoItemRepository,
            storageService,
            syncEventService,
            sourceFileService,
            inputGuard,
            storageQuotaService,
            fileMetadataQueryService,
            transactionTemplate,
            5,
            2
    );

    {
        when(txManager.getTransaction(any())).thenReturn(new SimpleTransactionStatus());
    }

    @Test
    void applyEditStoresFileOutputAndDeletesTemporaryFiles() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID sourceFileId = UUID.randomUUID();
        UUID editedFileId = UUID.randomUUID();
        Path sourceFile = createImage();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(sourceFileId);
        AtomicReference<Path> storedPath = new AtomicReference<>();
        when(photoItemRepository.findById(photoId)).thenReturn(Optional.of(photo));
        when(editVersionRepository.countByPhotoId(photoId)).thenReturn(0L);
        when(editVersionRepository.findByPhotoIdOrderByVersionNumberDesc(photoId)).thenReturn(List.of());
        when(sourceFileService.stageOwned(ownerUserId, sourceFileId))
                .thenReturn(new PhotoSourceFileService.StagedPhotoFile(
                        sourceFile,
                        "photo.png",
                        Files.size(sourceFile),
                        "image/png",
                        false
                ));
        when(storageService.store(
                eq(ownerUserId),
                anyString(),
                eq(photoId),
                anyString(),
                anyString(),
                eq("image/jpeg"),
                any(Path.class)
        )).thenAnswer(invocation -> {
            Path output = invocation.getArgument(6);
            storedPath.set(output);
            assertThat(output).exists();
            assertThat(Files.size(output)).isPositive();
            return editedFileId;
        });

        PhotoEditVersionDto result = service.applyEdit(
                ownerUserId,
                photoId,
                new EditRequest("BRIGHTNESS", Map.of("factor", 1.1))
        );

        assertThat(result.versionNumber()).isEqualTo(1);
        assertThat(photo.getCoverFileId()).isEqualTo(editedFileId);
        assertThat(sourceFile).doesNotExist();
        assertThat(storedPath.get()).doesNotExist();
    }

    @Test
    void applyEditedImageValidatesPayloadAndChargesQuota() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID editedFileId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        when(photoItemRepository.findById(photoId)).thenReturn(Optional.of(photo));
        when(editVersionRepository.countByPhotoId(photoId)).thenReturn(0L);
        when(editVersionRepository.findByPhotoIdOrderByVersionNumberDesc(photoId)).thenReturn(List.of());

        byte[] jpeg = jpegBytes();
        AtomicReference<Path> storedPath = new AtomicReference<>();
        when(storageService.store(
                eq(ownerUserId),
                anyString(),
                eq(photoId),
                anyString(),
                anyString(),
                eq("image/jpeg"),
                any(Path.class)
        )).thenAnswer(invocation -> {
            Path staged = invocation.getArgument(6);
            storedPath.set(staged);
            assertThat(staged).exists();
            return editedFileId;
        });

        PhotoEditVersionDto result = applyEditedImage(ownerUserId, photoId, jpeg);

        assertThat(result.versionNumber()).isEqualTo(1);
        verify(storageQuotaService).chargeUsage(ownerUserId, jpeg.length);
        assertThat(storedPath.get()).doesNotExist();
    }

    @Test
    void applyEditedImageRejectsDeclaredOversizeBeforeReadingBody() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        when(photoItemRepository.findById(photoId)).thenReturn(Optional.of(photo));
        PhotoEditService limited = serviceWithMaxBytes(8);

        assertThatThrownBy(() -> limited.applyEditedImage(
                ownerUserId, photoId, 9, new ByteArrayInputStream(new byte[9])))
                .isInstanceOfSatisfying(BusinessException.class,
                        exception -> assertThat(exception.errorCode()).isEqualTo(ErrorCode.PARAM_ERROR));
        verify(storageService, never()).store(
                any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
    }

    @Test
    void applyEditedImageStopsStreamingAtLimitWhenLengthUnknown() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        when(photoItemRepository.findById(photoId)).thenReturn(Optional.of(photo));
        PhotoEditService limited = serviceWithMaxBytes(8);

        assertThatThrownBy(() -> limited.applyEditedImage(
                ownerUserId, photoId, -1, new ByteArrayInputStream(new byte[64])))
                .isInstanceOfSatisfying(BusinessException.class,
                        exception -> assertThat(exception.errorCode()).isEqualTo(ErrorCode.PARAM_ERROR));
        verify(storageService, never()).store(
                any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
    }

    @Test
    void applyEditedImageRejectsNonImagePayloadClaimedAsJpeg() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        when(photoItemRepository.findById(photoId)).thenReturn(Optional.of(photo));
        when(editVersionRepository.countByPhotoId(photoId)).thenReturn(0L);

        byte[] payload = "这不是图片，只是自称 JPEG 的文本".getBytes(StandardCharsets.UTF_8);

        assertThatThrownBy(() -> applyEditedImage(ownerUserId, photoId, payload))
                .isInstanceOf(BusinessException.class);
        verify(storageService, never()).store(
                any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
        verify(storageQuotaService, never()).incrementUsage(any(), anyLong());
    }

    @Test
    void enforceMaxVersionsRefundsQuotaWhenNodePhysicallyDeleted() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID evictedFileId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        when(photoItemRepository.findById(photoId)).thenReturn(Optional.of(photo));
        when(editVersionRepository.countByPhotoId(photoId)).thenReturn(6L);
        when(editVersionRepository.findByPhotoIdOrderByVersionNumberDesc(photoId))
                .thenReturn(versionsWithEvictedFile(photoId, ownerUserId, evictedFileId));
        when(fileMetadataQueryService.findById(evictedFileId))
                .thenReturn(Optional.of(descriptorWithSize(ownerUserId, evictedFileId, 4096L)));
        when(storageService.deleteOwned(ownerUserId, evictedFileId)).thenReturn(true);
        when(storageService.store(
                eq(ownerUserId), anyString(), eq(photoId), anyString(), anyString(),
                eq("image/jpeg"), any(Path.class)
        )).thenReturn(UUID.randomUUID());

        applyEditedImage(ownerUserId, photoId, jpegBytes());

        // 节点行消失后必须按写入时口径退还字节，否则实时用量永久虚高。
        verify(storageQuotaService).decrementUsage(ownerUserId, 4096L);
    }

    @Test
    void enforceMaxVersionsDoesNotRefundWhenDeleteOwnedFails() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID evictedFileId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        when(photoItemRepository.findById(photoId)).thenReturn(Optional.of(photo));
        when(editVersionRepository.countByPhotoId(photoId)).thenReturn(6L);
        when(editVersionRepository.findByPhotoIdOrderByVersionNumberDesc(photoId))
                .thenReturn(versionsWithEvictedFile(photoId, ownerUserId, evictedFileId));
        when(fileMetadataQueryService.findById(evictedFileId))
                .thenReturn(Optional.of(descriptorWithSize(ownerUserId, evictedFileId, 4096L)));
        when(storageService.deleteOwned(ownerUserId, evictedFileId)).thenReturn(false);
        when(storageService.store(
                eq(ownerUserId), anyString(), eq(photoId), anyString(), anyString(),
                eq("image/jpeg"), any(Path.class)
        )).thenReturn(UUID.randomUUID());

        applyEditedImage(ownerUserId, photoId, jpegBytes());

        // 节点未消失时不得退款，避免与每日配额对账双重扣减。
        verify(storageQuotaService, never()).decrementUsage(any(), anyLong());
    }

    @Test
    void rejectsConcurrentEditsWhenHeapHeavySlotsAreExhausted() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID sourceFileId = UUID.randomUUID();
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(sourceFileId);
        when(photoItemRepository.findById(photoId)).thenReturn(Optional.of(photo));
        when(editVersionRepository.countByPhotoId(photoId)).thenReturn(0L);
        when(editVersionRepository.findByPhotoIdOrderByVersionNumberDesc(photoId)).thenReturn(List.of());
        Path sourceFile = createImage();
        CountDownLatch staging = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        when(sourceFileService.stageOwned(ownerUserId, sourceFileId)).thenAnswer(invocation -> {
            staging.countDown();
            release.await(10, TimeUnit.SECONDS);
            return new PhotoSourceFileService.StagedPhotoFile(
                    sourceFile, "photo.png", Files.size(sourceFile), "image/png", false);
        });
        when(storageService.store(
                eq(ownerUserId), anyString(), eq(photoId), anyString(), anyString(),
                eq("image/jpeg"), any(Path.class)
        )).thenReturn(UUID.randomUUID());

        PhotoEditService singleSlotService = new PhotoEditService(
                editVersionRepository,
                photoItemRepository,
                storageService,
                syncEventService,
                sourceFileService,
                inputGuard,
                storageQuotaService,
                fileMetadataQueryService,
                transactionTemplate,
                5,
                1
        );
        ExecutorService executor = Executors.newSingleThreadExecutor();
        try {
            Future<PhotoEditVersionDto> running = executor.submit(() -> singleSlotService.applyEdit(
                    ownerUserId,
                    photoId,
                    new EditRequest("BRIGHTNESS", Map.of("factor", 1.1))
            ));
            assertThat(staging.await(5, TimeUnit.SECONDS)).isTrue();

            assertThatThrownBy(() -> singleSlotService.applyEdit(
                    ownerUserId,
                    photoId,
                    new EditRequest("BRIGHTNESS", Map.of("factor", 1.1))
            )).isInstanceOfSatisfying(BusinessException.class,
                    exception -> assertThat(exception.errorCode()).isEqualTo(ErrorCode.RATE_LIMITED));

            release.countDown();
            assertThat(running.get(10, TimeUnit.SECONDS).versionNumber()).isEqualTo(1);
        } finally {
            release.countDown();
            executor.shutdownNow();
            Files.deleteIfExists(sourceFile);
        }
    }

    private PhotoEditService serviceWithMaxBytes(long maxBytes) {
        PhotoMediaLimitsProperties limits = new PhotoMediaLimitsProperties();
        limits.setMaxStandardFileBytes(maxBytes);
        return new PhotoEditService(
                editVersionRepository,
                photoItemRepository,
                storageService,
                syncEventService,
                sourceFileService,
                new PhotoInputGuard(limits),
                storageQuotaService,
                fileMetadataQueryService,
                transactionTemplate,
                5,
                2
        );
    }

    private PhotoEditVersionDto applyEditedImage(UUID ownerUserId, UUID photoId, byte[] bytes) {
        return service.applyEditedImage(
                ownerUserId, photoId, bytes.length, new ByteArrayInputStream(bytes));
    }

    private List<PhotoEditVersion> versionsWithEvictedFile(
            UUID photoId, UUID ownerUserId, UUID evictedFileId) {
        // 降序 6 行，上限 5：最后一行（版本 1）携带 evictedFileId，被逐出。
        List<PhotoEditVersion> versions = new ArrayList<>();
        for (int number = 6; number >= 1; number--) {
            PhotoEditVersion version = new PhotoEditVersion();
            version.setId(UUID.randomUUID());
            version.setOwnerUserId(ownerUserId);
            version.setPhotoId(photoId);
            version.setVersionNumber(number);
            version.setEditType("EXTERNAL");
            version.setFileId(number == 1 ? evictedFileId : UUID.randomUUID());
            version.setCreatedAt(Instant.now());
            versions.add(version);
        }
        return versions;
    }

    private FileDescriptor descriptorWithSize(UUID ownerUserId, UUID fileId, long sizeBytes) {
        return new FileDescriptor(
                fileId,
                ownerUserId,
                null,
                "FILE",
                "edited.jpg",
                "/.metadata/PHOTO_ITEM/" + fileId + "/EDIT_VERSION/edited.jpg",
                "image/jpeg",
                sizeBytes,
                null,
                "DERIVED",
                false,
                false,
                SpaceType.PERSONAL,
                ownerUserId,
                Instant.now(),
                Instant.now()
        );
    }

    private byte[] jpegBytes() throws Exception {
        BufferedImage image = new BufferedImage(12, 8, BufferedImage.TYPE_INT_RGB);
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        ImageIO.write(image, "jpg", buffer);
        return buffer.toByteArray();
    }

    private Path createImage() throws Exception {
        Path source = Files.createTempFile("omninest-photo-edit-test-", ".png");
        BufferedImage image = new BufferedImage(12, 8, BufferedImage.TYPE_INT_RGB);
        ImageIO.write(image, "png", source.toFile());
        return source;
    }
}
