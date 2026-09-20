package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.photos.config.PhotoMediaLimitsProperties;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Iterator;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 照片文件和解码内存容量校验器。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class PhotoInputGuard {

    private static final int HEADER_BYTES = 16;
    private static final int BYTES_PER_PIXEL = 4;

    private final PhotoMediaLimitsProperties properties;

    /**
     * 返回指定照片类型的最大文件字节数。
     *
     * @param raw 是否为 RAW 文件
     * @return 最大文件字节数
     */
    public long maxFileBytes(boolean raw) {
        return raw ? properties.getMaxRawFileBytes() : properties.getMaxStandardFileBytes();
    }

    /**
     * 校验文件字节数。
     *
     * @param sizeBytes 文件字节数
     * @param raw 是否为 RAW 文件
     */
    public void validateFileSize(long sizeBytes, boolean raw) {
        long maxBytes = maxFileBytes(raw);
        if (sizeBytes <= 0 || sizeBytes > maxBytes) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "照片文件大小超出限制");
        }
    }

    /**
     * 在完整解码前检查图片魔数、宽高、像素和估算内存。
     *
     * <p>以魔数为唯一格式事实来源：文件名扩展名可能与内容不符
     * （入口按声明 MIME 收件），此时拒绝处理会留下永久无封面的
     * 僵尸条目；内容可解码即放行，仅拒绝无法识别的光栅格式。</p>
     *
     * @param sourceFile 图片文件
     * @param fileName 原始文件名（仅用于调用方上下文）
     * @return 图片宽高
     */
    public ImageDimensions inspectForDecode(Path sourceFile, String fileName) {
        try {
            validateFileSize(Files.size(sourceFile), false);
            validateMagic(sourceFile);
            try (ImageInputStream imageInput = ImageIO.createImageInputStream(sourceFile.toFile())) {
                if (imageInput == null) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR, "图片编码不受支持");
                }
                Iterator<ImageReader> readers = ImageIO.getImageReaders(imageInput);
                if (!readers.hasNext()) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR, "图片编码不受支持");
                }
                ImageReader reader = readers.next();
                try {
                    reader.setInput(imageInput, true, true);
                    int width = reader.getWidth(0);
                    int height = reader.getHeight(0);
                    validateDimensions(width, height);
                    return new ImageDimensions(width, height);
                } finally {
                    reader.dispose();
                }
            }
        } catch (BusinessException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "图片文件检查失败");
        }
    }

    /**
     * 从文件头魔数识别实际光栅格式。
     *
     * @param sourceFile 图片文件
     * @return 识别出的格式（jpeg/png/gif/bmp/tiff），无法识别时返回 null
     */
    public String detectContentFormat(Path sourceFile) {
        byte[] header;
        try (InputStream input = Files.newInputStream(sourceFile)) {
            header = input.readNBytes(HEADER_BYTES);
        } catch (IOException exception) {
            return null;
        }
        return detectFormat(header);
    }

    /**
     * 从字节头魔数识别实际光栅格式。
     *
     * @param header 文件头字节
     * @return 识别出的格式（jpeg/png/gif/bmp/tiff），无法识别时返回 null
     */
    public String detectContentFormat(byte[] header) {
        return detectFormat(header);
    }

    /**
     * 校验图片宽高、总像素和估算解码内存。
     *
     * @param width 图片宽度
     * @param height 图片高度
     */
    public void validateDimensions(Integer width, Integer height) {
        if (width == null || height == null) {
            return;
        }
        if (width <= 0 || height <= 0
                || width > properties.getMaxWidth()
                || height > properties.getMaxHeight()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "图片宽高超出限制");
        }
        try {
            long pixels = Math.multiplyExact((long) width, (long) height);
            long decodedBytes = Math.multiplyExact(pixels, BYTES_PER_PIXEL);
            if (pixels > properties.getMaxPixels() || decodedBytes > properties.getMaxDecodedBytes()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "图片解码内存超出限制");
            }
        } catch (ArithmeticException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "图片尺寸无效");
        }
    }

    private void validateMagic(Path sourceFile) throws IOException {
        byte[] header;
        try (InputStream input = Files.newInputStream(sourceFile)) {
            header = input.readNBytes(HEADER_BYTES);
        }
        if (detectFormat(header) == null) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "图片编码不受支持");
        }
    }

    private String detectFormat(byte[] header) {
        if (header.length >= 3
                && unsigned(header[0]) == 0xFF
                && unsigned(header[1]) == 0xD8
                && unsigned(header[2]) == 0xFF) {
            return "jpeg";
        }
        if (startsWith(header, new int[]{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A})) {
            return "png";
        }
        if (header.length >= 6) {
            String prefix = new String(header, 0, 6, StandardCharsets.US_ASCII);
            if ("GIF87a".equals(prefix) || "GIF89a".equals(prefix)) {
                return "gif";
            }
        }
        if (header.length >= 2 && header[0] == 'B' && header[1] == 'M') {
            return "bmp";
        }
        if (header.length >= 4
                && ((header[0] == 'I' && header[1] == 'I' && header[2] == 42 && header[3] == 0)
                || (header[0] == 'M' && header[1] == 'M' && header[2] == 0 && header[3] == 42))) {
            return "tiff";
        }
        return null;
    }

    private boolean startsWith(byte[] source, int[] expected) {
        if (source.length < expected.length) {
            return false;
        }
        for (int index = 0; index < expected.length; index++) {
            if (unsigned(source[index]) != expected[index]) {
                return false;
            }
        }
        return true;
    }


    private int unsigned(byte value) {
        return value & 0xFF;
    }

    /**
     * 图片宽高检查结果。
     *
     * @param width 图片宽度
     * @param height 图片高度
     */
    public record ImageDimensions(int width, int height) {
    }
}
