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

import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.config.PhotoMediaLimitsProperties;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.dto.PhotoDtos.EditRequest;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoEditVersionDto;
import com.omninest.modules.photos.repository.PhotoEditVersionRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.quota.service.StorageQuotaService;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.function.Consumer;
import java.awt.image.BufferedImage;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
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
            transactionTemplate,
            5
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

        PhotoEditVersionDto result = service.applyEditedImage(ownerUserId, photoId, jpeg);

        assertThat(result.versionNumber()).isEqualTo(1);
        verify(storageQuotaService).checkQuota(ownerUserId, jpeg.length);
        verify(storageQuotaService).incrementUsage(ownerUserId, jpeg.length);
        assertThat(storedPath.get()).doesNotExist();
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

        assertThatThrownBy(() -> service.applyEditedImage(ownerUserId, photoId, payload))
                .isInstanceOf(BusinessException.class);
        verify(storageService, never()).store(
                any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
        verify(storageQuotaService, never()).incrementUsage(any(), anyLong());
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
