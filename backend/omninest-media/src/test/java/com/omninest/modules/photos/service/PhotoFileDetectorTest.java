package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * 照片文件检测器单元测试。
 *
 * @author OmniNest
 */
class PhotoFileDetectorTest {

    private final PhotoFileDetector detector = new PhotoFileDetector();

    /**
     * 验证 JVM 支持的图片扩展名可被识别。
     */
    @Test
    void detectsDecodableImageExtension() {
        assertThat(detector.isDecodable("photo.JPEG")).isTrue();
    }

    /**
     * 验证 RAW 文件扩展名可被识别。
     */
    @Test
    void detectsRawExtension() {
        assertThat(detector.isRaw("capture.CR2")).isTrue();
    }

    /**
     * 验证无扩展名文件返回空扩展名。
     */
    @Test
    void returnsEmptyExtensionForNameWithoutSuffix() {
        assertThat(detector.extension("photo")).isEmpty();
    }
}
