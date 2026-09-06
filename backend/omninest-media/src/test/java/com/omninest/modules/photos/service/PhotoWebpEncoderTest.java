package com.omninest.modules.photos.service;

import static org.junit.jupiter.api.Assertions.assertTrue;

import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;

/**
 * 验证 WebP 编码器依赖在类路径上正确注册。
 *
 * <p>PhotoThumbnailService 依赖该 SPI 输出 WebP 缩略图；
 * 若依赖被移除或 natives 缺失，此测试先行失败。</p>
 */
class PhotoWebpEncoderTest {

    @Test
    void webpImageWriterShouldBeRegistered() {
        assertTrue(ImageIO.getImageWritersByFormatName("webp").hasNext(),
                "缺少 WebP ImageIO 编码器，缩略图将回退为 JPEG");
    }
}
