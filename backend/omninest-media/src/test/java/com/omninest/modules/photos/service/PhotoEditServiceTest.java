package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.config.PhotoMediaLimitsProperties;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.dto.PhotoDtos.EditRequest;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoEditVersionDto;
import com.omninest.modules.photos.repository.PhotoEditVersionRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;
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
    private final PlatformTransactionManager txManager = mock(PlatformTransactionManager.class);
    private final TransactionTemplate transactionTemplate = new TransactionTemplate(txManager);
    private final PhotoEditService service = new PhotoEditService(
            editVersionRepository,
            photoItemRepository,
            storageService,
            syncEventService,
            sourceFileService,
            inputGuard,
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

    private Path createImage() throws Exception {
        Path source = Files.createTempFile("omninest-photo-edit-test-", ".png");
        BufferedImage image = new BufferedImage(12, 8, BufferedImage.TYPE_INT_RGB);
        ImageIO.write(image, "png", source.toFile());
        return source;
    }
}
