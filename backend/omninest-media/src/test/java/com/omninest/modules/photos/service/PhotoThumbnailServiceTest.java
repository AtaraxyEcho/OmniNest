package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.photos.config.PhotoMediaLimitsProperties;
import java.awt.image.BufferedImage;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;

/**
 * 照片缩略图文件化处理测试。
 *
 * @author OmniNest
 */
class PhotoThumbnailServiceTest {

    private final DerivedAssetStorageService storageService = mock(DerivedAssetStorageService.class);
    private final FileLifecycleGuard fileLifecycleGuard = mock(FileLifecycleGuard.class);
    private final PhotoFileDetector fileDetector = new PhotoFileDetector();
    private final PhotoInputGuard inputGuard = new PhotoInputGuard(new PhotoMediaLimitsProperties());
    private final PhotoSourceFileService sourceFileService = new PhotoSourceFileService(
            mock(FileQueryService.class),
            fileDetector,
            inputGuard
    );
    private final PhotoThumbnailService service = new PhotoThumbnailService(
            storageService,
            fileLifecycleGuard,
            sourceFileService,
            inputGuard
    );

    @Test
    void hasStoredThumbnailDelegatesPhysicalAvailabilityCheck() {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        when(storageService.isAvailable(
                eq(ownerUserId),
                eq("PHOTO_ITEM"),
                eq(fileNodeId),
                eq("POSTER"),
                anyString()
        )).thenReturn(true);

        boolean available = service.hasStoredThumbnail(ownerUserId, fileNodeId);

        assertThat(available).isTrue();
        verify(storageService).isAvailable(
                eq(ownerUserId),
                eq("PHOTO_ITEM"),
                eq(fileNodeId),
                eq("POSTER"),
                anyString()
        );
    }

    @Test
    void generateAndStoreUsesTemporaryOutputFileAndDeletesItAfterStorage() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        UUID thumbnailId = UUID.randomUUID();
        when(fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)).thenReturn(true);
        Path source = createImage("png");
        AtomicReference<Path> storedPath = new AtomicReference<>();
        when(storageService.store(
                eq(ownerUserId),
                anyString(),
                eq(fileNodeId),
                anyString(),
                anyString(),
                anyString(),
                any(Path.class)
        )).thenAnswer(invocation -> {
            Path output = invocation.getArgument(6);
            storedPath.set(output);
            assertThat(output).exists();
            assertThat(Files.size(output)).isPositive();
            return thumbnailId;
        });

        try {
            UUID result = service.generateAndStoreFile(ownerUserId, fileNodeId, source, "photo.png");

            assertThat(result).isEqualTo(thumbnailId);
            assertThat(storedPath.get()).doesNotExist();
        } finally {
            Files.deleteIfExists(source);
        }
    }

    @Test
    void generateAndStoreTrustsContentMagicOverExtensionMismatch() throws Exception {
        // 扩展名与内容不符时以魔数为准继续生成封面，避免僵尸占位条目。
        UUID ownerUserId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        UUID thumbnailId = UUID.randomUUID();
        when(fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)).thenReturn(true);
        when(storageService.store(any(), any(), any(), any(), any(), any(), any(Path.class)))
                .thenReturn(thumbnailId);
        Path source = createImage("png");
        try {
            UUID result = service.generateAndStoreFile(
                    ownerUserId,
                    fileNodeId,
                    source,
                    "photo.jpg"
            );

            assertThat(result).isEqualTo(thumbnailId);
            verify(storageService).store(any(), any(), any(), any(), any(), any(), any(Path.class));
        } finally {
            Files.deleteIfExists(source);
        }
    }

    @Test
    void generateAndStoreRejectsUnknownContentBeforeStorage() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        when(fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)).thenReturn(true);
        Path source = Files.createTempFile("omninest-thumb-test-", ".jpg");
        Files.write(source, new byte[]{0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07});
        try {
            UUID result = service.generateAndStoreFile(
                    ownerUserId,
                    fileNodeId,
                    source,
                    "photo.jpg"
            );

            assertThat(result).isNull();
            verifyNoInteractions(storageService);
        } finally {
            Files.deleteIfExists(source);
        }
    }

    @Test
    void generateAndStoreDecodesLargeImageWithinThumbnailBounds() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        UUID thumbnailId = UUID.randomUUID();
        when(fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)).thenReturn(true);
        Path source = createImage(4096, 4096, "jpg");
        AtomicReference<Path> storedPath = new AtomicReference<>();
        when(storageService.store(
                eq(ownerUserId),
                anyString(),
                eq(fileNodeId),
                anyString(),
                anyString(),
                anyString(),
                any(Path.class)
        )).thenAnswer(invocation -> {
            Path output = invocation.getArgument(6);
            storedPath.set(output);
            BufferedImage thumbnail = ImageIO.read(output.toFile());
            assertThat(thumbnail).isNotNull();
            assertThat(thumbnail.getWidth()).isLessThanOrEqualTo(1024);
            assertThat(thumbnail.getHeight()).isLessThanOrEqualTo(1024);
            return thumbnailId;
        });

        try {
            UUID result = service.generateAndStoreFile(ownerUserId, fileNodeId, source, "large.jpg");

            assertThat(result).isEqualTo(thumbnailId);
            assertThat(storedPath.get()).doesNotExist();
        } finally {
            Files.deleteIfExists(source);
        }
    }

    private Path createImage(String format) throws Exception {
        return createImage(24, 16, format);
    }

    private Path createImage(int width, int height, String format) throws Exception {
        Path source = Files.createTempFile("omninest-thumbnail-test-", "." + format);
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        ImageIO.write(image, format, source.toFile());
        return source;
    }
}
