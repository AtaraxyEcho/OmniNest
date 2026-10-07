package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.reader.service.ComicEpubParser.EpubManifestItem;
import com.omninest.modules.reader.service.ComicEpubParser.EpubParseResult;
import com.omninest.modules.reader.service.ComicEpubParser.EpubSpineItem;
import com.omninest.modules.reader.service.ComicEpubParser.EpubTocEntry;
import com.omninest.modules.reader.service.ReaderEpubArchiveStager.StagedArchive;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import java.io.BufferedReader;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.function.IntConsumer;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * EPUB/TXT 文本书籍流式解析器，生成可持久化章节清单。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderTextParser {

    private static final int CHARSET_SAMPLE_BYTES = 64 * 1024;
    /**
     * 章节标题入库长度上限。数据库列为 varchar(500)，此处留出前缀与截断标记余量，
     * 避免畸形 TXT 的超长"标题行"直接触发数据完整性异常。
     */
    private static final int MAX_CHAPTER_TITLE_CHARS = 200;

    private static final Pattern TXT_CHAPTER_PATTERN = Pattern.compile(
            "^(第.{1,24}[章回节卷篇]|(?i:chapter)\\s+[0-9ivxlcdm]+|"
                    + "(?i:part)\\s+[0-9ivxlcdm]+)[\\s　:：.-]?.*$"
    );

    /**
     * 数字序号章节标题。要求序号后紧跟非数字非 punctuation 的正文首字符且整体不长，
     * 以免"3.5 亿元的采购"这类行被误判为章节。
     */
    private static final Pattern TXT_NUMERIC_CHAPTER_PATTERN = Pattern.compile(
            "^[0-9]{1,3}[.、][ \\t]*[^0-9.、\\s].{0,28}$"
    );

    /** 扫描进度上报区间，25 为载入后基线，80 为扫描完成。 */
    private static final int PROGRESS_SCAN_START = 25;
    private static final int PROGRESS_SCAN_END = 80;
    private static final int PROGRESS_SCAN_STEP = 5;

    private final FileMetadataQueryService fileMetadataQueryService;
    private final FileQueryService fileQueryService;
    private final ReaderEpubArchiveStager epubArchiveStager;
    private final ReaderArchiveSafetyPolicy archiveSafetyPolicy;

    /**
     * 解析文本书籍。
     *
     * @param fileNodeId 文件节点 ID
     * @param fileFormat 文件格式
     * @param progressReporter 进度回调
     * @return 解析草稿
     */
    public ParsedTextBook parse(UUID fileNodeId, String fileFormat, IntConsumer progressReporter) {
        FileDescriptor fileNode = loadFileNode(fileNodeId);
        progressReporter.accept(25);
        if ("EPUB".equalsIgnoreCase(fileFormat)) {
            return parseEpub(fileNode, progressReporter);
        }
        if ("TXT".equalsIgnoreCase(fileFormat)) {
            return parseTxt(fileNode, progressReporter);
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "不支持的文本书籍格式");
    }

    private ParsedTextBook parseEpub(FileDescriptor fileNode, IntConsumer progressReporter) {
        try (StagedArchive staged = epubArchiveStager.stage(fileNode);
             EpubArchive archive = new EpubArchive(staged.path(), archiveSafetyPolicy)) {
            ComicEpubParser epubParser = new ComicEpubParser();
            EpubParseResult metadata = epubParser.parseMetadata(archive);
            if (metadata == null || metadata.spine().isEmpty()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "EPUB 未包含可阅读章节");
            }
            Map<String, TocMetadata> tocByPath = flattenToc(metadata.toc());
            List<TextChapterDraft> chapters = new ArrayList<>();
            for (EpubSpineItem spineItem : metadata.spine()) {
                if (!spineItem.linear()) {
                    continue;
                }
                EpubManifestItem manifestItem = metadata.manifest().get(spineItem.idref());
                if (!isTextContent(manifestItem)) {
                    continue;
                }
                String contentPath = stripFragment(manifestItem.href());
                TocMetadata toc = tocByPath.get(contentPath);
                String title = toc == null || toc.title().isBlank()
                        ? "第 " + (chapters.size() + 1) + " 章"
                        : clampTitle(toc.title());
                String xhtml = archive.readSmallText(contentPath);
                int charCount = xhtml == null ? 0 : countXhtmlCharacters(xhtml, contentPath);
                chapters.add(new TextChapterDraft(
                        chapters.size(),
                        "chapter_" + chapters.size(),
                        title,
                        contentPath,
                        null,
                        null,
                        charCount,
                        toc == null ? 0 : toc.level()
                ));
            }
            if (chapters.isEmpty()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "EPUB 未包含可阅读正文");
            }
            progressReporter.accept(80);
            ReaderCoverDraft cover = epubParser.extractCover(archive, metadata);
            return new ParsedTextBook(metadata.title(), metadata.author(), null, chapters, cover);
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "EPUB 解析失败");
        }
    }

    private ParsedTextBook parseTxt(FileDescriptor fileNode, IntConsumer progressReporter) {
        Charset charset = detectCharset(fileNode);
        List<TextChapterDraft> chapters = new ArrayList<>();
        long currentOffset = 0L;
        long chapterStart = 0L;
        String chapterTitle = "正文";
        int lastReportedProgress = PROGRESS_SCAN_START;
        long totalBytes = Math.max(1L, fileNode.sizeBytes());
        try (FileContentStream content = fileQueryService.openOwnedFileContent(
                fileNode.ownerUserId(),
                fileNode.id())) {
            CountingInputStream counting = new CountingInputStream(content.inputStream());
            BufferedReader reader = new BufferedReader(new InputStreamReader(counting, charset));
            String line;
            boolean firstLine = true;
            while ((line = reader.readLine()) != null) {
                if (!firstLine) {
                    // 行终止符按 1 个字符计入偏移域，且只在确实读到下一行时累加，
                    // 避免为无终止符的末行多加 1。
                    currentOffset += 1L;
                }
                if (firstLine && !line.isEmpty() && line.charAt(0) == '\uFEFF') {
                    line = line.substring(1);
                }
                firstLine = false;
                // strip() 按 Unicode 空白判定，可去除全角空格缩进；trim() 只去除 <= U+0020。
                String normalized = line.strip();
                if (isChapterTitle(normalized)) {
                    if (currentOffset == 0L) {
                        chapterTitle = normalized;
                    } else if (currentOffset > chapterStart) {
                        chapters.add(txtDraft(chapters.size(), chapterTitle, chapterStart, currentOffset));
                        chapterStart = currentOffset;
                        chapterTitle = normalized;
                    }
                }
                currentOffset += line.length();
                lastReportedProgress = reportScanProgress(
                        progressReporter, counting.consumed(), totalBytes, lastReportedProgress);
            }
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "TXT 解析失败");
        }
        if (currentOffset > chapterStart || chapters.isEmpty()) {
            chapters.add(txtDraft(chapters.size(), chapterTitle, chapterStart, currentOffset));
        }
        progressReporter.accept(PROGRESS_SCAN_END);
        return new ParsedTextBook(null, null, charset.name(), chapters, null);
    }

    /**
     * 判断归一化后的行是否为章节标题行。
     *
     * @param normalized 已去除首尾空白的行
     * @return 命中标题模式时返回 true
     */
    private boolean isChapterTitle(String normalized) {
        if (normalized.isEmpty()) {
            return false;
        }
        return TXT_CHAPTER_PATTERN.matcher(normalized).matches()
                || TXT_NUMERIC_CHAPTER_PATTERN.matcher(normalized).matches();
    }

    /**
     * 按已读字节比例上报扫描进度。进度回调同时是取消检查点，回调可抛出取消异常中断扫描。
     *
     * @param progressReporter 进度回调
     * @param consumedBytes 已消耗字节数
     * @param totalBytes 文件总字节数
     * @param lastReported 最近一次已上报值
     * @return 最近一次已上报的进度值
     */
    private int reportScanProgress(
            IntConsumer progressReporter, long consumedBytes, long totalBytes, int lastReported) {
        long span = PROGRESS_SCAN_END - PROGRESS_SCAN_START;
        int progress = (int) (PROGRESS_SCAN_START
                + Math.min(span, consumedBytes * span / Math.max(1L, totalBytes)));
        if (progress < lastReported + PROGRESS_SCAN_STEP) {
            return lastReported;
        }
        progressReporter.accept(progress);
        return progress;
    }

    /**
     * 统计已消耗字节数的输入流包装，仅用于扫描进度上报。
     */
    private static final class CountingInputStream extends FilterInputStream {

        private long consumed;

        CountingInputStream(InputStream input) {
            super(input);
        }

        long consumed() {
            return consumed;
        }

        @Override
        public int read() throws IOException {
            int value = super.read();
            if (value >= 0) {
                consumed++;
            }
            return value;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            int read = super.read(buffer, offset, length);
            if (read > 0) {
                consumed += read;
            }
            return read;
        }
    }

    private Charset detectCharset(FileDescriptor fileNode) {
        byte[] sample = new byte[CHARSET_SAMPLE_BYTES];
        int size = 0;
        try (FileContentStream content = fileQueryService.openOwnedFileContent(
                fileNode.ownerUserId(),
                fileNode.id())) {
            InputStream input = content.inputStream();
            while (size < sample.length) {
                int read = input.read(sample, size, sample.length - size);
                if (read < 0) {
                    break;
                }
                size += read;
            }
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "TXT 读取失败");
        }
        if (size >= 3 && sample[0] == (byte) 0xEF && sample[1] == (byte) 0xBB && sample[2] == (byte) 0xBF) {
            return StandardCharsets.UTF_8;
        }
        try {
            StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(sample, 0, size));
            return StandardCharsets.UTF_8;
        } catch (CharacterCodingException exception) {
            return Charset.forName("GB18030");
        }
    }

    private FileDescriptor loadFileNode(UUID fileNodeId) {
        FileDescriptor fileNode = fileMetadataQueryService.findById(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "阅读源文件不存在"));
        if (fileNode.deleted() || !"FILE".equals(fileNode.nodeType())) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "阅读源文件不存在");
        }
        return fileNode;
    }

    private Map<String, TocMetadata> flattenToc(List<EpubTocEntry> roots) {
        Map<String, TocMetadata> result = new LinkedHashMap<>();
        appendToc(roots, 0, result);
        return result;
    }

    private void appendToc(List<EpubTocEntry> entries, int level, Map<String, TocMetadata> result) {
        for (EpubTocEntry entry : entries) {
            if (entry.href() != null && !entry.href().isBlank()) {
                result.putIfAbsent(stripFragment(entry.href()), new TocMetadata(entry.title(), level));
            }
            appendToc(entry.children(), level + 1, result);
        }
    }

    private boolean isTextContent(EpubManifestItem item) {
        if (item == null || item.href() == null) {
            return false;
        }
        String mediaType = item.mediaType() == null ? "" : item.mediaType().toLowerCase(Locale.ROOT);
        return mediaType.contains("xhtml") || mediaType.contains("html");
    }

    private int countXhtmlCharacters(String xhtml, String path) {
        try {
            String text = ReaderXmlSafety.parse(xhtml)
                    .getDocumentElement()
                    .getTextContent();
            return text == null ? 0 : text.codePointCount(0, text.length());
        } catch (Exception exception) {
            log.debug("EPUB 章节字符数统计失败: pathLength={}, errorType={}",
                    path == null ? 0 : path.length(), exception.getClass().getSimpleName());
            return 0;
        }
    }

    private TextChapterDraft txtDraft(int index, String title, long start, long end) {
        long charCount = Math.max(0L, end - start);
        return new TextChapterDraft(
                index,
                "chapter_" + index,
                clampTitle(title),
                null,
                start,
                end,
                (int) Math.min(Integer.MAX_VALUE, charCount),
                0
        );
    }

    /**
     * 截断过长标题。TXT 标题取整行匹配内容，畸形文件可能产生远超列宽的超长行。
     *
     * @param title 原始标题
     * @return 不超过入库上限的标题
     */
    private String clampTitle(String title) {
        if (title == null || title.isBlank()) {
            return "正文";
        }
        if (title.length() <= MAX_CHAPTER_TITLE_CHARS) {
            return title;
        }
        return title.substring(0, MAX_CHAPTER_TITLE_CHARS);
    }

    private String stripFragment(String path) {
        int fragment = path.indexOf('#');
        return fragment < 0 ? path : path.substring(0, fragment);
    }

    /**
     * 文本书籍解析草稿。
     *
     * @param title 标题
     * @param author 作者
     * @param language 语言或字符集
     * @param chapters 章节清单
     * @param cover 自动提取的封面
     */
    public record ParsedTextBook(
            String title,
            String author,
            String language,
            List<TextChapterDraft> chapters,
            ReaderCoverDraft cover
    ) {
    }

    /**
     * 文本章节解析草稿。
     *
     * @param chapterIndex 章节顺序
     * @param chapterKey 稳定章节键
     * @param title 标题
     * @param contentPath EPUB 正文路径
     * @param sourceStartOffset TXT 起始字符偏移
     * @param sourceEndOffset TXT 结束字符偏移
     * @param charCount 字符数
     * @param level 目录层级
     */
    public record TextChapterDraft(
            int chapterIndex,
            String chapterKey,
            String title,
            String contentPath,
            Long sourceStartOffset,
            Long sourceEndOffset,
            int charCount,
            int level
    ) {
    }

    private record TocMetadata(String title, int level) {
    }
}
