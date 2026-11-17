package com.omninest.modules.photos.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.omninest.common.ai.ImageAnalysisGateway.BoundingBox;
import com.omninest.common.ai.ImageAnalysisGateway.ContentAnalysis;
import com.omninest.common.ai.ImageAnalysisGateway.ContentObservation;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.jupiter.api.Test;

/**
 * 图像分析标签策略测试。
 *
 * @author OmniNest
 */
class PhotoLabelPolicyTest {

    private final PhotoLabelPolicy policy = new PhotoLabelPolicy();

    @Test
    void shouldKeepSubjectAndSceneNamespacesIndependent() {
        ContentAnalysis analysis = analysis(
                observation("SUBJECT", "cat", 0.91F, "mobileclip2-s0-onnx",
                        List.of(new BoundingBox(0.1F, 0.1F, 0.4F, 0.4F))),
                observation("SCENE", "office", 0.88F, "mobileclip2-s0-onnx", List.of())
        );

        Set<String> labels = policy.classify(analysis).stream()
                .map(label -> label.namespace() + ":" + label.code())
                .collect(Collectors.toSet());

        assertEquals(Set.of("SUBJECT:cat", "SCENE:office"), labels);
        assertFalse(labels.contains("SUBJECT:indoor"));
        assertFalse(labels.contains("SUBJECT:animal"));
    }

    @Test
    void shouldNotInferIndoorOrAnimalFromUncontrolledSceneText() {
        ContentAnalysis analysis = analysis(
                observation("SCENE", "veterinarians office", 0.99F, "unknown", List.of())
        );

        List<PhotoLabelPolicy.PhotoLabel> labels = policy.classify(analysis);

        assertTrue(labels.isEmpty());
    }

    @Test
    void shouldKeepOnlyTheMostConfidentSceneAndStyleLabel() {
        ContentAnalysis analysis = analysis(
                observation("SCENE", "indoor", 0.91F, "mobileclip2-s0-onnx", List.of()),
                observation("SCENE", "office", 0.74F, "mobileclip2-s0-onnx", List.of()),
                observation("STYLE", "photograph", 0.89F, "mobileclip2-s0-onnx", List.of()),
                observation("STYLE", "artwork", 0.72F, "mobileclip2-s0-onnx", List.of()),
                observation("SUBJECT", "cat", 0.89F, "mobileclip2-s0-onnx", List.of())
        );

        Set<String> labels = policy.classify(analysis).stream()
                .map(label -> label.namespace() + ":" + label.code())
                .collect(Collectors.toSet());

        assertEquals(Set.of("SCENE:indoor", "STYLE:photograph", "SUBJECT:cat"), labels);
    }

    @Test
    void shouldDropObservationsBelowNamespaceThreshold() {
        ContentAnalysis analysis = analysis(
                observation("SUBJECT", "cat", 0.64F, "mobileclip2-s0-onnx", List.of()),
                observation("SCENE", "office", 0.54F, "mobileclip2-s0-onnx", List.of()),
                observation("STYLE", "photograph", 0.69F, "mobileclip2-s0-onnx", List.of())
        );

        assertTrue(policy.classify(analysis).isEmpty());
    }

    @Test
    void shouldAcceptPersonSubjectObservationWithoutFaceDetector() {
        ContentAnalysis analysis = analysis(
                observation("STYLE", "illustration", 0.93F, "mobileclip2-s0-onnx", List.of()),
                observation("SUBJECT", "person", 0.88F, "mobileclip2-s0-onnx", List.of())
        );

        Set<String> labels = policy.classify(analysis).stream()
                .map(label -> label.namespace() + ":" + label.code())
                .collect(Collectors.toSet());

        assertEquals(Set.of("SUBJECT:person", "STYLE:illustration"), labels);
    }

    @Test
    void shouldAcceptOcrLayoutStyleCodes() {
        ContentAnalysis analysis = analysis(
                observation("STYLE", "screenshot", 0.96F, PhotoContentAnalysisService.OCR_LAYOUT_SOURCE, List.of()),
                observation("STYLE", "document", 0.91F, PhotoContentAnalysisService.OCR_LAYOUT_SOURCE, List.of())
        );

        List<PhotoLabelPolicy.PhotoLabel> labels = policy.classify(analysis);

        assertEquals(1, labels.size());
        assertEquals("screenshot", labels.getFirst().code());
        assertEquals(PhotoContentAnalysisService.OCR_LAYOUT_SOURCE, labels.getFirst().source());
    }

    @Test
    void shouldExpandSearchKeywordsWithChineseSynonyms() {
        List<String> personKeywords = policy.expandSearchKeywords("SUBJECT", "person");
        List<String> documentKeywords = policy.expandSearchKeywords("STYLE", "document");
        List<String> unknownKeywords = policy.expandSearchKeywords("SCENE", "unknown_code");

        assertTrue(personKeywords.getFirst().contains("人物"));
        assertTrue(personKeywords.getFirst().contains("person"));
        assertTrue(documentKeywords.getFirst().contains("发票"));
        assertTrue(documentKeywords.getFirst().contains("document"));
        assertEquals(List.of("unknown code"), unknownKeywords);
        assertTrue(policy.expandSearchKeywords(null, "cat").isEmpty());
    }

    private ContentAnalysis analysis(ContentObservation... observations) {
        return new ContentAnalysis(
                2,
                "vision-v6-lightweight+ppocr-v4-onnx-v1",
                PhotoContentAnalysisService.EXPECTED_OCR_VERSION,
                List.of(observations),
                List.of(),
                null
        );
    }

    private ContentObservation observation(
            String namespace,
            String code,
            float confidence,
            String source,
            List<BoundingBox> boxes
    ) {
        return new ContentObservation(namespace, code, confidence, source, boxes);
    }
}
