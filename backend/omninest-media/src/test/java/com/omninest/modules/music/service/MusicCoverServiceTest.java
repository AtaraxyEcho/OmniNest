package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;

class MusicCoverServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("70000000-0000-0000-0000-000000000001");
    private static final UUID THUMBNAIL_ID = UUID.fromString("70000000-0000-0000-0000-000000000002");

    private final DerivedAssetStorageService storageService = mock(DerivedAssetStorageService.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final FileMetadataQueryService fileMetadataQueryService = mock(FileMetadataQueryService.class);
    private final MusicCoverThumbnailService coverThumbnailService = mock(MusicCoverThumbnailService.class);
    private final MusicCoverService coverService = new MusicCoverService(
            storageService,
            fileQueryService,
            fileMetadataQueryService,
            coverThumbnailService
    );

    @Test
    void uploadDetectsPngFromFileHeader() {
        byte[] png = new byte[]{
                (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00
        };
        MockMultipartFile file = new MockMultipartFile("file", "cover.bin", "application/octet-stream", png);
        when(storageService.store(
                eq(OWNER_ID),
                eq("MUSIC_COVER"),
                any(UUID.class),
                eq("COVER"),
                any(String.class),
                eq("image/png"),
                any(InputStream.class)
        )).thenReturn(FILE_ID);

        var result = coverService.upload(OWNER_ID, file);

        assertThat(result.fileId()).isEqualTo(FILE_ID);
    }

    @Test
    void uploadRejectsContentWithoutSupportedImageSignature() {
        MockMultipartFile file = new MockMultipartFile(
                "file",
                "cover.jpg",
                "image/jpeg",
                "not-an-image".getBytes(StandardCharsets.US_ASCII)
        );

        assertThatThrownBy(() -> coverService.upload(OWNER_ID, file))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("仅支持");
    }

    @Test
    void validateOwnedCoverDelegatesToFileOwnershipCheck() {
        coverService.validateOwnedCover(OWNER_ID, FILE_ID);

        verify(fileQueryService).validateOwnedImage(OWNER_ID, FILE_ID);
    }

    @Test
    void prepareCoverStreamReturnsDescriptorForOwnedImage() {
        when(fileMetadataQueryService.findActiveById(FILE_ID)).thenReturn(Optional.of(imageDescriptor("image/png", 1024)));

        var descriptor = coverService.prepareCoverStream(OWNER_ID, FILE_ID);

        assertThat(descriptor.fileId()).isEqualTo(FILE_ID);
        assertThat(descriptor.contentType()).isEqualTo("image/png");
        assertThat(descriptor.sizeBytes()).isEqualTo(1024);
        verify(fileQueryService).validateOwnedImage(OWNER_ID, FILE_ID);
    }

    @Test
    void prepareCoverStreamFallsBackToJpegWhenMimeTypeMissing() {
        when(fileMetadataQueryService.findActiveById(FILE_ID)).thenReturn(Optional.of(imageDescriptor(null, 2048)));

        var descriptor = coverService.prepareCoverStream(OWNER_ID, FILE_ID);

        assertThat(descriptor.contentType()).isEqualTo("image/jpeg");
    }

    @Test
    void prepareCoverStreamRejectsOversizedCover() {
        when(fileMetadataQueryService.findActiveById(FILE_ID))
                .thenReturn(Optional.of(imageDescriptor("image/png", 33L * 1024 * 1024)));

        assertThatThrownBy(() -> coverService.prepareCoverStream(OWNER_ID, FILE_ID))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    void prepareCoverStreamAllowsScrapedCoverAboveUploadLimit() {
        when(fileMetadataQueryService.findActiveById(FILE_ID))
                .thenReturn(Optional.of(imageDescriptor("image/png", 12L * 1024 * 1024)));

        var descriptor = coverService.prepareCoverStream(OWNER_ID, FILE_ID);

        assertThat(descriptor.sizeBytes()).isEqualTo(12L * 1024 * 1024);
    }

    @Test
    void prepareCoverStreamRejectsMissingNode() {
        when(fileMetadataQueryService.findActiveById(FILE_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> coverService.prepareCoverStream(OWNER_ID, FILE_ID))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    void streamCoverWritesContentAndClosesStream() throws Exception {
        byte[] payload = "cover-bytes".getBytes(StandardCharsets.US_ASCII);
        var descriptor = new MusicCoverService.CoverStreamDescriptor(OWNER_ID, FILE_ID, "image/png", payload.length);
        when(fileQueryService.openReadableFileContent(OWNER_ID, FILE_ID)).thenReturn(new FileContentStream(
                new ByteArrayInputStream(payload),
                "cover.png",
                payload.length,
                "image/png"
        ));

        ByteArrayOutputStream output = new ByteArrayOutputStream();
        coverService.streamCover(descriptor, output);

        assertThat(output.toByteArray()).isEqualTo(payload);
    }

    @Test
    void prepareThumbnailStreamServesDerivedThumbnail() {
        when(fileMetadataQueryService.findActiveById(FILE_ID))
                .thenReturn(Optional.of(imageDescriptor("image/png", 4096)));
        when(fileMetadataQueryService.findActiveById(THUMBNAIL_ID))
                .thenReturn(Optional.of(imageDescriptor(THUMBNAIL_ID, "image/jpeg", 900)));
        when(coverThumbnailService.ensureThumbnail(OWNER_ID, FILE_ID, 4096)).thenReturn(Optional.of(THUMBNAIL_ID));

        var stream = coverService.prepareThumbnailStream(OWNER_ID, FILE_ID);

        assertThat(stream.derived()).isTrue();
        assertThat(stream.descriptor().fileId()).isEqualTo(THUMBNAIL_ID);
        assertThat(stream.descriptor().contentType()).isEqualTo("image/jpeg");
        verify(fileQueryService).validateOwnedImage(OWNER_ID, FILE_ID);
        verify(fileQueryService).validateOwnedImage(OWNER_ID, THUMBNAIL_ID);
    }

    @Test
    void prepareThumbnailStreamFallsBackToOriginalCover() {
        when(fileMetadataQueryService.findActiveById(FILE_ID))
                .thenReturn(Optional.of(imageDescriptor("image/png", 12L * 1024 * 1024)));
        when(coverThumbnailService.ensureThumbnail(OWNER_ID, FILE_ID, 12L * 1024 * 1024))
                .thenReturn(Optional.empty());

        var stream = coverService.prepareThumbnailStream(OWNER_ID, FILE_ID);

        assertThat(stream.derived()).isFalse();
        assertThat(stream.descriptor().fileId()).isEqualTo(FILE_ID);
        assertThat(stream.descriptor().sizeBytes()).isEqualTo(12L * 1024 * 1024);
    }

    private FileDescriptor imageDescriptor(String mimeType, long sizeBytes) {
        return imageDescriptor(FILE_ID, mimeType, sizeBytes);
    }

    private FileDescriptor imageDescriptor(UUID fileId, String mimeType, long sizeBytes) {
        return new FileDescriptor(
                fileId,
                OWNER_ID,
                null,
                "FILE",
                "cover.png",
                "/library/cover.png",
                mimeType,
                sizeBytes,
                null,
                "MINIO",
                false,
                false,
                SpaceType.PERSONAL,
                OWNER_ID,
                Instant.parse("2026-01-01T00:00:00Z"),
                Instant.parse("2026-01-01T00:00:00Z")
        );
    }
}
