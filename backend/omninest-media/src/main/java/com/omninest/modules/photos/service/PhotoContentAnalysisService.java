package com.omninest.modules.photos.service;

import com.omninest.common.ai.ImageAnalysisGateway.BoundingBox;
import com.omninest.common.ai.ImageAnalysisGateway.ContentAnalysis;
import com.omninest.common.ai.ImageAnalysisGateway.ContentObservation;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.photos.domain.PhotoContentAnalysisRun;
import com.omninest.modules.photos.domain.PhotoContentLabel;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoContentAnalysisDto;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoContentLabelDto;
import com.omninest.modules.photos.repository.PhotoContentAnalysisRunRepository;
import com.omninest.modules.photos.repository.PhotoContentLabelRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 图像分析结果的原子落库服务。
 *
 * <p>模型推理在事务外执行，本服务只负责短事务内替换本次运行的标签、
 * 保留增量 OCR 结果，并在事务内投递搜索索引 Outbox。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class PhotoContentAnalysisService {

    public static final String STATUS_RUNNING = "RUNNING";
    public static final String STATUS_SUCCEEDED = "SUCCEEDED";
    public static final String STATUS_SUPERSEDED = "SUPERSEDED";
    public static final String STATUS_FAILED = "FAILED";
    public static final String STATE_AUTO = "AUTO";
    public static final String OCR_LAYOUT_SOURCE = "rapidocr-layout";
    public static final String EXPECTED_OCR_VERSION = "ppocr-v4-onnx-v1";

    private static final String METADATA_OCR_PIPELINE_VERSION = "ocrPipelineVersion";
    private static final String METADATA_OCR_DENSE_STYLE = "ocrDenseStyle";
    private static final String METADATA_OCR_DENSE_CONFIDENCE = "ocrDenseConfidence";
    private static final String METADATA_SEMANTIC_TAGS = "semanticTags";

    private final PhotoContentAnalysisRunRepository runRepository;
    private final PhotoContentLabelRepository labelRepository;
    private final PhotoItemRepository photoItemRepository;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final PhotoIndexTaskService photoIndexTaskService;

    /**
     * 判断当前照片是否已按目标流水线完成分析。
     *
     * @param ownerUserId 用户标识
     * @param photoId 照片标识
     * @param contentHash 当前原图内容哈希
     * @param expectedPipelineVersion 目标流水线版本
     * @return 已是最新分析结果时返回 true
     */
    @Transactional(readOnly = true)
    public boolean isAlreadyAnalyzed(
            UUID ownerUserId,
            UUID photoId,
            String contentHash,
            String expectedPipelineVersion
    ) {
        if (expectedPipelineVersion == null || expectedPipelineVersion.isBlank()) {
            return false;
        }
        PhotoContentAnalysisRun run = latestSucceededRun(ownerUserId, photoId);
        if (run == null || !expectedPipelineVersion.equals(run.getPipelineVersion())) {
            return false;
        }
        return contentHash == null
                || run.getContentHash() == null
                || contentHash.equals(run.getContentHash());
    }

    /**
     * 从同一用户下相同原图哈希的已分析照片克隆标签与 OCR 文本。
     *
     * @return 成功克隆并落库时返回 true
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean tryCloneFromSameHash(
            UUID ownerUserId,
            PhotoItem photo,
            String contentHash,
            String expectedPipelineVersion,
            boolean triggerImmediateIndex
    ) {
        if (contentHash == null || contentHash.isBlank()
                || expectedPipelineVersion == null || expectedPipelineVersion.isBlank()) {
            return false;
        }
        Optional<PhotoContentAnalysisRun> sourceRun = runRepository
                .findFirstByOwnerUserIdAndContentHashAndPipelineVersionAndStatusOrderByCompletedAtDesc(
                        ownerUserId,
                        contentHash,
                        expectedPipelineVersion,
                        STATUS_SUCCEEDED
                );
        if (sourceRun.isEmpty() || sourceRun.get().getPhotoId().equals(photo.getId())) {
            return false;
        }
        PhotoContentAnalysisRun run = sourceRun.get();
        PhotoItem sourcePhoto = photoItemRepository
                .findByOwnerUserIdAndId(ownerUserId, run.getPhotoId())
                .orElse(null);
        if (sourcePhoto == null) {
            return false;
        }
        List<PhotoContentLabel> sourceLabels = labelRepository
                .findByOwnerUserIdAndPhotoIdAndRunId(ownerUserId, run.getPhotoId(), run.getId())
                .stream()
                .filter(label -> STATE_AUTO.equals(label.getState()))
                .toList();
        List<ContentObservation> observations = sourceLabels.stream()
                .map(label -> new ContentObservation(
                        label.getNamespace(),
                        label.getLabelCode(),
                        label.getConfidence(),
                        label.getSource(),
                        toBoundingBoxes(label.getBoxes())
                ))
                .toList();
        List<PhotoLabelPolicy.PhotoLabel> labels = sourceLabels.stream()
                .map(label -> new PhotoLabelPolicy.PhotoLabel(
                        label.getNamespace(),
                        label.getLabelCode(),
                        label.getConfidence(),
                        label.getSource(),
                        toBoundingBoxes(label.getBoxes())
                ))
                .toList();
        ContentAnalysis clonedAnalysis = new ContentAnalysis(
                2,
                expectedPipelineVersion,
                metadataString(sourcePhoto, METADATA_OCR_PIPELINE_VERSION),
                observations,
                metadataStringList(sourcePhoto, METADATA_SEMANTIC_TAGS),
                sourcePhoto.getOcrText()
        );
        apply(ownerUserId, photo.getId(), clonedAnalysis, labels, false, triggerImmediateIndex);
        return true;
    }

    /**
     * 当 skipOcr 为真时，把上一轮由版面分析产出的 OCR 标签并回本轮视觉结果。
     */
    @Transactional(readOnly = true)
    public ContentAnalysis mergePreservedOcrObservations(
            UUID ownerUserId,
            UUID photoId,
            ContentAnalysis visualAnalysis
    ) {
        PhotoContentAnalysisRun previousRun = latestSucceededRun(ownerUserId, photoId);
        if (previousRun == null) {
            return visualAnalysis;
        }
        List<PhotoContentLabel> previousOcrLabels = labelRepository
                .findByOwnerUserIdAndPhotoIdAndRunId(ownerUserId, photoId, previousRun.getId())
                .stream()
                .filter(label -> OCR_LAYOUT_SOURCE.equals(label.getSource()))
                .toList();
        if (previousOcrLabels.isEmpty()) {
            return visualAnalysis;
        }
        List<ContentObservation> merged = new ArrayList<>(visualAnalysis.observations());
        for (PhotoContentLabel label : previousOcrLabels) {
            merged.add(new ContentObservation(
                    label.getNamespace(),
                    label.getLabelCode(),
                    label.getConfidence(),
                    label.getSource(),
                    toBoundingBoxes(label.getBoxes())
            ));
        }
        return new ContentAnalysis(
                visualAnalysis.schemaVersion(),
                visualAnalysis.pipelineVersion(),
                visualAnalysis.ocrPipelineVersion(),
                merged,
                visualAnalysis.semanticTags(),
                visualAnalysis.ocrText()
        );
    }

    /**
     * 密集文本照片切换视觉档位时直接继承 STYLE 标签，避免无意义的外呼。
     *
     * @return 已短路完成并落库时返回 true
     */
    @Transactional(rollbackFor = Exception.class)
    public boolean tryShortCircuitDenseTextReanalysis(
            UUID ownerUserId,
            PhotoItem photo,
            String expectedPipelineVersion,
            boolean triggerImmediateIndex
    ) {
        if (photo.getProviderMetadata() == null) {
            return false;
        }
        Object denseStyleValue = photo.getProviderMetadata().get(METADATA_OCR_DENSE_STYLE);
        if (!(denseStyleValue instanceof String denseStyle) || denseStyle.isBlank()) {
            return false;
        }
        float confidence = 0.92F;
        Object confidenceValue = photo.getProviderMetadata().get(METADATA_OCR_DENSE_CONFIDENCE);
        if (confidenceValue instanceof Number number) {
            confidence = number.floatValue();
        }
        ContentAnalysis syntheticAnalysis = new ContentAnalysis(
                2,
                expectedPipelineVersion,
                EXPECTED_OCR_VERSION,
                List.of(new ContentObservation(
                        PhotoLabelPolicy.STYLE,
                        denseStyle,
                        confidence,
                        OCR_LAYOUT_SOURCE,
                        List.of()
                )),
                metadataStringList(photo, METADATA_SEMANTIC_TAGS),
                photo.getOcrText()
        );
        List<PhotoLabelPolicy.PhotoLabel> labels = List.of(new PhotoLabelPolicy.PhotoLabel(
                PhotoLabelPolicy.STYLE,
                denseStyle,
                confidence,
                OCR_LAYOUT_SOURCE,
                List.of()
        ));
        apply(ownerUserId, photo.getId(), syntheticAnalysis, labels, true, triggerImmediateIndex);
        return true;
    }

    /**
     * 在短事务中原子应用一轮图像分析结果。
     *
     * @param ownerUserId 用户标识
     * @param photoId 照片标识
     * @param analysis 结构化分析结果
     * @param labels 经过业务策略筛选的标签
     * @param skipOcr 是否跳过 OCR；为真时保留原 ocrText 与 OCR 版面标签
     * @param triggerImmediateIndex 是否在同事务内投递单图索引 Outbox
     */
    @Transactional(rollbackFor = Exception.class)
    public void apply(
            UUID ownerUserId,
            UUID photoId,
            ContentAnalysis analysis,
            List<PhotoLabelPolicy.PhotoLabel> labels,
            boolean skipOcr,
            boolean triggerImmediateIndex
    ) {
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId)
                .orElseThrow(() -> new IllegalStateException("照片不存在"));
        fileLifecycleGuard.requireOwnedWritable(ownerUserId, photo.getFileNodeId());
        if (photo.getCoverFileId() != null && !photo.getCoverFileId().equals(photo.getFileNodeId())) {
            fileLifecycleGuard.requireOwnedWritable(ownerUserId, photo.getCoverFileId());
        }

        List<PhotoContentAnalysisRun> previousRuns = runRepository
                .findByOwnerUserIdAndPhotoIdAndStatus(ownerUserId, photoId, STATUS_SUCCEEDED);
        List<PhotoLabelPolicy.PhotoLabel> effectiveLabels = skipOcr
                ? withPreservedOcrLabels(ownerUserId, photoId, labels)
                : labels;
        previousRuns.forEach(run -> run.setStatus(STATUS_SUPERSEDED));
        runRepository.saveAll(previousRuns);

        Instant now = Instant.now();
        PhotoContentAnalysisRun run = new PhotoContentAnalysisRun();
        run.setOwnerUserId(ownerUserId);
        run.setPhotoId(photoId);
        run.setContentHash(contentHash(photo));
        run.setPipelineVersion(analysis.pipelineVersion() == null || analysis.pipelineVersion().isBlank()
                ? "content-analysis-v6"
                : analysis.pipelineVersion());
        run.setStatus(STATUS_SUCCEEDED);
        run.setStartedAt(now);
        run.setCompletedAt(now);
        PhotoContentAnalysisRun savedRun = runRepository.save(run);

        labelRepository.deleteByOwnerUserIdAndPhotoId(ownerUserId, photoId);
        List<PhotoContentLabel> entities = effectiveLabels.stream()
                .map(label -> toEntity(
                        ownerUserId,
                        photoId,
                        savedRun.getId(),
                        savedRun.getPipelineVersion(),
                        label
                ))
                .toList();
        labelRepository.saveAll(entities);

        if (!skipOcr) {
            photo.setOcrText(analysis.ocrText());
        }

        Map<String, Object> metadata = photo.getProviderMetadata() == null
                ? new HashMap<>()
                : new HashMap<>(photo.getProviderMetadata());
        metadata.remove("rawSceneLabels");
        metadata.remove("sceneLabels");
        metadata.remove("aiTags");
        if (!skipOcr) {
            String ocrPipelineVersion = analysis.ocrPipelineVersion();
            if (ocrPipelineVersion == null || ocrPipelineVersion.isBlank()) {
                ocrPipelineVersion = EXPECTED_OCR_VERSION;
            }
            metadata.put(METADATA_OCR_PIPELINE_VERSION, ocrPipelineVersion);
            PhotoLabelPolicy.PhotoLabel denseStyleLabel = effectiveLabels.stream()
                    .filter(label -> PhotoLabelPolicy.STYLE.equals(label.namespace())
                            && OCR_LAYOUT_SOURCE.equals(label.source()))
                    .findFirst()
                    .orElse(null);
            if (denseStyleLabel != null) {
                metadata.put(METADATA_OCR_DENSE_STYLE, denseStyleLabel.code());
                metadata.put(METADATA_OCR_DENSE_CONFIDENCE, denseStyleLabel.confidence());
            } else {
                metadata.remove(METADATA_OCR_DENSE_STYLE);
                metadata.remove(METADATA_OCR_DENSE_CONFIDENCE);
            }
        }
        if (analysis.semanticTags() != null && !analysis.semanticTags().isEmpty()) {
            metadata.put(METADATA_SEMANTIC_TAGS, analysis.semanticTags());
        } else {
            metadata.remove(METADATA_SEMANTIC_TAGS);
        }
        metadata.put("contentAnalysis", Map.of(
                "status", STATUS_SUCCEEDED,
                "pipelineVersion", run.getPipelineVersion(),
                "completedAt", now.toString(),
                "labelCount", entities.size()
        ));
        photo.setProviderMetadata(metadata);
        photoItemRepository.save(photo);

        if (triggerImmediateIndex) {
            photoIndexTaskService.scheduleIndexAfterCommit(ownerUserId, photoId);
        }
    }

    /**
     * 查询照片当前成功的图像分析结果。
     *
     * @param ownerUserId 用户标识
     * @param photoId 照片标识
     * @return 当前分析结果，不存在时返回 null
     */
    @Transactional(readOnly = true)
    public PhotoContentAnalysisDto current(UUID ownerUserId, UUID photoId) {
        PhotoContentAnalysisRun run = latestSucceededRun(ownerUserId, photoId);
        if (run == null) {
            return null;
        }
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndId(ownerUserId, photoId).orElse(null);
        List<PhotoContentLabelDto> labels = labelRepository
                .findByOwnerUserIdAndPhotoIdAndStateOrderByNamespaceAscLabelCodeAsc(
                        ownerUserId,
                        photoId,
                        STATE_AUTO
                )
                .stream()
                .filter(label -> run.getId().equals(label.getRunId()))
                .map(this::toDto)
                .toList();
        return new PhotoContentAnalysisDto(
                run.getStatus(),
                run.getPipelineVersion(),
                run.getCompletedAt(),
                labels,
                photo == null ? null : photo.getOcrText()
        );
    }

    private PhotoContentAnalysisRun latestSucceededRun(UUID ownerUserId, UUID photoId) {
        return runRepository.findTopByOwnerUserIdAndPhotoIdAndStatusOrderByCreatedAtDesc(
                ownerUserId,
                photoId,
                STATUS_SUCCEEDED
        );
    }

    /**
     * skipOcr 时把上一轮版面分析标签补回本轮，避免切换视觉档位后 STYLE 标签丢失。
     */
    private List<PhotoLabelPolicy.PhotoLabel> withPreservedOcrLabels(
            UUID ownerUserId,
            UUID photoId,
            List<PhotoLabelPolicy.PhotoLabel> labels
    ) {
        PhotoContentAnalysisRun previousRun = latestSucceededRun(ownerUserId, photoId);
        if (previousRun == null) {
            return labels;
        }
        List<PhotoContentLabel> previousOcrLabels = labelRepository
                .findByOwnerUserIdAndPhotoIdAndRunId(ownerUserId, photoId, previousRun.getId())
                .stream()
                .filter(label -> OCR_LAYOUT_SOURCE.equals(label.getSource()))
                .toList();
        if (previousOcrLabels.isEmpty()) {
            return labels;
        }
        Set<String> existingKeys = new HashSet<>();
        for (PhotoLabelPolicy.PhotoLabel label : labels) {
            existingKeys.add(labelKey(label.namespace(), label.code()));
        }
        List<PhotoLabelPolicy.PhotoLabel> merged = new ArrayList<>(labels);
        for (PhotoContentLabel previous : previousOcrLabels) {
            if (!existingKeys.add(labelKey(previous.getNamespace(), previous.getLabelCode()))) {
                continue;
            }
            merged.add(new PhotoLabelPolicy.PhotoLabel(
                    previous.getNamespace(),
                    previous.getLabelCode(),
                    previous.getConfidence(),
                    previous.getSource(),
                    toBoundingBoxes(previous.getBoxes())
            ));
        }
        return List.copyOf(merged);
    }

    private String labelKey(String namespace, String code) {
        return namespace + ":" + code;
    }

    private PhotoContentLabel toEntity(
            UUID ownerUserId,
            UUID photoId,
            UUID runId,
            String modelVersion,
            PhotoLabelPolicy.PhotoLabel label
    ) {
        PhotoContentLabel entity = new PhotoContentLabel();
        entity.setOwnerUserId(ownerUserId);
        entity.setPhotoId(photoId);
        entity.setRunId(runId);
        entity.setNamespace(label.namespace());
        entity.setLabelCode(label.code());
        entity.setConfidence(label.confidence());
        entity.setSource(label.source() == null || label.source().isBlank()
                ? "unknown"
                : label.source());
        entity.setModelVersion(modelVersion);
        entity.setBoxes(label.boxes().stream().map(this::toBox).toList());
        entity.setState(STATE_AUTO);
        return entity;
    }

    private Map<String, Object> toBox(BoundingBox box) {
        Map<String, Object> result = new HashMap<>();
        result.put("x", box.x());
        result.put("y", box.y());
        result.put("width", box.width());
        result.put("height", box.height());
        return result;
    }

    private List<BoundingBox> toBoundingBoxes(List<Map<String, Object>> boxes) {
        if (boxes == null || boxes.isEmpty()) {
            return List.of();
        }
        List<BoundingBox> result = new ArrayList<>();
        for (Map<String, Object> box : boxes) {
            if (box == null) {
                continue;
            }
            Object x = box.get("x");
            Object y = box.get("y");
            Object width = box.get("width");
            Object height = box.get("height");
            if (x instanceof Number xValue && y instanceof Number yValue
                    && width instanceof Number widthValue && height instanceof Number heightValue) {
                result.add(new BoundingBox(
                        xValue.floatValue(),
                        yValue.floatValue(),
                        widthValue.floatValue(),
                        heightValue.floatValue()
                ));
            }
        }
        return List.copyOf(result);
    }

    private PhotoContentLabelDto toDto(PhotoContentLabel label) {
        return new PhotoContentLabelDto(
                label.getId(),
                label.getNamespace(),
                label.getLabelCode(),
                label.getConfidence(),
                label.getSource(),
                label.getState(),
                label.getBoxes() == null ? List.of() : label.getBoxes()
        );
    }

    private String contentHash(PhotoItem photo) {
        return metadataString(photo, "contentHash");
    }

    private String metadataString(PhotoItem photo, String key) {
        if (photo.getProviderMetadata() == null) {
            return null;
        }
        Object value = photo.getProviderMetadata().get(key);
        return value == null ? null : value.toString();
    }

    private List<String> metadataStringList(PhotoItem photo, String key) {
        if (photo.getProviderMetadata() == null) {
            return List.of();
        }
        Object value = photo.getProviderMetadata().get(key);
        if (!(value instanceof Collection<?> collection)) {
            return List.of();
        }
        return collection.stream()
                .filter(Objects::nonNull)
                .map(Object::toString)
                .filter(text -> !text.isBlank())
                .toList();
    }
}
