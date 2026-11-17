package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.photos.config.PhotoMediaLimitsProperties;
import java.awt.image.BufferedImage;
import java.nio.file.Files;
import java.nio.file.Path;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;

/**
 * 照片输入格式和解码容量限制测试。
 *
 * @author OmniNest
 */
class PhotoInputGuardTest {

    private final PhotoMediaLimitsProperties properties = new PhotoMediaLimitsProperties();
    private final PhotoInputGuard guard = new PhotoInputGuard(properties);

    @Test
    void inspectForDecodeReturnsDimensionsForValidImage() throws Exception {
        Path image = createImage(12, 8, "png");
        try {
            PhotoInputGuard.ImageDimensions dimensions = guard.inspectForDecode(image, "photo.png");

            assertThat(dimensions.width()).isEqualTo(12);
            assertThat(dimensions.height()).isEqualTo(8);
        } finally {
            Files.deleteIfExists(image);
        }
    }

    @Test
    void inspectForDecodeTrustsContentMagicOverExtensionMismatch() throws Exception {
        // 入口按声明 MIME 收件，扩展名可能与内容不符；处理端以魔数为
        // 事实来源放行可解码内容，否则会留下永久无封面的僵尸条目。
        Path image = createImage(10, 6, "png");
        try {
            PhotoInputGuard.ImageDimensions dimensions = guard.inspectForDecode(image, "photo.jpg");

            assertThat(dimensions.width()).isEqualTo(10);
            assertThat(dimensions.height()).isEqualTo(6);
        } finally {
            Files.deleteIfExists(image);
        }
    }

    @Test
    void inspectForDecodeRejectsUnknownContent() throws Exception {
        Path image = Files.createTempFile("omninest-photo-guard-test-", ".jpg");
        try {
            Files.write(image, new byte[]{0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07});
            assertThatThrownBy(() -> guard.inspectForDecode(image, "photo.jpg"))
                    .isInstanceOf(BusinessException.class)
                    .hasMessage("图片编码不受支持");
        } finally {
            Files.deleteIfExists(image);
        }
    }

    @Test
    void inspectForDecodeRejectsPixelCountBeforeFullDecode() throws Exception {
        properties.setMaxPixels(15);
        properties.setMaxDecodedBytes(60);
        Path image = createImage(4, 4, "png");
        try {
            assertThatThrownBy(() -> guard.inspectForDecode(image, "photo.png"))
                    .isInstanceOf(BusinessException.class)
                    .hasMessage("图片解码内存超出限制");
        } finally {
            Files.deleteIfExists(image);
        }
    }

    @Test
    void detectContentFormatIdentifiesRasterMagics() {
        byte[] jpeg = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0x00, 0x10};
        byte[] png = {(byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
        byte[] unknown = {0x12, 0x34};

        assertThat(guard.detectContentFormat(jpeg)).isEqualTo("jpeg");
        assertThat(guard.detectContentFormat(png)).isEqualTo("png");
        assertThat(guard.detectContentFormat(unknown)).isNull();
    }

    private Path createImage(int width, int height, String format) throws Exception {
        Path image = Files.createTempFile("omninest-photo-guard-test-", "." + format);
        BufferedImage bufferedImage = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        ImageIO.write(bufferedImage, format, image.toFile());
        return image;
    }
}
