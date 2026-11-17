package com.omninest.modules.reader.service.model;

/**
 * 阅读条目封面解析草稿。
 *
 * @param content 图片内容
 * @param mimeType 解析器识别的 MIME 类型
 * @param sourcePath 压缩包内的来源路径
 * @author OmniNest
 */
public record ReaderCoverDraft(
        byte[] content,
        String mimeType,
        String sourcePath
) {
}
