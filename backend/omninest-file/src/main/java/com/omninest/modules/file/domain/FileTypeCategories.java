package com.omninest.modules.file.domain;

import java.util.Locale;
import java.util.Set;

/**
 * 文件业务分类计算。
 *
 * <p>分类由扩展名与 MIME 共同决定，扩展名优先用于 comic/novel 特判；
 * 结果写入 {@code file_nodes.category}，供列表接口在数据库层过滤分页。
 */
public final class FileTypeCategories {

    public static final String IMAGE = "image";
    public static final String VIDEO = "video";
    public static final String AUDIO = "audio";
    public static final String DOCUMENT = "document";
    public static final String NOVEL = "novel";
    public static final String COMIC = "comic";
    public static final String ARCHIVE = "archive";
    public static final String OTHER = "other";

    private static final Set<String> COMIC_EXTENSIONS = Set.of("cbz", "cbr", "cb7", "cbt");
    private static final Set<String> NOVEL_EXTENSIONS = Set.of("epub", "mobi", "azw3", "azw", "fb2", "txt");
    private static final Set<String> IMAGE_EXTENSIONS = Set.of(
            "jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "heic", "heif", "avif");
    private static final Set<String> VIDEO_EXTENSIONS = Set.of(
            "mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "flv", "ts", "m2ts", "3gp");
    private static final Set<String> AUDIO_EXTENSIONS = Set.of(
            "mp3", "flac", "aac", "m4a", "ogg", "opus", "wav", "aiff", "aif", "alac", "wma");
    private static final Set<String> DOCUMENT_EXTENSIONS = Set.of(
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "md", "rtf", "csv");
    private static final Set<String> ARCHIVE_EXTENSIONS = Set.of("zip", "rar", "7z", "tar", "gz", "bz2", "xz");

    private FileTypeCategories() {
    }

    /**
     * 解析文件分类。
     *
     * @param name     文件名
     * @param mimeType MIME 类型，可空
     * @param nodeType 节点类型；非 FILE 返回 null
     * @return 分类编码，非文件返回 null
     */
    public static String resolve(String name, String mimeType, String nodeType) {
        if (!"FILE".equals(nodeType)) {
            return null;
        }
        String extension = resolveExtension(name);
        String normalizedMime = mimeType == null
                ? ""
                : mimeType.trim().toLowerCase(Locale.ROOT);
        if (COMIC_EXTENSIONS.contains(extension)) {
            return COMIC;
        }
        if (NOVEL_EXTENSIONS.contains(extension)) {
            return NOVEL;
        }
        if (normalizedMime.startsWith("image/") || IMAGE_EXTENSIONS.contains(extension)) {
            return IMAGE;
        }
        if (normalizedMime.startsWith("video/") || VIDEO_EXTENSIONS.contains(extension)) {
            return VIDEO;
        }
        if (normalizedMime.startsWith("audio/") || AUDIO_EXTENSIONS.contains(extension)) {
            return AUDIO;
        }
        if (DOCUMENT_EXTENSIONS.contains(extension) || isDocumentMimeType(normalizedMime)) {
            return DOCUMENT;
        }
        if (ARCHIVE_EXTENSIONS.contains(extension) || isArchiveMimeType(normalizedMime)) {
            return ARCHIVE;
        }
        return OTHER;
    }

    private static String resolveExtension(String fileName) {
        if (fileName == null) {
            return "";
        }
        int dotIndex = fileName.lastIndexOf('.');
        if (dotIndex < 0 || dotIndex == fileName.length() - 1) {
            return "";
        }
        return fileName.substring(dotIndex + 1).toLowerCase(Locale.ROOT);
    }

    private static boolean isDocumentMimeType(String mimeType) {
        return mimeType.equals("application/pdf")
                || mimeType.equals("text/markdown")
                || mimeType.equals("text/csv")
                || mimeType.equals("application/msword")
                || mimeType.equals(
                        "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
                || mimeType.equals("application/vnd.ms-excel")
                || mimeType.equals(
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
                || mimeType.equals("application/vnd.ms-powerpoint")
                || mimeType.equals(
                        "application/vnd.openxmlformats-officedocument.presentationml.presentation");
    }

    private static boolean isArchiveMimeType(String mimeType) {
        return mimeType.equals("application/zip")
                || mimeType.equals("application/x-rar-compressed")
                || mimeType.equals("application/x-7z-compressed")
                || mimeType.equals("application/x-tar")
                || mimeType.equals("application/gzip")
                || mimeType.equals("application/x-bzip2");
    }
}
