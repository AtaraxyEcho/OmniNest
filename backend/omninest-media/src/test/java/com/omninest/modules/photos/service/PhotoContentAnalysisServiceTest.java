package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;

import com.omninest.common.ai.ImageAnalysisGateway.ContentAnalysis;
import com.omninest.common.ai.ImageAnalysisGateway.ContentObservation;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.photos.domain.PhotoContentAnalysisRun;
import com.omninest.modules.photos.domain.PhotoContentLabel;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoContentAnalysisDto;
import com.omninest.modules.photos.repository.PhotoContentAnalysisRunRepository;
import com.omninest.modules.photos.repository.PhotoContentLabelRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 图像分析落库测试：OCR 继承、密集文本短路、哈希克隆与索引 Outbox。
 *
 * @author OmniNest
 */
class PhotoContentAnalysisServiceTest {

    private static final String PIPELINE = "vision-v6-lightweight+ppocr-v4-onnx-v1";
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID PHOTO_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final PhotoContentAnalysisRunRepository runRepository =
            Mockito.mock(PhotoContentAnalysisRunRepository.class);
    private final PhotoContentLabelRepository labelRepository =
            Mockito.mock(PhotoContentLabelRepository.class);
    private final PhotoItemRepository photoItemRepository = Mockito.mock(PhotoItemRepository.class);
    private final FileLifecycleGuard fileLifecycleGuard = Mockito.mock(FileLifecycleGuard.class);
    private final PhotoIndexTaskService photoIndexTaskService = Mockito.mock(PhotoIndexTaskService.class);
    private final PhotoContentAnalysisService service = new PhotoContentAnalysisService(
            runRepository,
            labelRepository,
            photoItemRepository,
            fileLifecycleGuard,
            photoIndexTaskService
    );

    @BeforeEach
    void setUp() {
        Mockito.when(runRepository.findByOwnerUserIdAndPhotoIdAndStatus(any(), any(), anyString()))
                .thenReturn(List.of());
        Mockito.when(runRepository.save(any(PhotoContentAnalysisRun.class))).thenAnswer(invocation -> {
            PhotoContentAnalysisRun run = invocation.getArgument(0);
            if (run.getId() == null) {
                run.setId(UUID.randomUUID());
            }
            return run;
        });
    }

    @Test
    void applyStoresOcrTextDenseStyleAndSchedulesIndex() {
        PhotoItem photo = photo(new HashMap<>());
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID))
                .thenReturn(Optional.of(photo));
        ContentAnalysis analysis = analysis("增值税发票", List.of("文档"), List.of(
                observation("STYLE", "document", 0.91F, PhotoContentAnalysisService.OCR_LAYOUT_SOURCE)
        ));
        List<PhotoLabelPolicy.PhotoLabel> labels = List.of(new PhotoLabelPolicy.PhotoLabel(
                "STYLE", "document", 0.91F, PhotoContentAnalysisService.OCR_LAYOUT_SOURCE, List.of()
        ));

        service.apply(OWNER_ID, PHOTO_ID, analysis, labels, false, true);

        assertThat(photo.getOcrText()).isEqualTo("增值税发票");
        assertThat(photo.getProviderMetadata())
                .containsEntry("ocrPipelineVersion", PhotoContentAnalysisService.EXPECTED_OCR_VERSION)
                .containsEntry("ocrDenseStyle", "document")
                .containsEntry("semanticTags", List.of("文档"));
        assertThat(photo.getProviderMetadata().get("ocrDenseConfidence")).isEqualTo(0.91F);
        Mockito.verify(labelRepository).deleteByOwnerUserIdAndPhotoId(OWNER_ID, PHOTO_ID);
        Mockito.verify(photoIndexTaskService).scheduleIndexAfterCommit(OWNER_ID, PHOTO_ID);

        ArgumentCaptor<List<PhotoContentLabel>> labelsCaptor = listCaptor();
        Mockito.verify(labelRepository).saveAll(labelsCaptor.capture());
        assertThat(labelsCaptor.getValue()).singleElement().satisfies(label -> {
            assertThat(label.getRunId()).isNotNull();
            assertThat(label.getModelVersion()).isEqualTo(PIPELINE);
            assertThat(label.getSource()).isEqualTo(PhotoContentAnalysisService.OCR_LAYOUT_SOURCE);
        });
    }

    @Test
    void applyWithSkipOcrPreservesOcrTextAndDenseMetadata() {
        Map<String, Object> metadata = new HashMap<>();
        metadata.put("ocrPipelineVersion", PhotoContentAnalysisService.EXPECTED_OCR_VERSION);
        metadata.put("ocrDenseStyle", "screenshot");
        metadata.put("ocrDenseConfidence", 0.9F);
        PhotoItem photo = photo(metadata);
        photo.setOcrText("旧文字");
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID))
                .thenReturn(Optional.of(photo));
        ContentAnalysis analysis = analysis("新文字", List.of(), List.of(
                observation("SUBJECT", "cat", 0.9F, "mobileclip2-s0-onnx")
        ));
        List<PhotoLabelPolicy.PhotoLabel> labels = List.of(new PhotoLabelPolicy.PhotoLabel(
                "SUBJECT", "cat", 0.9F, "mobileclip2-s0-onnx", List.of()
        ));

        service.apply(OWNER_ID, PHOTO_ID, analysis, labels, true, true);

        assertThat(photo.getOcrText()).isEqualTo("旧文字");
        assertThat(photo.getProviderMetadata())
                .containsEntry("ocrDenseStyle", "screenshot")
                .containsEntry("ocrPipelineVersion", PhotoContentAnalysisService.EXPECTED_OCR_VERSION);
        Mockito.verify(photoIndexTaskService).scheduleIndexAfterCommit(OWNER_ID, PHOTO_ID);
    }

    @Test
    void applyWithSkipOcrRestoresLayoutLabelFromPreviousRun() {
        PhotoContentAnalysisRun previousRun = run(UUID.randomUUID(), PIPELINE);
        Mockito.when(runRepository.findTopByOwnerUserIdAndPhotoIdAndStatusOrderByCreatedAtDesc(
                OWNER_ID, PHOTO_ID, "SUCCEEDED")).thenReturn(previousRun);
        Mockito.when(labelRepository.findByOwnerUserIdAndPhotoIdAndRunId(
                OWNER_ID, PHOTO_ID, previousRun.getId())).thenReturn(List.of(
                label(UUID.randomUUID(), previousRun.getId(), "STYLE", "document",
                        PhotoContentAnalysisService.OCR_LAYOUT_SOURCE)
        ));
        PhotoItem photo = photo(new HashMap<>());
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID))
                .thenReturn(Optional.of(photo));
        ContentAnalysis analysis = analysis(null, List.of(), List.of(
                observation("SUBJECT", "cat", 0.9F, "mobileclip2-s0-onnx")
        ));
        List<PhotoLabelPolicy.PhotoLabel> labels = List.of(new PhotoLabelPolicy.PhotoLabel(
                "SUBJECT", "cat", 0.9F, "mobileclip2-s0-onnx", List.of()
        ));

        service.apply(OWNER_ID, PHOTO_ID, analysis, labels, true, false);

        ArgumentCaptor<List<PhotoContentLabel>> labelsCaptor = listCaptor();
        Mockito.verify(labelRepository).saveAll(labelsCaptor.capture());
        assertThat(labelsCaptor.getValue())
                .extracting(label -> label.getNamespace() + ":" + label.getLabelCode())
                .containsExactlyInAnyOrder("SUBJECT:cat", "STYLE:document");
    }

    @Test
    void mergePreservedOcrObservationsAddsOnlyLayoutLabels() {
        PhotoContentAnalysisRun previousRun = run(UUID.randomUUID(), PIPELINE);
        Mockito.when(runRepository.findTopByOwnerUserIdAndPhotoIdAndStatusOrderByCreatedAtDesc(
                OWNER_ID, PHOTO_ID, "SUCCEEDED")).thenReturn(previousRun);
        PhotoContentLabel layoutLabel = label(
                UUID.randomUUID(), previousRun.getId(), "STYLE", "document",
                PhotoContentAnalysisService.OCR_LAYOUT_SOURCE);
        PhotoContentLabel visualLabel = label(
                UUID.randomUUID(), previousRun.getId(), "SUBJECT", "cat", "mobileclip2-s0-onnx");
        Mockito.when(labelRepository.findByOwnerUserIdAndPhotoIdAndRunId(
                OWNER_ID, PHOTO_ID, previousRun.getId())).thenReturn(List.of(layoutLabel, visualLabel));
        ContentAnalysis visualAnalysis = analysis(null, List.of(), List.of(
                observation("SUBJECT", "cat", 0.9F, "mobileclip2-s0-onnx")
        ));

        ContentAnalysis merged = service.mergePreservedOcrObservations(OWNER_ID, PHOTO_ID, visualAnalysis);

        assertThat(merged.observations()).hasSize(2);
        assertThat(merged.observations())
                .anySatisfy(observation -> {
                    assertThat(observation.namespace()).isEqualTo("STYLE");
                    assertThat(observation.code()).isEqualTo("document");
                    assertThat(observation.source()).isEqualTo(PhotoContentAnalysisService.OCR_LAYOUT_SOURCE);
                });
    }

    @Test
    void tryShortCircuitDenseTextReanalysisKeepsOcrTextAndStyle() {
        Map<String, Object> metadata = new HashMap<>();
        metadata.put("ocrDenseStyle", "document");
        metadata.put("ocrDenseConfidence", 0.93F);
        metadata.put("ocrPipelineVersion", PhotoContentAnalysisService.EXPECTED_OCR_VERSION);
        PhotoItem photo = photo(metadata);
        photo.setOcrText("合同正文");
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID))
                .thenReturn(Optional.of(photo));

        boolean shortCircuited = service.tryShortCircuitDenseTextReanalysis(
                OWNER_ID, photo, PIPELINE, true);

        assertThat(shortCircuited).isTrue();
        assertThat(photo.getOcrText()).isEqualTo("合同正文");
        assertThat(photo.getProviderMetadata()).containsEntry("ocrDenseStyle", "document");
        Mockito.verify(photoIndexTaskService).scheduleIndexAfterCommit(OWNER_ID, PHOTO_ID);
        ArgumentCaptor<List<PhotoContentLabel>> labelsCaptor = listCaptor();
        Mockito.verify(labelRepository).saveAll(labelsCaptor.capture());
        assertThat(labelsCaptor.getValue()).singleElement().satisfies(label -> {
            assertThat(label.getNamespace()).isEqualTo("STYLE");
            assertThat(label.getLabelCode()).isEqualTo("document");
            assertThat(label.getConfidence()).isEqualTo(0.93F);
        });
    }

    @Test
    void tryShortCircuitReturnsFalseWithoutDenseStyle() {
        PhotoItem photo = photo(new HashMap<>());
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID))
                .thenReturn(Optional.of(photo));

        assertThat(service.tryShortCircuitDenseTextReanalysis(OWNER_ID, photo, PIPELINE, true))
                .isFalse();
        Mockito.verifyNoInteractions(labelRepository, photoIndexTaskService);
    }

    @Test
    void tryCloneFromSameHashCopiesLabelsOcrTextAndSemanticTags() {
        UUID sourcePhotoId = UUID.randomUUID();
        UUID sourceRunId = UUID.randomUUID();
        PhotoContentAnalysisRun sourceRun = run(sourceRunId, PIPELINE);
        sourceRun.setPhotoId(sourcePhotoId);
        sourceRun.setContentHash("hash-1");
        Mockito.when(runRepository
                        .findFirstByOwnerUserIdAndContentHashAndPipelineVersionAndStatusOrderByCompletedAtDesc(
                                OWNER_ID, "hash-1", PIPELINE, "SUCCEEDED"))
                .thenReturn(Optional.of(sourceRun));

        PhotoItem targetPhoto = photo(new HashMap<>());
        targetPhoto.getProviderMetadata().put("contentHash", "hash-1");
        Map<String, Object> sourceMetadata = new HashMap<>();
        sourceMetadata.put("ocrPipelineVersion", PhotoContentAnalysisService.EXPECTED_OCR_VERSION);
        sourceMetadata.put("semanticTags", List.of("橘猫"));
        PhotoItem sourcePhoto = photo(sourceMetadata);
        sourcePhoto.setId(sourcePhotoId);
        sourcePhoto.setOcrText("源图文字");
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID))
                .thenReturn(Optional.of(targetPhoto));
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, sourcePhotoId))
                .thenReturn(Optional.of(sourcePhoto));
        Mockito.when(labelRepository.findByOwnerUserIdAndPhotoIdAndRunId(
                OWNER_ID, sourcePhotoId, sourceRunId)).thenReturn(List.of(
                label(UUID.randomUUID(), sourceRunId, "SUBJECT", "cat", "mobileclip2-s0-onnx")
        ));

        boolean cloned = service.tryCloneFromSameHash(
                OWNER_ID, targetPhoto, "hash-1", PIPELINE, true);

        assertThat(cloned).isTrue();
        assertThat(targetPhoto.getOcrText()).isEqualTo("源图文字");
        assertThat(targetPhoto.getProviderMetadata())
                .containsEntry("semanticTags", List.of("橘猫"))
                .containsEntry("ocrPipelineVersion", PhotoContentAnalysisService.EXPECTED_OCR_VERSION);
        ArgumentCaptor<List<PhotoContentLabel>> labelsCaptor = listCaptor();
        Mockito.verify(labelRepository).saveAll(labelsCaptor.capture());
        assertThat(labelsCaptor.getValue()).singleElement().satisfies(label -> {
            assertThat(label.getNamespace()).isEqualTo("SUBJECT");
            assertThat(label.getLabelCode()).isEqualTo("cat");
            assertThat(label.getRunId()).isNotEqualTo(sourceRunId);
        });
    }

    @Test
    void currentReturnsOcrTextAndOnlyLatestRunLabels() {
        PhotoContentAnalysisRun run = run(UUID.randomUUID(), PIPELINE);
        Mockito.when(runRepository.findTopByOwnerUserIdAndPhotoIdAndStatusOrderByCreatedAtDesc(
                OWNER_ID, PHOTO_ID, "SUCCEEDED")).thenReturn(run);
        PhotoItem photo = photo(new HashMap<>());
        photo.setOcrText("图中文字");
        Mockito.when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID))
                .thenReturn(Optional.of(photo));
        PhotoContentLabel currentLabel = label(
                UUID.randomUUID(), run.getId(), "SUBJECT", "cat", "mobileclip2-s0-onnx");
        PhotoContentLabel oldLabel = label(
                UUID.randomUUID(), UUID.randomUUID(), "SUBJECT", "dog", "mobileclip2-s0-onnx");
        Mockito.when(labelRepository
                        .findByOwnerUserIdAndPhotoIdAndStateOrderByNamespaceAscLabelCodeAsc(
                                OWNER_ID, PHOTO_ID, "AUTO"))
                .thenReturn(List.of(currentLabel, oldLabel));

        PhotoContentAnalysisDto result = service.current(OWNER_ID, PHOTO_ID);

        assertThat(result.ocrText()).isEqualTo("图中文字");
        assertThat(result.labels()).singleElement().satisfies(label -> {
            assertThat(label.namespace()).isEqualTo("SUBJECT");
            assertThat(label.code()).isEqualTo("cat");
        });
    }

    @Test
    void isAlreadyAnalyzedRequiresPipelineAndContentHash() {
        PhotoContentAnalysisRun run = run(UUID.randomUUID(), PIPELINE);
        run.setContentHash("hash-1");
        Mockito.when(runRepository.findTopByOwnerUserIdAndPhotoIdAndStatusOrderByCreatedAtDesc(
                OWNER_ID, PHOTO_ID, "SUCCEEDED")).thenReturn(run);

        assertThat(service.isAlreadyAnalyzed(OWNER_ID, PHOTO_ID, "hash-1", PIPELINE)).isTrue();
        assertThat(service.isAlreadyAnalyzed(OWNER_ID, PHOTO_ID, "hash-2", PIPELINE)).isFalse();
        assertThat(service.isAlreadyAnalyzed(OWNER_ID, PHOTO_ID, "hash-1", "other-pipeline")).isFalse();
    }

    private PhotoItem photo(Map<String, Object> metadata) {
        PhotoItem photo = new PhotoItem();
        photo.setId(PHOTO_ID);
        photo.setOwnerUserId(OWNER_ID);
        photo.setFileNodeId(UUID.randomUUID());
        photo.setProviderMetadata(metadata);
        return photo;
    }

    private PhotoContentAnalysisRun run(UUID runId, String pipelineVersion) {
        PhotoContentAnalysisRun run = new PhotoContentAnalysisRun();
        run.setId(runId);
        run.setOwnerUserId(OWNER_ID);
        run.setPhotoId(PHOTO_ID);
        run.setPipelineVersion(pipelineVersion);
        run.setStatus("SUCCEEDED");
        run.setCompletedAt(Instant.now());
        return run;
    }

    private PhotoContentLabel label(
            UUID labelId,
            UUID runId,
            String namespace,
            String code,
            String source
    ) {
        PhotoContentLabel label = new PhotoContentLabel();
        label.setId(labelId);
        label.setOwnerUserId(OWNER_ID);
        label.setPhotoId(PHOTO_ID);
        label.setRunId(runId);
        label.setNamespace(namespace);
        label.setLabelCode(code);
        label.setConfidence(0.9F);
        label.setSource(source);
        label.setState("AUTO");
        label.setBoxes(new ArrayList<>());
        return label;
    }

    private ContentAnalysis analysis(
            String ocrText,
            List<String> semanticTags,
            List<ContentObservation> observations
    ) {
        return new ContentAnalysis(
                2,
                PIPELINE,
                PhotoContentAnalysisService.EXPECTED_OCR_VERSION,
                observations,
                semanticTags,
                ocrText
        );
    }

    private ContentObservation observation(
            String namespace,
            String code,
            float confidence,
            String source
    ) {
        return new ContentObservation(namespace, code, confidence, source, List.of());
    }

    @SuppressWarnings("unchecked")
    private ArgumentCaptor<List<PhotoContentLabel>> listCaptor() {
        return ArgumentCaptor.forClass(List.class);
    }
}
