package com.omninest.modules.photos.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.AdditionalMatchers.aryEq;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;

import com.omninest.common.ai.ImageAnalysisGateway;
import com.omninest.common.ai.ImageAnalysisGateway.ContentAnalysis;
import com.omninest.common.ai.ImageAnalysisGateway.ContentObservation;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 照片图像分析编排测试：选源、短路、下采样与生命周期边界。
 *
 * @author OmniNest
 */
class PhotoAiServiceTest {

    private static final String PIPELINE = "vision-v6-lightweight+ppocr-v4-onnx-v1";

    private final ImageAnalysisGateway imageAnalysisGateway = Mockito.mock(ImageAnalysisGateway.class);
    private final PhotoLabelPolicy labelPolicy = new PhotoLabelPolicy();
    private final PhotoContentAnalysisService contentAnalysisService =
            Mockito.mock(PhotoContentAnalysisService.class);
    private final PhotosRuntimeConfigService configService = Mockito.mock(PhotosRuntimeConfigService.class);
    private final PhotoItemRepository photoItemRepository = Mockito.mock(PhotoItemRepository.class);
    private final PhotoFileDetector fileDetector = new PhotoFileDetector();
    private final FileQueryService fileQueryService = Mockito.mock(FileQueryService.class);
    private final FileLifecycleGuard fileLifecycleGuard = Mockito.mock(FileLifecycleGuard.class);
    private final PhotoAiService service = new PhotoAiService(
            imageAnalysisGateway,
            labelPolicy,
            contentAnalysisService,
            configService,
            photoItemRepository,
            fileDetector,
            fileQueryService,
            fileLifecycleGuard
    );

    @Test
    void shouldReadOriginalAndApplyOcrAnalysis() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, fileNodeId, null);
        photo.setCameraMake("Apple");
        photo.getProviderMetadata().put("contentHash", "hash-1");
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        byte[] imageBytes = new byte[]{1, 2, 3, 4, 5};
        Mockito.when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenReturn(content(imageBytes));
        ContentAnalysis analysis = analysis("增值税发票");
        Mockito.when(imageAnalysisGateway.analyzeContent(
                        any(byte[].class), anyString(), anyString(), anyBoolean(), anyString(), anyInt()))
                .thenReturn(analysis);

        service.processPhoto(ownerUserId, photoId, true);

        Mockito.verify(imageAnalysisGateway).analyzeContent(
                aryEq(imageBytes),
                eq(photoId + ".jpg"),
                eq("NATURAL_PHOTO"),
                eq(false),
                eq("http://sidecar"),
                eq(5)
        );
        ArgumentCaptor<ContentAnalysis> analysisCaptor = ArgumentCaptor.forClass(ContentAnalysis.class);
        Mockito.verify(contentAnalysisService).apply(
                eq(ownerUserId),
                eq(photoId),
                analysisCaptor.capture(),
                Mockito.anyList(),
                eq(false),
                eq(true)
        );
        assertSame(analysis, analysisCaptor.getValue());
    }

    @Test
    void shouldUseCoverAndSkipOcrWhenOcrVersionIsCurrent() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        UUID coverFileId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, fileNodeId, coverFileId);
        photo.getProviderMetadata().put("ocrPipelineVersion", PhotoAiService.EXPECTED_OCR_VERSION);
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        byte[] coverBytes = new byte[]{9, 8, 7};
        Mockito.when(fileQueryService.openOwnedFileContent(ownerUserId, coverFileId))
                .thenReturn(content(coverBytes));
        ContentAnalysis analysis = analysis("old text");
        Mockito.when(imageAnalysisGateway.analyzeContent(
                        any(byte[].class), anyString(), anyString(), anyBoolean(), anyString(), anyInt()))
                .thenReturn(analysis);
        Mockito.when(contentAnalysisService.mergePreservedOcrObservations(ownerUserId, photoId, analysis))
                .thenReturn(analysis);

        service.processPhoto(ownerUserId, photoId, false);

        Mockito.verify(fileQueryService).openOwnedFileContent(ownerUserId, coverFileId);
        Mockito.verify(fileQueryService, Mockito.never()).openOwnedFileContent(ownerUserId, fileNodeId);
        Mockito.verify(imageAnalysisGateway).analyzeContent(
                aryEq(coverBytes),
                eq(photoId + ".jpg"),
                eq("AUTO"),
                eq(true),
                eq("http://sidecar"),
                eq(5)
        );
        Mockito.verify(contentAnalysisService).apply(
                eq(ownerUserId),
                eq(photoId),
                eq(analysis),
                Mockito.anyList(),
                eq(true),
                eq(false)
        );
    }

    @Test
    void shouldShortCircuitDenseTextWithoutCallingSidecar() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, UUID.randomUUID(), UUID.randomUUID());
        photo.getProviderMetadata().put("ocrPipelineVersion", PhotoAiService.EXPECTED_OCR_VERSION);
        photo.getProviderMetadata().put("ocrDenseStyle", "document");
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(contentAnalysisService.tryShortCircuitDenseTextReanalysis(
                ownerUserId, photo, PIPELINE, true)).thenReturn(true);

        service.processPhoto(ownerUserId, photoId, true);

        Mockito.verifyNoInteractions(imageAnalysisGateway, fileQueryService);
        Mockito.verify(contentAnalysisService, Mockito.never())
                .apply(any(), any(), any(), any(), anyBoolean(), anyBoolean());
    }

    @Test
    void shouldCloneAnalysisWhenSameContentHashWasAlreadyAnalyzed() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, UUID.randomUUID(), null);
        photo.getProviderMetadata().put("contentHash", "hash-1");
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(contentAnalysisService.tryCloneFromSameHash(
                ownerUserId, photo, "hash-1", PIPELINE, false)).thenReturn(true);

        service.processPhoto(ownerUserId, photoId, false);

        Mockito.verifyNoInteractions(imageAnalysisGateway, fileQueryService);
        Mockito.verify(contentAnalysisService, Mockito.never())
                .apply(any(), any(), any(), any(), anyBoolean(), anyBoolean());
    }

    @Test
    void shouldSkipWhenPhotoIsAlreadyAnalyzedWithExpectedPipeline() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, UUID.randomUUID(), null);
        photo.getProviderMetadata().put("contentHash", "hash-1");
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(contentAnalysisService.isAlreadyAnalyzed(
                ownerUserId, photoId, "hash-1", PIPELINE)).thenReturn(true);

        service.processPhoto(ownerUserId, photoId, true);

        Mockito.verifyNoInteractions(imageAnalysisGateway, fileQueryService);
        Mockito.verify(contentAnalysisService, Mockito.never())
                .tryCloneFromSameHash(any(), any(), any(), any(), anyBoolean());
        Mockito.verify(contentAnalysisService, Mockito.never())
                .apply(any(), any(), any(), any(), anyBoolean(), anyBoolean());
    }

    @Test
    void shouldSignalDependencyNotReadyWhenRawPhotoHasNoCover() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, UUID.randomUUID(), null);
        photo.setFormat("dng");
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));

        BusinessException exception = assertThrows(BusinessException.class,
                () -> service.processPhoto(ownerUserId, photoId, true));

        assertEquals(ErrorCode.TASK_DEPENDENCY_NOT_READY, exception.errorCode());
        Mockito.verifyNoInteractions(fileQueryService, imageAnalysisGateway);
    }

    @Test
    void shouldDownsampleOriginalWhenLongSideExceedsDirectLimit() throws IOException {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, fileNodeId, null);
        photo.setFileSize(3L * 1024 * 1024);
        photo.setWidth(3000);
        photo.setHeight(100);
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        byte[] original = jpegBytes(3000, 100);
        Mockito.when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenReturn(content(original));
        Mockito.when(imageAnalysisGateway.analyzeContent(
                        any(byte[].class), anyString(), anyString(), anyBoolean(), anyString(), anyInt()))
                .thenReturn(analysis(null));

        service.processPhoto(ownerUserId, photoId, false);

        ArgumentCaptor<byte[]> bytesCaptor = ArgumentCaptor.forClass(byte[].class);
        Mockito.verify(imageAnalysisGateway).analyzeContent(
                bytesCaptor.capture(),
                anyString(),
                anyString(),
                anyBoolean(),
                anyString(),
                anyInt()
        );
        byte[] sent = bytesCaptor.getValue();
        assertNotEquals(original.length, sent.length);
        assertEquals(0xFF, sent[0] & 0xFF);
        assertEquals(0xD8, sent[1] & 0xFF);
    }

    @Test
    void shouldFallbackToCoverWhenOriginalExceedsDownsampleSourceLimit() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        UUID coverFileId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, fileNodeId, coverFileId);
        photo.setFileSize(40L * 1024 * 1024);
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        byte[] coverBytes = new byte[]{5, 5, 5};
        Mockito.when(fileQueryService.openOwnedFileContent(ownerUserId, coverFileId))
                .thenReturn(content(coverBytes));
        Mockito.when(imageAnalysisGateway.analyzeContent(
                        any(byte[].class), anyString(), anyString(), anyBoolean(), anyString(), anyInt()))
                .thenReturn(analysis(null));

        service.processPhoto(ownerUserId, photoId, false);

        Mockito.verify(fileQueryService).openOwnedFileContent(ownerUserId, coverFileId);
        Mockito.verify(fileQueryService, Mockito.never()).openOwnedFileContent(ownerUserId, fileNodeId);
    }

    @Test
    void shouldRejectOriginalLargerThanGatewayInputLimit() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, fileNodeId, null);
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(imageAnalysisGateway.maxImageBytes()).thenReturn(4L);
        Mockito.when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenReturn(content(new byte[]{1, 2, 3, 4, 5}));

        assertThrows(IllegalStateException.class,
                () -> service.processPhoto(ownerUserId, photoId, false));

        Mockito.verify(imageAnalysisGateway, Mockito.never()).analyzeContent(
                any(), anyString(), anyString(), anyBoolean(), anyString(), anyInt());
    }

    @Test
    void shouldRejectIncompleteSidecarAnalysis() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, fileNodeId, null);
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenReturn(content(new byte[]{1, 2, 3}));
        Mockito.when(imageAnalysisGateway.analyzeContent(
                        any(byte[].class), anyString(), anyString(), anyBoolean(), anyString(), anyInt()))
                .thenReturn(new ContentAnalysis(0, null, null, List.of(), List.of(), null));

        assertThrows(IllegalStateException.class,
                () -> service.processPhoto(ownerUserId, photoId, false));

        Mockito.verify(contentAnalysisService, Mockito.never())
                .apply(any(), any(), any(), any(), anyBoolean(), anyBoolean());
    }

    @Test
    void shouldKeepExistingAnalysisWhenSidecarFails() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, fileNodeId, null);
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenReturn(content(new byte[]{1, 2, 3}));
        Mockito.when(imageAnalysisGateway.analyzeContent(
                        any(byte[].class), anyString(), anyString(), anyBoolean(), anyString(), anyInt()))
                .thenThrow(new IllegalStateException("sidecar unavailable"));

        assertThrows(IllegalStateException.class,
                () -> service.processPhoto(ownerUserId, photoId, false));

        Mockito.verify(contentAnalysisService, Mockito.never())
                .apply(any(), any(), any(), any(), anyBoolean(), anyBoolean());
    }

    @Test
    void shouldNotShortCircuitOrCloneWhenPipelineVersionIsUnavailable() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, fileNodeId, null);
        photo.getProviderMetadata().put("contentHash", "hash-1");
        photo.getProviderMetadata().put("ocrPipelineVersion", PhotoAiService.EXPECTED_OCR_VERSION);
        Mockito.when(configService.expectedPipelineVersion()).thenReturn(null);
        Mockito.when(configService.aiEndpoint()).thenReturn("http://sidecar");
        Mockito.when(configService.aiTimeoutSeconds()).thenReturn(5);
        Mockito.when(imageAnalysisGateway.maxImageBytes()).thenReturn(64L * 1024 * 1024);
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenReturn(content(new byte[]{1, 2, 3}));
        ContentAnalysis analysis = analysis(null);
        Mockito.when(imageAnalysisGateway.analyzeContent(
                        any(byte[].class), anyString(), anyString(), anyBoolean(), anyString(), anyInt()))
                .thenReturn(analysis);
        Mockito.when(contentAnalysisService.mergePreservedOcrObservations(ownerUserId, photoId, analysis))
                .thenReturn(analysis);

        service.processPhoto(ownerUserId, photoId, false);

        Mockito.verify(contentAnalysisService, Mockito.never()).isAlreadyAnalyzed(
                any(), any(), any(), any());
        Mockito.verify(contentAnalysisService, Mockito.never())
                .tryCloneFromSameHash(any(), any(), any(), any(), anyBoolean());
        Mockito.verify(contentAnalysisService, Mockito.never())
                .tryShortCircuitDenseTextReanalysis(any(), any(), any(), anyBoolean());
        Mockito.verify(imageAnalysisGateway).analyzeContent(
                any(byte[].class), anyString(), anyString(), eq(true), anyString(), anyInt());
    }

    @Test
    void shouldUseTextGraphicHintForPngWithoutCameraMetadata() {
        UUID ownerUserId = UUID.randomUUID();
        UUID photoId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        PhotoItem photo = photo(ownerUserId, photoId, fileNodeId, null);
        photo.setFormat("png");
        stubConfig();
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId))
                .thenReturn(Optional.of(photo));
        Mockito.when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenReturn(content(new byte[]{1, 2, 3}));
        Mockito.when(imageAnalysisGateway.analyzeContent(
                        any(byte[].class), anyString(), anyString(), anyBoolean(), anyString(), anyInt()))
                .thenReturn(analysis(null));

        service.processPhoto(ownerUserId, photoId, false);

        Mockito.verify(imageAnalysisGateway).analyzeContent(
                any(byte[].class),
                eq(photoId + ".jpg"),
                eq("TEXT_GRAPHIC"),
                eq(false),
                eq("http://sidecar"),
                eq(5)
        );
    }

    private PhotoItem photo(UUID ownerUserId, UUID photoId, UUID fileNodeId, UUID coverFileId) {
        PhotoItem photo = new PhotoItem();
        photo.setId(photoId);
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(fileNodeId);
        photo.setCoverFileId(coverFileId);
        photo.setFormat("jpg");
        photo.setFileSize(1024);
        photo.setWidth(100);
        photo.setHeight(100);
        photo.setProviderMetadata(new HashMap<>());
        return photo;
    }

    private void stubConfig() {
        Mockito.when(configService.expectedPipelineVersion()).thenReturn(PIPELINE);
        Mockito.when(configService.aiEndpoint()).thenReturn("http://sidecar");
        Mockito.when(configService.aiTimeoutSeconds()).thenReturn(5);
        Mockito.when(imageAnalysisGateway.maxImageBytes()).thenReturn(64L * 1024 * 1024);
    }

    private FileContentStream content(byte[] bytes) {
        return new FileContentStream(
                new ByteArrayInputStream(bytes),
                "photo.jpg",
                bytes.length,
                "image/jpeg"
        );
    }

    private ContentAnalysis analysis(String ocrText) {
        return new ContentAnalysis(
                2,
                PIPELINE,
                PhotoAiService.EXPECTED_OCR_VERSION,
                List.of(new ContentObservation(
                        "SUBJECT",
                        "cat",
                        0.9F,
                        "mobileclip2-s0-onnx",
                        List.of()
                )),
                List.of("橘猫"),
                ocrText
        );
    }

    private byte[] jpegBytes(int width, int height) throws IOException {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        for (int x = 0; x < width; x++) {
            image.setRGB(x, height / 2, 0x336699);
        }
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        ImageIO.write(image, "jpg", output);
        return output.toByteArray();
    }
}
