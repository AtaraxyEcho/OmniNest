package com.omninest.modules.reader.service;

import java.io.IOException;
import java.nio.file.Path;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 阅读文件类型检测工具。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderFileDetector {

    private static final String EPUB = "EPUB";
    private static final String TXT = "TXT";
    private static final String CBZ = "CBZ";
    private static final String ZIP = "ZIP";
    private static final String PDF = "PDF";
    private static final String CONTENT_KIND_COMIC = "COMIC";
    private static final String CONTENT_KIND_TEXT = "TEXT";
    private static final int DEFAULT_TEXT_CHARS_THRESHOLD = 100;

    private final ReaderArchiveSafetyPolicy archiveSafetyPolicy;

    /**
     * 判断文件是否为阅读器支持的类型。
     * 支持 EPUB、TXT、CBZ、ZIP 和 PDF。
     *
     * @param fileName 文件名
     * @return 是否为阅读器文件
     */
    public boolean isReaderFile(String fileName) {
        if (fileName == null || fileName.isBlank()) {
            return false;
        }
        String lower = fileName.toLowerCase(Locale.ROOT);
        return lower.endsWith(".epub") || lower.endsWith(".txt")
                || lower.endsWith(".cbz") || lower.endsWith(".zip")
                || lower.endsWith(".pdf");
    }

    /**
     * 检测文件类型。
     *
     * @param fileName 文件名
     * @return 文件类型（EPUB / TXT / CBZ / ZIP / PDF），不支持时返回 null
     */
    public String detectType(String fileName) {
        if (fileName == null || fileName.isBlank()) {
            return null;
        }
        String lower = fileName.toLowerCase(Locale.ROOT);
        if (lower.endsWith(".epub")) {
            return EPUB;
        }
        if (lower.endsWith(".txt")) {
            return TXT;
        }
        if (lower.endsWith(".cbz")) {
            return CBZ;
        }
        if (lower.endsWith(".zip")) {
            return ZIP;
        }
        if (lower.endsWith(".pdf")) {
            return PDF;
        }
        return null;
    }

    /**
     * 根据文件类型推断 contentKind。
     *
     * @param fileType 文件类型（EPUB / TXT / CBZ / ZIP / PDF）
     * @return 内容类型（TEXT 或 COMIC）
     */
    public String detectContentKind(String fileType) {
        if (CBZ.equals(fileType) || ZIP.equals(fileType)) {
            return "COMIC";
        }
        return "TEXT";
    }

    /**
     * 从本地临时 EPUB 文件检测是否为固定版式或声明为漫画。
     *
     * @param epubPath EPUB 本地文件路径
     * @return true 表示 fixed-layout 或漫画声明 EPUB
     */
    public boolean isFixedLayoutEpub(Path epubPath) {
        if (epubPath == null) {
            return false;
        }
        try (EpubArchive archive = new EpubArchive(epubPath, archiveSafetyPolicy)) {
            String container = archive.readSmallText("META-INF/container.xml");
            if (container == null || container.isBlank()) {
                return false;
            }
            String opfPath = extractOpfPath(container);
            if (opfPath == null || opfPath.isBlank()) {
                return false;
            }
            String opf = archive.readSmallText(opfPath);
            if (opf == null) {
                return false;
            }
            return isComicDeclared(opf);
        } catch (IOException | RuntimeException e) {
            log.debug("EPUB 固定版式文件检测失败: {}", e.getMessage());
            return false;
        }
    }

    /**
     * 从 OPF 元数据判断是否声明为漫画/固定版式。
     * 优先命中 EPUB 规范 fixed-layout 或出版商自定义漫画标记。
     *
     * @param opfXml OPF 文件内容
     * @return true 表示命中漫画声明
     */
    private boolean isComicDeclared(String opfXml) {
        return opfXml.contains("pre-paginated")
                || opfXml.contains("book-type\">comic")
                || opfXml.contains("fixed-layout\">true");
    }

    /**
     * 按正文文本密度判定 EPUB 内容形态。
     * 每文本条目平均去标签纯文本字符数低于阈值时判为漫画，否则为文本。
     *
     * @param epubPath EPUB 本地文件路径
     * @param textCharsThreshold 平均正文字符阈值
     * @return 内容形态（COMIC / TEXT）
     */
    public String detectContentKindByTextDensity(Path epubPath, int textCharsThreshold) {
        if (epubPath == null) {
            return CONTENT_KIND_TEXT;
        }
        long textEntries = 0;
        long textChars = 0;
        try (EpubArchive archive = new EpubArchive(epubPath, archiveSafetyPolicy)) {
            var entries = archive.entryNames();
            if (entries.isEmpty()) {
                return CONTENT_KIND_TEXT;
            }
            for (String entry : entries) {
                String lower = entry.toLowerCase(Locale.ROOT);
                if (!lower.endsWith(".xhtml") && !lower.endsWith(".html")
                        && !lower.endsWith(".htm")) {
                    continue;
                }
                String content = archive.readSmallText(entry);
                if (content == null) {
                    continue;
                }
                textEntries++;
                String stripped = content.replaceAll("<[^>]+>", " ")
                        .replaceAll("\\s+", "");
                textChars += stripped.length();
            }
            if (textEntries == 0) {
                return CONTENT_KIND_COMIC;
            }
            return (textChars / textEntries) < textCharsThreshold
                    ? CONTENT_KIND_COMIC
                    : CONTENT_KIND_TEXT;
        } catch (IOException | RuntimeException e) {
            log.debug("EPUB 文本密度检测失败: {}", e.getMessage());
            return CONTENT_KIND_TEXT;
        }
    }

    /**
     * 综合判定 EPUB 内容形态：规范声明优先，文本密度兜底。
     *
     * @param epubPath EPUB 本地文件路径
     * @param textCharsThreshold 平均正文字符阈值
     * @return 内容形态（COMIC / TEXT）
     */
    public String detectContentKind(Path epubPath, int textCharsThreshold) {
        try (EpubArchive archive = new EpubArchive(epubPath, archiveSafetyPolicy)) {
            String container = archive.readSmallText("META-INF/container.xml");
            if (container == null || container.isBlank()) {
                return CONTENT_KIND_TEXT;
            }
            String opfPath = extractOpfPath(container);
            if (opfPath == null || opfPath.isBlank()) {
                return CONTENT_KIND_TEXT;
            }
            String opf = archive.readSmallText(opfPath);
            if (opf != null && isComicDeclared(opf)) {
                return CONTENT_KIND_COMIC;
            }
        } catch (IOException | RuntimeException e) {
            log.debug("EPUB 声明检测失败，回退文本密度: {}", e.getMessage());
        }
        return detectContentKindByTextDensity(epubPath, textCharsThreshold);
    }

    /**
     * 从 container.xml 中提取 OPF 文件的完整路径。
     *
     * @param containerXml container.xml 内容
     * @return OPF 文件路径，未找到时返回 null
     */
    private String extractOpfPath(String containerXml) {
        // 匹配 <rootfile full-path="..." />
        Pattern pattern = Pattern.compile("full-path\\s*=\\s*\"([^\"]+)\"");
        Matcher matcher = pattern.matcher(containerXml);
        if (matcher.find()) {
            return matcher.group(1);
        }
        return null;
    }
}
