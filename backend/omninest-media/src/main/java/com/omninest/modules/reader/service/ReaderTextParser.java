package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.reader.service.ComicEpubParser.EpubManifestItem;
import com.omninest.modules.reader.service.ComicEpubParser.EpubParseResult;
import com.omninest.modules.reader.service.ComicEpubParser.EpubSpineItem;
import com.omninest.modules.reader.service.ComicEpubParser.EpubTocEntry;
import com.omninest.modules.reader.service.ReaderEpubArchiveStager.StagedArchive;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import java.io.IOException;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.IntConsumer;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.w3c.dom.Document;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

/**
 * EPUB/TXT 文本书籍流式解析器，生成可持久化章节清单。
 *
 * <p>TXT 的解码与偏移域规则不在本类内实现，统一由 {@link TxtContentDecoder} 提供，
 * 使章节清单与按章正文出自同一份解码代码。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderTextParser {

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

    /**
     * 句子标点：标题行里出现句号或分号即判为正文句子，不是章节起点。
     *
     * <p>抓取站的作者附言会以"1、《覆汉》实体书第一辑要出了；29"这样的编号行出现，
     * 卷末标记"第一卷完。113"也以句号收尾；两者都曾被当成独立成章的标题，
     * 在目录里留下十几字的伪章。感叹号与问号不参与判定：章题里会出现"第1章 谁？"。
     */
    private static final Pattern SENTENCE_PUNCTUATION = Pattern.compile("[。；;]");

    /** 扫描进度上报区间，25 为载入后基线，80 为扫描完成。 */
    private static final int PROGRESS_SCAN_START = 25;
    private static final int PROGRESS_SCAN_END = 80;
    private static final int PROGRESS_SCAN_STEP = 5;

    private final FileMetadataQueryService fileMetadataQueryService;
    private final TxtContentDecoder txtContentDecoder;
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
                        toc == null ? 0 : toc.level(),
                        null
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
        Charset charset = txtContentDecoder.detectCharset(fileNode);
        List<TxtCandidate> candidates = new ArrayList<>();
        int lastReportedProgress = PROGRESS_SCAN_START;
        long totalBytes = Math.max(1L, fileNode.sizeBytes());
        long currentOffset;
        try (TxtContentDecoder.TxtLineCursor cursor = txtContentDecoder.openCursor(fileNode, charset)) {
            TxtContentDecoder.TxtLine line;
            while ((line = cursor.next()) != null) {
                // strip() 按 Unicode 空白判定，可去除全角空格缩进；trim() 只去除 <= U+0020。
                String normalized = line.text().strip();
                boolean startsChapter = isChapterTitle(normalized)
                        && (candidates.isEmpty() || line.offset() > candidates.getLast().start());
                if (startsChapter) {
                    candidates.add(new TxtCandidate(line.offset(), line.text().length(), normalized));
                }
                lastReportedProgress = reportScanProgress(
                        progressReporter, cursor.consumedBytes(), totalBytes, lastReportedProgress);
            }
            currentOffset = cursor.offset();
        }
        List<TextChapterDraft> chapters = buildTxtDrafts(candidates, currentOffset);
        progressReporter.accept(PROGRESS_SCAN_END);
        return new ParsedTextBook(null, null, charset.name(), chapters, null);
    }

    /**
     * 由候选标题行生成 TXT 章节清单。
     *
     * <p>区间始终按"本候选到下一候选"划定，再从中挑出主正文序列；被丢弃的预览区间既不并入
     * 相邻章，也不成章——抓取站放在文件头尾的"最新章节"是正文的整份副本，并入会让一章凭空
     * 多出一段重复正文，保留成章则让目录出现三份同名章。因为区间以全部候选为界，丢弃后章节
     * 不再首尾相接，全书进度按入选章的字数合计。
     *
     * @param candidates 按文件顺序记录的候选标题行
     * @param fileEnd 解码文本的总字符数
     * @return 章节清单
     */
    private List<TextChapterDraft> buildTxtDrafts(List<TxtCandidate> candidates, long fileEnd) {
        List<TextChapterDraft> chapters = new ArrayList<>();
        if (candidates.isEmpty()) {
            chapters.add(txtDraft(0, "正文", 0L, fileEnd, 0));
            return chapters;
        }

        Set<Integer> kept = selectMainSequence(candidates, fileEnd);
        int index = 0;
        long firstStart = candidates.getFirst().start();
        if (firstStart > 0L) {
            // 首个标题行之前的书名、作者与分节线保留为单章"正文"，与既有清单口径一致。
            chapters.add(txtDraft(index++, "正文", 0L, firstStart, 0));
        }
        for (int position = 0; position < candidates.size(); position++) {
            if (!kept.contains(position)) {
                continue;
            }
            TxtCandidate candidate = candidates.get(position);
            long end = position + 1 < candidates.size()
                    ? candidates.get(position + 1).start()
                    : fileEnd;
            chapters.add(txtDraft(
                    index++,
                    candidate.title(),
                    candidate.start(),
                    end,
                    bodyStartOffset(candidate.start(), candidate.start(), candidate.titleLength(), end)
            ));
        }
        flushTailChunk(chapters, index, fileEnd);
        return chapters;
    }

    /**
     * 把清单最后一段没覆盖到的尾部正文强制入表。
     *
     * <p>派生阶段按章节区间逐章写正文，落在所有区间之外的字符既不属任何一章也不会被读到。
     * 最后一个候选被判为伪标题或预览副本时，清单就停在那里，文件末尾的整段正文无声消失
     * （实测《廓晋》.txt 尾部 32,983 字，占全书 1/9）。区间连续是清单的硬约束，
     * 尾部缺口只能补章，不能靠日志通报。
     *
     * @param chapters 已生成的章节清单
     * @param nextIndex 下一章的顺位
     * @param fileEnd 解码文本的总字符数
     */
    private void flushTailChunk(List<TextChapterDraft> chapters, int nextIndex, long fileEnd) {
        if (chapters.isEmpty()) {
            return;
        }
        TextChapterDraft last = chapters.getLast();
        Long lastEnd = last.sourceEndOffset();
        if (lastEnd == null || lastEnd >= fileEnd) {
            return;
        }
        chapters.add(txtDraft(nextIndex, "正文", lastEnd, fileEnd, 0));
    }

    /**
     * 挑出主正文序列，丢弃其副本所在的整段连续区间。
     *
     * <p>切段依据是序号回退：正文的递增序号一旦从头再来，说明进入了预览或书尾块。切出的段里
     * 字数最多的那段是正文；其余段只有在**过半章节与正文同名同号**且体量远小于正文时才丢弃，
     * 避免把"第二卷从第1章重新编号"这类合法分卷结构当成预览删掉。
     *
     * @param candidates 按文件顺序记录的候选标题行
     * @param fileEnd 解码文本的总字符数，最后一个候选的区间以此收尾
     * @return 入选候选在列表中的下标集合
     */
    private Set<Integer> selectMainSequence(List<TxtCandidate> candidates, long fileEnd) {
        List<List<Integer>> runs = new ArrayList<>();
        List<Long> runChars = new ArrayList<>();
        int previousNumber = -1;
        for (int position = 0; position < candidates.size(); position++) {
            TxtCandidate candidate = candidates.get(position);
            int number = sequenceNumber(candidate.title());
            boolean restarts = number >= 0 && previousNumber >= 0 && number <= previousNumber;
            if (runs.isEmpty() || restarts) {
                runs.add(new ArrayList<>());
                runChars.add(0L);
            }
            int run = runs.size() - 1;
            runs.get(run).add(position);
            // 末个候选也要带上自己的正文长度：写成 candidate.start() 会让它恒记 0 字，
            // 正文恰好以末章体量输掉"哪一段是主序列"的比较。
            long end = position + 1 < candidates.size()
                    ? candidates.get(position + 1).start()
                    : fileEnd;
            runChars.set(run, runChars.get(run) + Math.max(0L, end - candidate.start()));
            if (number >= 0) {
                previousNumber = number;
            }
        }

        Set<Integer> kept = new HashSet<>();
        if (runs.size() < 2) {
            for (int position = 0; position < candidates.size(); position++) {
                kept.add(position);
            }
            return kept;
        }

        int mainRun = 0;
        for (int run = 1; run < runs.size(); run++) {
            if (runChars.get(run) > runChars.get(mainRun)) {
                mainRun = run;
            }
        }
        Set<String> mainKeys = new HashSet<>();
        for (int position : runs.get(mainRun)) {
            mainKeys.add(duplicateKey(candidates.get(position)));
        }

        List<Integer> dropped = new ArrayList<>();
        for (int run = 0; run < runs.size(); run++) {
            List<Integer> members = runs.get(run);
            long duplicates = members.stream()
                    .filter(position -> mainKeys.contains(duplicateKey(candidates.get(position))))
                    .count();
            boolean copy = run != mainRun
                    && duplicates * 2 >= members.size()
                    && runChars.get(run) * 10 < runChars.get(mainRun) * 3;
            for (int position : members) {
                if (copy) {
                    dropped.add(position);
                } else {
                    kept.add(position);
                }
            }
        }
        if (!dropped.isEmpty()) {
            log.info("TXT 预览副本丢弃: candidates={}, dropped={}, kept={}",
                    candidates.size(), dropped.size(), kept.size());
        }
        return kept;
    }

    /**
     * 参与序号回退判定的编号。
     *
     * <p>卷/篇级标记不参与：正文常用"第1卷 + 第1章"的重新开始编号，把卷号算进来会把
     * 结构正常的书切碎。中文数字不解析，一律按无编号处理，既不误切也不误丢。
     */
    private static int sequenceNumber(String title) {
        NumberToken token = matchNumberToken(title, 0);
        if (token == null || token.value() < 0) {
            return -1;
        }
        String text = token.text();
        return text.endsWith("卷") || text.endsWith("篇") ? -1 : token.value();
    }

    /**
     * 副本识别键：序号标记加上剥掉全部前导标记后的标题正文。
     *
     * @param candidate 候选标题行
     * @return 同名同号判定用的键
     */
    private static String duplicateKey(TxtCandidate candidate) {
        String title = candidate.title();
        int consumed = 0;
        int cursor = 0;
        while (cursor < title.length()) {
            NumberToken token = matchNumberToken(title, cursor);
            if (token == null) {
                break;
            }
            consumed = token.end();
            cursor = consumed;
        }
        String core = title.substring(consumed).strip();
        // 只剩序号的标题（"第54章"）用整行做键，避免所有空标题互相判成副本。
        return sequenceNumber(title) + "|" + (core.isEmpty() ? title : core);
    }

    /**
     * TXT 标题行候选。
     *
     * @param start 标题行在解码字符域中的起点
     * @param titleLength 标题行字符长度，不含行终止符
     * @param title 已去除首尾空白的标题文本
     */
    private record TxtCandidate(long start, int titleLength, String title) {
    }

    /**
     * 计算正文在本章偏移域中的起点：标题行本身与其后的行终止符都不属于正文。
     *
     * <p>章节首行不是标题行时返回 0，表示整章都是正文（无标题书名只能整本成一章的情况）。
     * 标题行是本章最后一行且没有终止符时返回章节长度本身，表示正文为空。
     *
     * @param chapterStart 章节起始偏移
     * @param titleOffset 标题行起始偏移，无标题行时为哨兵值
     * @param titleLength 标题行字符长度
     * @param chapterEnd 章节结束偏移
     * @return 正文起点相对章节起点的偏移
     */
    private int bodyStartOffset(long chapterStart, long titleOffset, long titleLength, long chapterEnd) {
        if (titleOffset < chapterStart) {
            return 0;
        }
        long chapterChars = Math.max(0L, chapterEnd - chapterStart);
        long afterTitle = Math.max(0L, titleOffset + titleLength + 1L - chapterStart);
        return (int) Math.min(chapterChars, afterTitle);
    }

    /**
     * 判断归一化后的行是否为章节标题行。
     *
     * <p>命中句子标点的行先排除：编号附言与卷末标记的形状与标题一致，但带句读，
     * 让它们起章会在目录里留下十几字的伪章，正文也被从上一章截断。
     *
     * @param normalized 已去除首尾空白的行
     * @return 命中标题模式时返回 true
     */
    private boolean isChapterTitle(String normalized) {
        if (normalized.isEmpty()) {
            return false;
        }
        if (SENTENCE_PUNCTUATION.matcher(normalized).find()) {
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

    /**
     * 统计 EPUB 章节的正文字符数。
     *
     * <p>只取 {@code <body>} 并剔掉其中的 {@code <style>} 与 {@code <script>}：整份文档的文本节点
     * 会把 CSS 与 JS 按字符计进字数，而这份字数同时是全书进度的权重与"本章多少字"的显示值。
     * 包内可见供单元测试直接验证规则，不依赖整本 EPUB 夹具。
     */
    int countXhtmlCharacters(String xhtml, String path) {
        try {
            Document doc = ReaderXmlSafety.parse(xhtml);
            NodeList bodies = doc.getElementsByTagNameNS("*", "body");
            Node root = bodies.getLength() > 0 ? bodies.item(0) : doc.getDocumentElement();
            if (root == null) {
                return 0;
            }
            Node content = root.cloneNode(true);
            stripNonContentNodes(content);
            String text = content.getTextContent();
            return text == null ? 0 : text.codePointCount(0, text.length());
        } catch (Exception exception) {
            log.debug("EPUB 章节字符数统计失败: pathLength={}, errorType={}",
                    path == null ? 0 : path.length(), exception.getClass().getSimpleName());
            return 0;
        }
    }

    /**
     * 递归移除样式与脚本节点。
     */
    private void stripNonContentNodes(Node node) {
        NodeList children = node.getChildNodes();
        for (int index = children.getLength() - 1; index >= 0; index--) {
            Node child = children.item(index);
            String name = child.getLocalName() != null ? child.getLocalName() : child.getNodeName();
            if ("style".equalsIgnoreCase(name) || "script".equalsIgnoreCase(name)) {
                node.removeChild(child);
            } else if (child.hasChildNodes()) {
                stripNonContentNodes(child);
            }
        }
    }

    /**
     * 章节标题前导的序号标记：第N章/节/回/卷/篇、Chapter N、裸数字加分隔符。
     * 捕获组取标记本身（含其后的冒号），组外再吃掉标记之间的空白。
     */
    private static final Pattern CHAPTER_NUMBER_TOKEN = Pattern.compile(
            "^((?:第\\s*[0-9〇零一二三四五六七八九十百千两]{1,8}\\s*[章节回卷篇]"
                    + "|[Cc][Hh][Aa][Pp][Tt][Ee][Rr]\\s+[0-9]+"
                    + "|[0-9]{1,3}\\s*[.、])[\\s　]*[:：]?)[\\s　]*"
    );

    /** 序号标记里的阿拉伯数字，用于与目录位次比对；中文数字不参与比对。 */
    private static final Pattern TOKEN_DIGITS = Pattern.compile("[0-9]+");

    /**
     * 归一章标题里连续出现的序号标记。
     *
     * <p>抓取站会在原标题前再补一个全书递增号，形成"第1章 第1章 天胡开局"或
     * "第38章 第1章 吴兴"（卷内序号重启）。裁决口径：优先保留数值等于本章目录位次
     * 的那个标记，中文数字或都不等于位次时保留第一个；其余标记剥除，标题正文原样保留。
     * 只有一个标记时不改写，已带序号的标题也不再补号。
     *
     * @param rawTitle 标题行原文
     * @param chapterOrdinal 本章在清单中的 1-based 位次
     * @return 用于入库与展示的标题
     */
    static String normalizeChapterTitle(String rawTitle, int chapterOrdinal) {
        if (rawTitle == null || rawTitle.isBlank()) {
            return rawTitle;
        }
        List<NumberToken> tokens = new ArrayList<>();
        int cursor = 0;
        while (cursor < rawTitle.length()) {
            NumberToken token = matchNumberToken(rawTitle, cursor);
            if (token == null) {
                break;
            }
            tokens.add(token);
            cursor = token.end();
        }
        if (tokens.size() < 2) {
            return rawTitle;
        }
        NumberToken kept = tokens.getFirst();
        for (NumberToken token : tokens) {
            if (token.value() >= 0 && token.value() == chapterOrdinal) {
                kept = token;
                break;
            }
        }
        String tail = rawTitle.substring(cursor).strip();
        return tail.isEmpty() ? kept.text() : kept.text() + " " + tail;
    }

    private static NumberToken matchNumberToken(String text, int from) {
        var matcher = CHAPTER_NUMBER_TOKEN.matcher(text.substring(from));
        if (!matcher.find()) {
            return null;
        }
        String token = matcher.group(1).strip().replaceAll("[:：]$", "");
        return new NumberToken(token, from + matcher.end(), tokenValue(token));
    }

    private static int tokenValue(String token) {
        var matcher = TOKEN_DIGITS.matcher(token);
        if (matcher.find()) {
            try {
                return Integer.parseInt(matcher.group());
            } catch (NumberFormatException exception) {
                return -1;
            }
        }
        return chineseNumberValue(token);
    }

    /**
     * 中文数字标记的取值：常用写法可到千位（十一=11、二十三=23、一百二十=120、两千=2000）。
     *
     * <p>不认中文数字的话，"第一回/第二回"编号的书既拿不到与目录位次比对的数值，
     * 序号回退也永远判不出来——抓取站放在头尾的预览副本就切不出段，目录里仍是重复章。
     *
     * <p>包内共享：漫画分卷名（第三十一卷）走的是同一套数位-单位累加规则，两处各写一份时
     * 出现过"十一"被算成 -9 的分叉，排序与目录一起错乱。
     *
     * @param token 标记文本
     * @return 数值；文本里没有可识别数字时返回 -1
     */
    static int chineseNumberValue(String token) {
        int section = 0;
        int digit = 0;
        boolean seen = false;
        for (int offset = 0; offset < token.length();) {
            int codePoint = token.codePointAt(offset);
            offset += Character.charCount(codePoint);
            int value = numeralValue(codePoint);
            if (value >= 0) {
                digit = value;
                seen = true;
                continue;
            }
            int unit = unitValue(codePoint);
            if (unit <= 0) {
                continue;
            }
            seen = true;
            section += (digit == 0 ? unit : digit * unit);
            digit = 0;
        }
        return seen ? section + digit : -1;
    }

    private static int numeralValue(int codePoint) {
        return switch (codePoint) {
            case '〇', '零' -> 0;
            case '一', '壹' -> 1;
            case '二', '两', '兩', '贰', '貳' -> 2;
            case '三', '叁', '參' -> 3;
            case '四', '肆' -> 4;
            case '五', '伍' -> 5;
            case '六', '陆', '陸' -> 6;
            case '七', '柒' -> 7;
            case '八', '捌' -> 8;
            case '九', '玖' -> 9;
            default -> -1;
        };
    }

    private static int unitValue(int codePoint) {
        return switch (codePoint) {
            case '十', '拾' -> 10;
            case '百', '佰' -> 100;
            case '千', '仟' -> 1000;
            case '万', '萬' -> 10000;
            default -> 0;
        };
    }

    /**
     * 标题前导序号标记。
     *
     * @param text 标记文本
     * @param end 标记之后在原文中的位置
     * @param value 阿拉伯数字值，中文数字或无数字为 -1
     */
    private record NumberToken(String text, int end, int value) {
    }

    private TextChapterDraft txtDraft(int index, String title, long start, long end, int bodyStart) {
        long charCount = Math.max(0L, end - start);
        return new TextChapterDraft(
                index,
                txtChapterKey(start),
                clampTitle(normalizeChapterTitle(title, index + 1)),
                null,
                start,
                end,
                (int) Math.min(Integer.MAX_VALUE, charCount),
                0,
                bodyStart
        );
    }

    /**
     * TXT 章节身份键：按本章在解码字符域中的起点派生，而不是按清单顺位。
     *
     * <p>阅读进度与批注存的就是这个键。收紧标题判据会减少章节数，位置键 {@code chapter_N}
     * 于是整体位移，旧进度会静默落到别的章节；正文起点不参与章节计数，合并掉一个伪标题
     * 也不会移动后续任何一章的起点。
     *
     * @param sourceStartOffset 本章起始字符偏移
     * @return 章节身份键
     */
    static String txtChapterKey(long sourceStartOffset) {
        return "t" + sourceStartOffset;
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
     * @param bodyStartOffset TXT 正文起点相对章节起点的偏移，标题行不计入；EPUB 为 null
     */
    public record TextChapterDraft(
            int chapterIndex,
            String chapterKey,
            String title,
            String contentPath,
            Long sourceStartOffset,
            Long sourceEndOffset,
            int charCount,
            int level,
            Integer bodyStartOffset
    ) {
    }

    private record TocMetadata(String title, int level) {
    }
}
