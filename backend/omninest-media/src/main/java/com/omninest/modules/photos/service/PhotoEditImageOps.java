package com.omninest.modules.photos.service;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.awt.image.ByteLookupTable;
import java.awt.image.ConvolveOp;
import java.awt.image.DataBufferInt;
import java.awt.image.Kernel;
import java.awt.image.LookupOp;
import java.util.Map;

/**
 * 照片编辑的像素级滤镜与画布归一化。
 *
 * <p>所有操作统一使用三通道 INT_RGB 画布：索引色与带 Alpha 的源图直接在原类型上
 * 套单表 LookupOp 或同类型画布会抛 ImagingOpException。</p>
 *
 * @author OmniNest
 */
final class PhotoEditImageOps {

    private PhotoEditImageOps() {
    }

    static BufferedImage copyToIntRgb(BufferedImage image) {
        BufferedImage result = new BufferedImage(
                image.getWidth(), image.getHeight(), BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = result.createGraphics();
        try {
            // 透明像素按白底合成，与写出 JPEG 前的口径一致。
            graphics.setColor(Color.WHITE);
            graphics.fillRect(0, 0, image.getWidth(), image.getHeight());
            graphics.drawImage(image, 0, 0, null);
        } finally {
            graphics.dispose();
        }
        return result;
    }

    static BufferedImage ensureOpaqueRgb(BufferedImage image) {
        if (!image.getColorModel().hasAlpha()) {
            return image;
        }
        BufferedImage rgb = new BufferedImage(
                image.getWidth(), image.getHeight(), BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = rgb.createGraphics();
        try {
            graphics.setColor(Color.WHITE);
            graphics.fillRect(0, 0, image.getWidth(), image.getHeight());
            graphics.drawImage(image, 0, 0, null);
        } finally {
            graphics.dispose();
        }
        return rgb;
    }

    /** 饱和度调整：factor 1 为原图，0 为灰度，2 为两倍饱和度。 */
    static BufferedImage applySaturation(BufferedImage image, Map<String, Object> params) {
        float factor = ((Number) params.getOrDefault("factor", 1.0f)).floatValue();
        BufferedImage result = copyToIntRgb(image);
        int[] pixels = pixelData(result);
        for (int index = 0; index < pixels.length; index++) {
            int rgb = pixels[index];
            int r = (rgb >> 16) & 0xFF;
            int g = (rgb >> 8) & 0xFF;
            int b = rgb & 0xFF;
            float gray = 0.299f * r + 0.587f * g + 0.114f * b;
            int nr = clampColor(Math.round(gray + (r - gray) * factor));
            int ng = clampColor(Math.round(gray + (g - gray) * factor));
            int nb = clampColor(Math.round(gray + (b - gray) * factor));
            pixels[index] = (nr << 16) | (ng << 8) | nb;
        }
        return result;
    }

    static BufferedImage applyBrightness(BufferedImage image, Map<String, Object> params) {
        float factor = ((Number) params.getOrDefault("factor", 1.0f)).floatValue();
        byte[] lookup = new byte[256];
        for (int i = 0; i < 256; i++) {
            lookup[i] = (byte) Math.min(255, Math.max(0, (int) (i * factor)));
        }
        LookupOp op = new LookupOp(new ByteLookupTable(0, lookup), null);
        return op.filter(copyToIntRgb(image), null);
    }

    static BufferedImage applyContrast(BufferedImage image, Map<String, Object> params) {
        float factor = ((Number) params.getOrDefault("factor", 1.0f)).floatValue();
        byte[] lookup = new byte[256];
        for (int i = 0; i < 256; i++) {
            int val = (int) (((i - 128) * factor) + 128);
            lookup[i] = (byte) Math.min(255, Math.max(0, val));
        }
        LookupOp op = new LookupOp(new ByteLookupTable(0, lookup), null);
        return op.filter(copyToIntRgb(image), null);
    }

    static BufferedImage applyFilter(BufferedImage image, Map<String, Object> params) {
        String filterName = (String) params.getOrDefault("name", "none");
        return switch (filterName.toLowerCase()) {
            case "grayscale" -> applyGrayscale(image);
            case "sepia" -> applySepia(image);
            case "blur" -> applyBlur(image);
            case "sharpen" -> applySharpen(image);
            default -> image;
        };
    }

    private static BufferedImage applyGrayscale(BufferedImage image) {
        BufferedImage result = copyToIntRgb(image);
        int[] pixels = pixelData(result);
        for (int index = 0; index < pixels.length; index++) {
            int rgb = pixels[index];
            int r = (rgb >> 16) & 0xFF;
            int g = (rgb >> 8) & 0xFF;
            int b = rgb & 0xFF;
            int gray = (int) (0.299 * r + 0.587 * g + 0.114 * b);
            pixels[index] = (gray << 16) | (gray << 8) | gray;
        }
        return result;
    }

    private static BufferedImage applySepia(BufferedImage image) {
        BufferedImage result = copyToIntRgb(image);
        int[] pixels = pixelData(result);
        for (int index = 0; index < pixels.length; index++) {
            int rgb = pixels[index];
            int r = (rgb >> 16) & 0xFF;
            int g = (rgb >> 8) & 0xFF;
            int b = rgb & 0xFF;
            int newR = Math.min(255, (int) (0.393 * r + 0.769 * g + 0.189 * b));
            int newG = Math.min(255, (int) (0.349 * r + 0.686 * g + 0.168 * b));
            int newB = Math.min(255, (int) (0.272 * r + 0.534 * g + 0.131 * b));
            pixels[index] = (newR << 16) | (newG << 8) | newB;
        }
        return result;
    }

    private static BufferedImage applyBlur(BufferedImage image) {
        float[] kernel = {
                1f / 9, 1f / 9, 1f / 9,
                1f / 9, 1f / 9, 1f / 9,
                1f / 9, 1f / 9, 1f / 9
        };
        ConvolveOp op = new ConvolveOp(new Kernel(3, 3, kernel), ConvolveOp.EDGE_NO_OP, null);
        return op.filter(copyToIntRgb(image), null);
    }

    private static BufferedImage applySharpen(BufferedImage image) {
        float[] kernel = {
                0, -1, 0,
                -1, 5, -1,
                0, -1, 0
        };
        ConvolveOp op = new ConvolveOp(new Kernel(3, 3, kernel), ConvolveOp.EDGE_NO_OP, null);
        return op.filter(copyToIntRgb(image), null);
    }

    private static int[] pixelData(BufferedImage image) {
        return ((DataBufferInt) image.getRaster().getDataBuffer()).getData();
    }

    private static int clampColor(int value) {
        return Math.min(255, Math.max(0, value));
    }
}
