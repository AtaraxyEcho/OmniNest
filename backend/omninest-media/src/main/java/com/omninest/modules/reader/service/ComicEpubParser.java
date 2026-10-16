package com.omninest.modules.reader.service;

import com.omninest.modules.reader.service.model.ComicManifestDraft.ComicCatalogDraftNode;
import com.omninest.modules.reader.service.model.ComicManifestDraft.ComicPageDraft;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import lombok.extern.slf4j.Slf4j;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

/**
 * EPUB 漫画专用解析器。
 *
 * <p>解析流程：container.xml → OPF → manifest/spine → nav/toc → 页面图片。
 * 使用 XML parser 解析 OPF，不用正则。
 * 支持 RTL/LTR、SVG wrapper、URL decode、相对路径规范化。
 * 按 entry 流式读取，不全量加载图片到内存。
 *
 * @author OmniNest
 */
@Slf4j
public class ComicEpubParser {

    private static final long MAX_COVER_BYTES = 20L * 1024 * 1024;

    /**
     * EPUB 解析结果。
     */
    public record EpubParseResult(
            String title,
            String author,
            String readingDirection,
            List<EpubSpineItem> spine,
            Map<String, EpubManifestItem> manifest,
            List<EpubTocEntry> toc,
            EpubCover cover
    ) {}

    /**
     * EPUB 封面引用。
     *
     * @param path 压缩包内图片路径
     * @param mimeType 图片 MIME 类型
     */
    public record EpubCover(String path, String mimeType) {
    }

    /**
     * OPF manifest 条目。
     */
    public record EpubManifestItem(
            String id,
            String href,
            String mediaType,
            String properties
    ) {}

    /**
     * Spine 条目（阅读顺序）。
     */
    public record EpubSpineItem(
            String idref,
            boolean linear
    ) {}

    /**
     * 目录条目。
     */
    public record EpubTocEntry(
            String title,
            String href,
            int level,
            List<EpubTocEntry> children
    ) {}

    // 基于 EpubArchive 的流式解析方法，不在内存中保留图片正文。

    /**
     * 使用 EpubArchive 解析 EPUB 元数据（不读取图片）。
     * 随机访问小文件，不将整个 EPUB 读入内存。
     *
     * @param archive EPUB 文件的随机访问抽象
     * @return 解析结果
     */
    public EpubParseResult parseMetadata(EpubArchive archive) {
        try {
            // 1. 找 container.xml → OPF 路径
            String containerXml = archive.readSmallText("META-INF/container.xml");
            if (containerXml == null) {
                log.warn("EPUB 缺少 container.xml");
                return null;
            }
            String opfPath = parseContainerXml(containerXml);
            if (opfPath == null) {
                log.warn("EPUB container.xml 未指定 OPF 路径");
                return null;
            }

            // 2. 读取 OPF
            String opfXml = archive.readSmallText(opfPath);
            if (opfXml == null) {
                log.warn("EPUB OPF 文件不存在: pathLength={}", opfPath.toString().length());
                return null;
            }

            String opfDir = "";
            int lastSlash = opfPath.lastIndexOf('/');
            if (lastSlash > 0) {
                opfDir = opfPath.substring(0, lastSlash + 1);
            }

            // 3. 解析 OPF
            Document opfDoc = parseXml(opfXml);
            String title = extractMetadataText(opfDoc, "title");
            String author = extractMetadataText(opfDoc, "creator");

            // manifest
            Map<String, EpubManifestItem> manifest = parseManifest(opfDoc, opfDir);

            // spine
            List<EpubSpineItem> spine = parseSpine(opfDoc);

            // reading direction
            String readingDirection = null;
            NodeList spineNodes = opfDoc.getElementsByTagNameNS("*", "spine");
            Element spineElement = spineNodes.getLength() > 0 ? (Element) spineNodes.item(0) : null;
            if (spineElement != null) {
                readingDirection = spineElement.getAttribute("page-progression-direction");
                if (readingDirection.isEmpty()) readingDirection = null;
            }

            // 4. 尝试读取 nav.xhtml 或 toc.ncx
            List<EpubTocEntry> toc = new ArrayList<>();
            String navPath = findNavPath(manifest);
            if (navPath != null) {
                String navHtml = archive.readSmallText(navPath);
                if (navHtml != null) {
                    toc = parseNavToc(navHtml, getParentDir(navPath));
                }
            }
            if (toc.isEmpty()) {
                String ncxPath = findNcxPath(manifest);
                if (ncxPath != null) {
                    String ncxXml = archive.readSmallText(ncxPath);
                    if (ncxXml != null) {
                        toc = parseNcxToc(ncxXml, getParentDir(ncxPath));
                    }
                }
            }

            EpubCover cover = findCover(archive, opfDoc, opfDir, manifest, spine);
            return new EpubParseResult(title, author, readingDirection, spine, manifest, toc, cover);
        } catch (Exception e) {
            log.error("EPUB 元数据解析失败", e);
            return null;
        }
    }

    /**
     * 使用 EpubArchive 按 spine 顺序提取页面草稿。
     * 不将图片读入内存，只读取头部获取宽高。
     * sourcePath 保存图片 entry 路径，用于按需读取。
     *
     * @param archive    EPUB 文件的随机访问抽象
     * @param parseResult 之前解析的元数据
     * @param sourceId   来源 ID
     * @return 页面草稿列表
     */
    public List<ComicPageDraft> extractPageDrafts(EpubArchive archive, EpubParseResult parseResult, UUID sourceId) {
        List<ComicPageDraft> pages = new ArrayList<>();
        Map<String, String> spineCatalogKeys = buildSpineCatalogKeys(parseResult, sourceId);
        int pageIndex = 0;

        for (EpubSpineItem spineItem : parseResult.spine()) {
            if (!spineItem.linear()) continue;

            EpubManifestItem manifestItem = parseResult.manifest().get(spineItem.idref());
            if (manifestItem == null) continue;

            String xhtmlPath = manifestItem.href();

            // 读取 XHTML
            String xhtml = archive.readSmallText(xhtmlPath);
            if (xhtml == null) continue;

            // 提取主图片路径，并归一成压缩包里的真实条目名：声明的 href 可能大小写不一致，
            // 而按需流式解压只认精确条目名，存声明路径会让整本书每页 404。
            String declaredImagePath = extractMainImagePath(xhtml, xhtmlPath);
            if (declaredImagePath == null) {
                continue;
            }
            String imagePath = archive.resolveEntryName(declaredImagePath);
            if (imagePath == null) {
                continue;
            }

            // 读取图片头部获取宽高（不读取完整图片）
            int width = 0;
            int height = 0;
            byte[] header = archive.readImageHeader(imagePath, 65536);
            if (header != null && header.length > 24) {
                int[] dims = readImageDimensions(header);
                width = dims[0];
                height = dims[1];
            }

            String mime = detectMimeType(imagePath);
            long entrySize = archive.getEntrySize(imagePath);
            long entryCrc = archive.getEntryCrc(imagePath);

            // fingerprint 基于 entry 路径 + 大小 + CRC
            String fingerprint = computeEpubFingerprint(imagePath, entrySize, entryCrc);

            pages.add(new ComicPageDraft(
                    sourceId,
                    imagePath,      // sourcePath = 图片 entry 路径
                    pageIndex,
                    width,
                    height,
                    mime,
                    fingerprint,
                    entrySize > 0 ? entrySize : 0,
                    null,           // entryIndex (EPUB 无此概念)
                    // 目录键表按去 fragment 后的 href 建键，这里必须同口径查，
                    // 否则带 "#id" 的 manifest href 会查不到归属分卷。
                    spineCatalogKeys.get(stripFragment(xhtmlPath))
            ));
            pageIndex++;
        }

        return pages;
    }

    /**
     * 读取 EPUB 封面图片。
     *
     * @param archive EPUB 文件随机访问抽象
     * @param parseResult EPUB 元数据解析结果
     * @return 封面草稿，未找到有效封面时返回 null
     */
    public ReaderCoverDraft extractCover(EpubArchive archive, EpubParseResult parseResult) {
        if (parseResult == null || parseResult.cover() == null) {
            return null;
        }
        EpubCover cover = parseResult.cover();
        long entrySize = archive.getEntrySize(cover.path());
        if (entrySize <= 0 || entrySize > MAX_COVER_BYTES) {
            return null;
        }
        try (InputStream input = archive.openEntryStream(cover.path())) {
            if (input == null) {
                return null;
            }
            ByteArrayOutputStream output = new ByteArrayOutputStream((int) entrySize);
            byte[] buffer = new byte[8192];
            long totalRead = 0;
            int read;
            while ((read = input.read(buffer)) != -1) {
                totalRead += read;
                if (totalRead > MAX_COVER_BYTES) {
                    return null;
                }
                output.write(buffer, 0, read);
            }
            return new ReaderCoverDraft(output.toByteArray(), cover.mimeType(), cover.path());
        } catch (IOException exception) {
            log.warn("EPUB 封面读取失败: errorType={}", exception.getClass().getSimpleName());
            return null;
        }
    }

    /**
     * 将 EPUB nav/toc 转为目录草稿。
     *
     * @param parseResult EPUB 元数据解析结果
     * @param sourceId 来源 ID
     * @return 目录草稿列表
     */
    public List<ComicCatalogDraftNode> extractCatalogDrafts(EpubParseResult parseResult, UUID sourceId) {
        List<ComicCatalogDraftNode> nodes = new ArrayList<>();
        String sourceKey = buildSourceKey(sourceId);
        String sourceTitle = parseResult.title() == null || parseResult.title().isBlank()
                ? "漫画来源"
                : parseResult.title();
        nodes.add(new ComicCatalogDraftNode(
                sourceKey,
                null,
                sourceTitle,
                "COLLECTION",
                0,
                sourceId));
        appendCatalogDrafts(parseResult.toc(), sourceKey, nodes, sourceId);
        return nodes;
    }

    /**
     * 计算 EPUB 页面指纹（基于 entry 路径 + 大小 + CRC）。
     */
    private String computeEpubFingerprint(String path, long size, long crc) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            md.update(path.getBytes());
            md.update(String.valueOf(size).getBytes());
            md.update(String.valueOf(crc).getBytes());
            byte[] hash = md.digest();
            StringBuilder hex = new StringBuilder(16);
            for (int i = 0; i < 8; i++) {
                hex.append(String.format("%02x", hash[i]));
            }
            return hex.toString();
        } catch (Exception e) {
            return "";
        }
    }

    private Map<String, String> buildSpineCatalogKeys(EpubParseResult parseResult, UUID sourceId) {
        Map<String, String> byHref = new LinkedHashMap<>();
        String sourceKey = buildSourceKey(sourceId);
        appendTocHrefKeys(parseResult.toc(), sourceKey, byHref);

        Map<String, String> spineKeys = new LinkedHashMap<>();
        // 初始归属当前分卷的 source 键：无 TOC 的漫画、或排在首个 TOC 锚点之前的页面
        // 否则拿到 null，混排时这些页在目录里连一个分卷节点都没有。
        String currentKey = sourceKey;
        for (EpubSpineItem spineItem : parseResult.spine()) {
            EpubManifestItem manifestItem = parseResult.manifest().get(spineItem.idref());
            if (manifestItem == null) {
                continue;
            }
            String spineHref = stripFragment(manifestItem.href());
            String tocKey = byHref.get(spineHref);
            if (tocKey != null) {
                currentKey = tocKey;
            }
            spineKeys.put(spineHref, currentKey);
        }
        return spineKeys;
    }

    private void appendTocHrefKeys(List<EpubTocEntry> entries, String parentKey, Map<String, String> byHref) {
        int index = 0;
        for (EpubTocEntry entry : entries) {
            String key = buildTocKey(parentKey, entry.title(), index);
            if (entry.href() != null && !entry.href().isBlank()) {
                byHref.put(stripFragment(entry.href()), key);
            }
            appendTocHrefKeys(entry.children(), key, byHref);
            index++;
        }
    }

    private void appendCatalogDrafts(
            List<EpubTocEntry> entries,
            String parentKey,
            List<ComicCatalogDraftNode> nodes,
            UUID sourceId) {
        int index = 0;
        for (EpubTocEntry entry : entries) {
            String key = buildTocKey(parentKey, entry.title(), index);
            nodes.add(new ComicCatalogDraftNode(
                    key,
                    parentKey,
                    entry.title(),
                    detectCatalogNodeType(entry.title()),
                    index,
                    sourceId));
            appendCatalogDrafts(entry.children(), key, nodes, sourceId);
            index++;
        }
    }

    private String buildTocKey(String parentKey, String title, int index) {
        String titlePart = title == null || title.isBlank() ? "目录" + (index + 1) : title.trim();
        String segment = "toc:" + sanitizeCatalogSegment(titlePart) + ":" + index;
        return parentKey == null || parentKey.isBlank() ? segment : parentKey + "/" + segment;
    }

    private String sanitizeCatalogSegment(String value) {
        return value
                .replace('\\', '/')
                .replaceAll("[/\\s]+", "_")
                .replaceAll("[^\\p{IsHan}\\p{Alnum}_\\-]", "");
    }

    private String detectCatalogNodeType(String title) {
        if (title == null) {
            return "CHAPTER";
        }
        String lower = title.toLowerCase(Locale.ROOT);
        if (lower.matches(".*(season|第.+季|s\\d+).*")) {
            return "SEASON";
        }
        if (lower.matches(".*(volume|vol\\.?|第.+卷).*")) {
            return "VOLUME";
        }
        if (lower.contains("extra") || lower.contains("special") || lower.contains("番外")) {
            return "EXTRA";
        }
        return "CHAPTER";
    }

    // ── Private helpers ─────────────────────────────────────────

    private String parseContainerXml(String xml) {
        Document doc = parseXml(xml);
        NodeList rootfiles = doc.getElementsByTagNameNS("*", "rootfile");
        if (rootfiles.getLength() > 0) {
            return ((Element) rootfiles.item(0)).getAttribute("full-path");
        }
        return null;
    }

    private String extractMetadataText(Document opfDoc, String name) {
        NodeList nodes = opfDoc.getElementsByTagNameNS("*", name);
        if (nodes.getLength() > 0) {
            return nodes.item(0).getTextContent().trim();
        }
        return "";
    }

    private Map<String, EpubManifestItem> parseManifest(Document opfDoc, String opfDir) {
        Map<String, EpubManifestItem> map = new LinkedHashMap<>();
        NodeList items = opfDoc.getElementsByTagNameNS("*", "item");
        for (int i = 0; i < items.getLength(); i++) {
            Element el = (Element) items.item(i);
            String id = el.getAttribute("id");
            String href = el.getAttribute("href");
            String mediaType = el.getAttribute("media-type");
            String properties = el.getAttribute("properties");
            String resolvedHref = resolvePath(href, opfDir);
            map.put(id, new EpubManifestItem(id, resolvedHref, mediaType, properties));
        }
        return map;
    }

    private String buildSourceKey(UUID sourceId) {
        return "source:" + sourceId;
    }

    private EpubCover findCover(
            EpubArchive archive,
            Document opfDoc,
            String opfDir,
            Map<String, EpubManifestItem> manifest,
            List<EpubSpineItem> spine
    ) {
        NodeList metadataEntries = opfDoc.getElementsByTagNameNS("*", "meta");
        for (int i = 0; i < metadataEntries.getLength(); i++) {
            Element metadata = (Element) metadataEntries.item(i);
            if ("cover".equalsIgnoreCase(metadata.getAttribute("name"))) {
                EpubCover cover = coverFromManifestItem(archive, manifest.get(metadata.getAttribute("content")), manifest);
                if (cover != null) {
                    return cover;
                }
            }
        }

        for (EpubManifestItem item : manifest.values()) {
            if (hasProperty(item.properties(), "cover-image")) {
                EpubCover cover = coverFromManifestItem(archive, item, manifest);
                if (cover != null) {
                    return cover;
                }
            }
        }

        NodeList references = opfDoc.getElementsByTagNameNS("*", "reference");
        for (int i = 0; i < references.getLength(); i++) {
            Element reference = (Element) references.item(i);
            if (reference.getAttribute("type").toLowerCase(Locale.ROOT).contains("cover")) {
                String path = resolvePath(reference.getAttribute("href"), opfDir);
                EpubCover cover = resolveCoverPath(archive, path, null, manifest);
                if (cover != null) {
                    return cover;
                }
            }
        }

        for (EpubSpineItem spineItem : spine) {
            if (!spineItem.linear()) {
                continue;
            }
            EpubManifestItem item = manifest.get(spineItem.idref());
            if (item == null) {
                continue;
            }
            EpubCover cover = coverFromManifestItem(archive, item, manifest);
            if (cover != null) {
                return cover;
            }
        }
        return null;
    }

    private boolean hasProperty(String properties, String expectedProperty) {
        if (properties == null || properties.isBlank()) {
            return false;
        }
        for (String property : properties.trim().split("\\s+")) {
            if (expectedProperty.equals(property)) {
                return true;
            }
        }
        return false;
    }

    private EpubCover coverFromManifestItem(
            EpubArchive archive,
            EpubManifestItem item,
            Map<String, EpubManifestItem> manifest
    ) {
        if (item == null) {
            return null;
        }
        return resolveCoverPath(archive, item.href(), item.mediaType(), manifest);
    }

    private EpubCover resolveCoverPath(
            EpubArchive archive,
            String path,
            String mimeType,
            Map<String, EpubManifestItem> manifest
    ) {
        if (path == null || path.isBlank()) {
            return null;
        }
        String normalizedPath = stripFragment(path);
        String normalizedMimeType = mimeType == null ? "" : mimeType.toLowerCase(Locale.ROOT);
        if (normalizedMimeType.startsWith("image/") || archive.getEntrySize(normalizedPath) > 0
                && isImagePath(normalizedPath)) {
            String resolvedMimeType = normalizedMimeType.startsWith("image/")
                    ? normalizedMimeType
                    : detectMimeType(normalizedPath);
            return new EpubCover(normalizedPath, resolvedMimeType);
        }

        String document = archive.readSmallText(normalizedPath);
        if (document == null) {
            return null;
        }
        String imagePath = extractMainImagePath(document, normalizedPath);
        if (imagePath == null || archive.getEntrySize(imagePath) <= 0) {
            return null;
        }
        String resolvedMimeType = manifest.values().stream()
                .filter(candidate -> imagePath.equals(stripFragment(candidate.href())))
                .map(EpubManifestItem::mediaType)
                .filter(candidate -> candidate != null && candidate.startsWith("image/"))
                .findFirst()
                .orElseGet(() -> detectMimeType(imagePath));
        return new EpubCover(imagePath, resolvedMimeType);
    }

    private boolean isImagePath(String path) {
        String lower = path.toLowerCase(Locale.ROOT);
        return lower.endsWith(".jpg")
                || lower.endsWith(".jpeg")
                || lower.endsWith(".png")
                || lower.endsWith(".gif")
                || lower.endsWith(".webp")
                || lower.endsWith(".bmp")
                || lower.endsWith(".avif");
    }

    private List<EpubSpineItem> parseSpine(Document opfDoc) {
        List<EpubSpineItem> list = new ArrayList<>();
        NodeList spines = opfDoc.getElementsByTagNameNS("*", "spine");
        if (spines.getLength() == 0) {
            return list;
        }

        Element spine = (Element) spines.item(0);
        NodeList itemrefs = spine.getElementsByTagNameNS("*", "itemref");
        for (int i = 0; i < itemrefs.getLength(); i++) {
            Element el = (Element) itemrefs.item(i);
            String idref = el.getAttribute("idref");
            String linear = el.getAttribute("linear");
            boolean isLinear = !"no".equals(linear);
            list.add(new EpubSpineItem(idref, isLinear));
        }
        return list;
    }

    /**
     * 解析 nav.xhtml 中的目录。
     */
    private List<EpubTocEntry> parseNavToc(String navXml, String opfDir) {
        List<EpubTocEntry> entries = new ArrayList<>();
        try {
            Document doc = parseXml(navXml);
            NodeList navs = doc.getElementsByTagNameNS("*", "nav");
            Element tocNav = null;
            for (int i = 0; i < navs.getLength(); i++) {
                Element el = (Element) navs.item(i);
                String type = el.getAttributeNS("http://www.idpf.org/2007/ops", "type");
                if ("toc".equals(type)) {
                    tocNav = el;
                    break;
                }
            }
            if (tocNav == null) {
                return entries;
            }

            NodeList ols = tocNav.getElementsByTagNameNS("*", "ol");
            if (ols.getLength() > 0) {
                parseNavList((Element) ols.item(0), entries, 0, opfDir);
            }
        } catch (Exception e) {
            log.warn("nav.xhtml 解析失败: {}", e.getMessage());
        }
        return entries;
    }

    private void parseNavList(Element ol, List<EpubTocEntry> entries, int level, String opfDir) {
        NodeList childNodes = ol.getChildNodes();
        for (int i = 0; i < childNodes.getLength(); i++) {
            Node child = childNodes.item(i);
            if (!(child instanceof Element li) || !"li".equalsIgnoreCase(li.getLocalName())) {
                continue;
            }

            Element anchor = findDirectChild(li, "a");
            Element span = findDirectChild(li, "span");
            String title = anchor != null ? anchor.getTextContent().trim()
                    : span != null ? span.getTextContent().trim() : "";
            String href = anchor != null ? anchor.getAttribute("href") : "";
            String resolvedHref = href.isBlank() ? "" : resolvePath(href, opfDir);

            List<EpubTocEntry> children = new ArrayList<>();
            Element nestedOl = findDirectChild(li, "ol");
            if (nestedOl != null) {
                parseNavList(nestedOl, children, level + 1, opfDir);
            }

            entries.add(new EpubTocEntry(title, resolvedHref, level, children));
        }
    }

    private Element findDirectChild(Element parent, String tagName) {
        NodeList childNodes = parent.getChildNodes();
        for (int i = 0; i < childNodes.getLength(); i++) {
            Node child = childNodes.item(i);
            if (child instanceof Element element && hasName(element, tagName)) {
                return element;
            }
        }
        return null;
    }

    private boolean hasName(Element element, String tagName) {
        String localName = element.getLocalName();
        String nodeName = element.getNodeName();
        return tagName.equalsIgnoreCase(localName) || tagName.equalsIgnoreCase(nodeName);
    }

    /**
     * 解析 toc.ncx (EPUB2)。
     */
    private List<EpubTocEntry> parseNcxToc(String ncxXml, String opfDir) {
        List<EpubTocEntry> entries = new ArrayList<>();
        try {
            Document doc = parseXml(ncxXml);
            NodeList navMaps = doc.getElementsByTagNameNS("*", "navMap");
            if (navMaps.getLength() > 0) {
                parseNcxNavPoints((Element) navMaps.item(0), entries, 0, opfDir);
            }
        } catch (Exception e) {
            log.warn("toc.ncx 解析失败: {}", e.getMessage());
        }
        return entries;
    }

    private void parseNcxNavPoints(Element parent, List<EpubTocEntry> entries, int level, String opfDir) {
        NodeList points = parent.getElementsByTagNameNS("*", "navPoint");
        for (int i = 0; i < points.getLength(); i++) {
            Element point = (Element) points.item(i);
            if (point.getParentNode() != parent) {
                continue;
            }

            NodeList labels = point.getElementsByTagNameNS("*", "text");
            String title = labels.getLength() > 0 ? labels.item(0).getTextContent().trim() : "";

            NodeList contents = point.getElementsByTagNameNS("*", "content");
            String href = contents.getLength() > 0
                    ? ((Element) contents.item(0)).getAttribute("src") : "";

            String resolvedHref = resolvePath(href, opfDir);

            List<EpubTocEntry> children = new ArrayList<>();
            parseNcxNavPoints(point, children, level + 1, opfDir);

            entries.add(new EpubTocEntry(title, resolvedHref, level, children));
        }
    }

    private static final Pattern HTML_COMMENT_PATTERN = Pattern.compile("<!--[\\s\\S]*?-->");
    private static final Pattern IMG_TAG_PATTERN = Pattern.compile("<img\\b[^>]*>", Pattern.CASE_INSENSITIVE);
    private static final Pattern SVG_IMAGE_TAG_PATTERN = Pattern.compile("<image\\b[^>]*>", Pattern.CASE_INSENSITIVE);

    /**
     * 从 XHTML 中提取主图片路径。
     * 支持：<img src="">、SVG <image href="">
     *
     * <p>属性只能在标签自身的闭合 {@code >} 之内取：从 {@code <img} 一直截到文末时，
     * 一张没有 src 的图会把后文别的元素的 src 抓来当主图。注释里的排版留痕
     * （{@code <!-- <img src="old.jpg"> -->}）同理必须整段剥掉，否则被注释掉的旧图成为封面。
     */
    private String extractMainImagePath(String xhtml, String xhtmlPath) {
        String cleaned = HTML_COMMENT_PATTERN.matcher(xhtml).replaceAll("");

        Matcher imgMatcher = IMG_TAG_PATTERN.matcher(cleaned);
        while (imgMatcher.find()) {
            String src = extractAttribute(imgMatcher.group(), "src");
            if (src != null && !src.isEmpty()) {
                return resolveRelativePath(src, xhtmlPath);
            }
        }

        Matcher svgMatcher = SVG_IMAGE_TAG_PATTERN.matcher(cleaned);
        while (svgMatcher.find()) {
            String tag = svgMatcher.group();
            String href = extractAttribute(tag, "href");
            if (href == null || href.isEmpty()) {
                href = extractAttribute(tag, "xlink:href");
            }
            if (href != null && !href.isEmpty()) {
                return resolveRelativePath(href, xhtmlPath);
            }
        }

        return null;
    }

    /**
     * 在单个标签内取属性值。
     *
     * <p>HTML 的属性名不区分大小写（{@code <IMG SRC="...">} 与 {@code <img src="...">} 同义），
     * 按字面量匹配会让大写写法的漫画页一张主图都取不到。属性名还必须以空白起头，
     * 否则 {@code data-src} 会被当成 {@code src} 命中，把懒加载占位当真图抓走。
     */
    private String extractAttribute(String tag, String attrName) {
        String normalized = tag.toLowerCase(Locale.ROOT);
        String needle = attrName.toLowerCase(Locale.ROOT) + "=";
        int idx = normalized.indexOf(needle);
        while (idx >= 0) {
            int valueStart = idx + needle.length();
            if (idx > 0 && !Character.isWhitespace(tag.charAt(idx - 1))) {
                idx = normalized.indexOf(needle, valueStart);
                continue;
            }
            if (valueStart >= tag.length()) {
                break;
            }
            char quote = tag.charAt(valueStart);
            if (quote == '"' || quote == '\'') {
                int end = tag.indexOf(quote, valueStart + 1);
                if (end > valueStart) {
                    return tag.substring(valueStart + 1, end);
                }
            } else {
                int end = valueStart;
                while (end < tag.length()
                        && !Character.isWhitespace(tag.charAt(end))
                        && tag.charAt(end) != '>') {
                    end++;
                }
                if (end > valueStart) {
                    return tag.substring(valueStart, end);
                }
            }
            idx = normalized.indexOf(needle, valueStart);
        }
        return null;
    }

    /**
     * 解析相对路径（基于 XHTML 文件路径）。
     */
    private String resolveRelativePath(String relativeTo, String basePath) {
        if (relativeTo.startsWith("http://") || relativeTo.startsWith("https://")) {
            return relativeTo;
        }
        String decoded = urlDecode(relativeTo);
        String baseDir = basePath.contains("/") ? basePath.substring(0, basePath.lastIndexOf('/') + 1) : "";
        return normalizePath(baseDir + decoded);
    }

    /**
     * 解析 manifest href（基于 OPF 目录）。
     */
    private String resolvePath(String href, String opfDir) {
        if (href.startsWith("http://") || href.startsWith("https://")) {
            return href;
        }
        String decoded = urlDecode(href);
        if (decoded.startsWith("/")) {
            return decoded.substring(1);
        }
        return normalizePath(opfDir + decoded);
    }

    /**
     * 规范化路径：处理 ../、./、重复斜杠。
     *
     * <p>百分号解码只在 resolvePath / resolveRelativePath 做一次，这里不再解码：同一串解码两遍会把
     * 文件名里字面量的 {@code %252D} 之类读成 {@code %2D}，归档条目随即找不到。
     */
    private String normalizePath(String path) {
        if (path == null) {
            return "";
        }
        String normalizedInput = path.replace('\\', '/');
        Deque<String> segments = new ArrayDeque<>();
        for (String segment : normalizedInput.split("/+")) {
            if (segment.isEmpty() || ".".equals(segment)) {
                continue;
            }
            if ("..".equals(segment)) {
                if (!segments.isEmpty()) {
                    segments.removeLast();
                }
                continue;
            }
            segments.addLast(segment);
        }
        return String.join("/", segments);
    }

    /**
     * 按 URI 百分号编码解码路径。
     *
     * <p>{@link URLDecoder} 是表单解码器，会把字面量 {@code +} 变成空格；EPUB 的 href 是 URI 路径，
     * 文件名里的加号必须先转义再解，否则 "C++/001.xhtml" 会变成 "C++ /001.xhtml"（客户端那份宽容解码
     * 同样只解百分号、不动加号）。
     */
    private String urlDecode(String s) {
        if (s == null) {
            return "";
        }
        try {
            return URLDecoder.decode(s.replace("+", "%2B"), StandardCharsets.UTF_8.name());
        } catch (Exception e) {
            return s;
        }
    }

    private String stripFragment(String href) {
        if (href == null) {
            return "";
        }
        int hashIndex = href.indexOf('#');
        return hashIndex >= 0 ? href.substring(0, hashIndex) : href;
    }

    private String getParentDir(String path) {
        if (path == null) {
            return "";
        }
        int slashIndex = path.lastIndexOf('/');
        return slashIndex >= 0 ? path.substring(0, slashIndex + 1) : "";
    }

    private Document parseXml(String xml) {
        return ReaderXmlSafety.parse(xml);
    }

    /**
     * 页面图宽高嗅探统一走 {@link ComicPageAssetService} 的那一份实现。
     *
     * <p>两处各写一份时，同一张 WebP 在归档解析与页面资产落库两条路径上会得出不同结论：
     * 一边记成有尺寸、另一边记成 0x0，清单与装页就按两套高度走。
     */
    private int[] readImageDimensions(byte[] data) {
        return ComicPageAssetService.readImageDimensions(data);
    }

    /**
     * 从 OPF manifest 中查找 nav 文档路径（properties 词元含 "nav"）。
     */
    private String findNavPath(Map<String, EpubManifestItem> manifest) {
        for (EpubManifestItem item : manifest.values()) {
            if (hasProperty(item.properties(), "nav")) {
                return item.href();
            }
        }
        return null;
    }

    /**
     * 从 OPF manifest 中查找 NCX 路径（media-type 为 application/x-dtbncx+xml）。
     */
    private String findNcxPath(Map<String, EpubManifestItem> manifest) {
        for (EpubManifestItem item : manifest.values()) {
            if ("application/x-dtbncx+xml".equals(item.mediaType())) {
                return item.href();
            }
        }
        return null;
    }

    private String detectMimeType(String path) {
        if (path == null) {
            return "application/octet-stream";
        }
        String lower = path.toLowerCase(Locale.ROOT);
        if (lower.endsWith(".png")) return "image/png";
        if (lower.endsWith(".gif")) return "image/gif";
        if (lower.endsWith(".webp")) return "image/webp";
        if (lower.endsWith(".svg")) return "image/svg+xml";
        if (lower.endsWith(".bmp")) return "image/bmp";
        if (lower.endsWith(".avif")) return "image/avif";
        return "image/jpeg";
    }
}
