package com.omninest.common.ai;

import java.util.List;

/**
 * 提供图片文字识别与受控视觉标签分析能力。
 *
 * @author OmniNest
 */
public interface ImageAnalysisGateway {

    /**
     * 返回允许处理的最大图片字节数。
     *
     * @return 最大图片字节数
     */
    long maxImageBytes();

    /**
     * 探测侧车当前生效的分析流水线版本。
     *
     * @param endpoint 分析服务端点
     * @param timeoutSeconds 请求超时秒数
     * @return 流水线版本；侧车不可用或响应无效时返回 null
     */
    String fetchRemotePipelineVersion(String endpoint, int timeoutSeconds);

    /**
     * 对图片执行文字识别与视觉标签分析。
     *
     * @param imageBytes 图片字节
     * @param filename 上传文件名
     * @param hint 分析提示，取值 AUTO、TEXT_GRAPHIC、NATURAL_PHOTO
     * @param skipOcr 是否跳过重复 OCR
     * @param endpoint 分析服务端点
     * @param timeoutSeconds 请求超时秒数
     * @return 结构化分析结果
     */
    ContentAnalysis analyzeContent(
            byte[] imageBytes,
            String filename,
            String hint,
            boolean skipOcr,
            String endpoint,
            int timeoutSeconds
    );

    /**
     * 结构化图像分析结果。
     *
     * @param schemaVersion 响应契约版本
     * @param pipelineVersion 分析流水线版本
     * @param ocrPipelineVersion OCR 流水线版本
     * @param observations 分析观察项
     * @param semanticTags 开放集语义标签
     * @param ocrText 图片内嵌文字
     */
    record ContentAnalysis(
            int schemaVersion,
            String pipelineVersion,
            String ocrPipelineVersion,
            List<ContentObservation> observations,
            List<String> semanticTags,
            String ocrText
    ) {
        public ContentAnalysis {
            observations = observations == null ? List.of() : List.copyOf(observations);
            semanticTags = semanticTags == null ? List.of() : List.copyOf(semanticTags);
        }
    }

    /**
     * 图像内容观察项。不同命名空间之间禁止通过字符串规则相互推导。
     *
     * @param namespace 命名空间，例如 SUBJECT、SCENE、STYLE
     * @param code 稳定标签编码
     * @param confidence 置信度
     * @param source 产生观察项的模型或检测器
     * @param boxes 归一化边界框
     */
    record ContentObservation(String namespace, String code, float confidence,
                              String source, List<BoundingBox> boxes) {
        public ContentObservation {
            boxes = boxes == null ? List.of() : List.copyOf(boxes);
        }
    }

    /**
     * 归一化图像边界框。
     *
     * @param x 左上角横坐标比例
     * @param y 左上角纵坐标比例
     * @param width 宽度比例
     * @param height 高度比例
     */
    record BoundingBox(float x, float y, float width, float height) {
    }
}
