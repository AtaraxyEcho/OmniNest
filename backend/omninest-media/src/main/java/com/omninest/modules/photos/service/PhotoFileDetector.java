package com.omninest.modules.photos.service;

import java.util.Locale;
import java.util.Set;
import org.springframework.stereotype.Service;

/**
 * 照片文件扩展名与解码能力检测器。
 *
 * @author OmniNest
 */
@Service
public class PhotoFileDetector {

    private static final Set<String> DECODABLE_EXTENSIONS = Set.of(
            "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif"
    );

    private static final Set<String> RAW_EXTENSIONS = Set.of(
            "raw", "cr2", "nef", "arw", "dng", "orf", "rw2", "raf"
    );

    /**
     * 判断文件是否可被 Thumbnailator 解码生成缩略图。
     * RAW/HEIC/AVIF/SVG 等格式 JVM ImageIO 不支持，需跳过缩略图生成。
     */
    public boolean isDecodable(String fileName) {
        return DECODABLE_EXTENSIONS.contains(extension(fileName));
    }

    /**
     * 判断文件是否为 RAW 格式。
     */
    public boolean isRaw(String fileName) {
        return RAW_EXTENSIONS.contains(extension(fileName));
    }

    /**
     * 从文件名提取小写扩展名。
     */
    public String extension(String fileName) {
        if (fileName == null) {
            return "";
        }
        int dot = fileName.lastIndexOf('.');
        return dot < 0 || dot == fileName.length() - 1
                ? ""
                : fileName.substring(dot + 1).toLowerCase(Locale.ROOT);
    }
}
