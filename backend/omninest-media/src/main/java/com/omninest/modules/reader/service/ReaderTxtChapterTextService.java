package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.processing.TempStagingPort;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderTextChapter;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderTextChapterRepository;
import com.omninest.modules.reader.service.TxtContentDecoder.TxtLine;
import com.omninest.modules.reader.service.TxtContentDecoder.TxtLineCursor;
import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.UUID;
import java.util.function.IntConsumer;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * TXT 每章 UTF-8 正文派生服务。
 *
 * <p>服务端要按章返回正文，就必须先完成解码；若留到请求时现解码，每次请求都要重跑
 * 整本书。这里在解析任务内用与章节清单同源的 {@link TxtContentDecoder} 做一次流式遍历，
 * 把每章正文写成独立的 UTF-8 派生文件，读取端只需打开对应文件节点。
 *
 * <p>章节区间不要求首尾相接：{@link ReaderTextParser} 会把抓取站放在文件头尾的预览副本整段
 * 丢弃，被丢弃的字符不属于任何一章，本服务按清单起点跳读并把空洞留在原地，所以清单也可能
 * 不覆盖文件末尾。跳空只记日志，不判失败：真正的检视点是每章写入字符数必须逐章等于清单里的
 * {@code sourceEndOffset - sourceStartOffset}，且本章起点必须正好落在行首，
 * 两者不一致说明源文件与清单已经错位，直接失败而不是产出偏移错误的正文。
 *
 * @author OmniNest
 */
@Service
@Slf4j
@RequiredArgsConstructor
public class ReaderTxtChapterTextService {

    /** 派生资产资源类型，与阅读封面同一命名空间 */
    private static final String RESOURCE_TYPE = "READER_ITEM";

    /** 派生资产类型：TXT 单章 UTF-8 正文 */
    private static final String ASSET_TYPE = "TEXT_CHAPTER";

    private static final String MIME_TYPE = "text/plain";

    /** 自有临时文件的业务子目录 */
    private static final String TEMP_SEGMENT = "reader-text";

    /** 正文写盘进度区间，80 为章节扫描完成，95 为全部章节落盘完成 */
    private static final int PROGRESS_BODY_START = 80;
    private static final int PROGRESS_BODY_END = 95;
    private static final int PROGRESS_BODY_STEP = 5;

    private final ReaderItemRepository itemRepository;
    private final ReaderTextChapterRepository chapterRepository;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final FileQueryService fileQueryService;
    private final TxtContentDecoder txtContentDecoder;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final TempStagingPort tempStagingPort;
    private final MediaProcessingLimitsProperties processingLimits;
    private final ReaderItemService readerItemService;

    /**
     * 读取一章服务端解码后的 UTF-8 正文。
     *
     * <p>派生文件尚未生成（旧数据未重解析、空章或本章超过单章返回上限），
     * 或节点已先于清单被清理时，一律返回 {@link ErrorCode#CHAPTER_TEXT_UNAVAILABLE}，
     * 客户端据此回退本地解析链；权限类错误保持原样，不得伪装成可回退。
     *
     * @param ownerUserId 当前用户 ID
     * @param itemId 阅读条目 ID
     * @param chapterIndex 章节顺序
     * @return 单章正文
     */
    public ChapterTextDto readChapterText(UUID ownerUserId, UUID itemId, int chapterIndex) {
        ReaderItem item = readerItemService.requireItem(ownerUserId, itemId);
        if (!"TXT".equalsIgnoreCase(item.getItemType())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "当前条目不是 TXT 书籍");
        }
        ReaderTextChapter chapter = chapterRepository.findByReaderItemIdAndChapterIndex(itemId, chapterIndex)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "章节不存在"));
        UUID contentFileNodeId = chapter.getContentFileNodeId();
        if (contentFileNodeId == null) {
            throw new BusinessException(ErrorCode.CHAPTER_TEXT_UNAVAILABLE, "本章正文尚未就绪");
        }
        long maxBytes = processingLimits.getMaxReaderChapterTextBytes();
        // 派生章节文件写在条目所有者名下，请求者的可读性已由 requireItem 判定，这里按节点真实所有者开流。
        try (FileContentStream content = fileQueryService.openOwnedFileContent(
                item.getOwnerUserId(), contentFileNodeId)) {
            if (content.sizeBytes() > maxBytes) {
                throw new BusinessException(ErrorCode.CHAPTER_TEXT_UNAVAILABLE, "本章正文超过单章返回上限");
            }
            String slice = new String(content.inputStream().readNBytes((int) content.sizeBytes()),
                    StandardCharsets.UTF_8);
            // 派生文件从标题行开始，返回时剥掉标题行及其终止符：客户端顶栏已显示章节名，
            // 正文再含一行就是重复标题（D-12）。起点如实回报，整章只有标题行时正文为空，
            // 由渲染端决定补什么，不在此改写偏移（否则客户端会把它认成陈旧清单）。
            int bodyStart = bodyStartOf(chapter, slice.length());
            String text = slice.substring(bodyStart);
            return new ChapterTextDto(text, text.length(), bodyStart);
        } catch (BusinessException exception) {
            if (exception.errorCode() == ErrorCode.FILE_NOT_FOUND
                    || exception.errorCode() == ErrorCode.FILE_OBJECT_MISSING) {
                // 节点先于清单被清理：与"尚未派生"同类，客户端应回退而不是报错
                throw new BusinessException(ErrorCode.CHAPTER_TEXT_UNAVAILABLE, "本章正文文件已失效");
            }
            throw exception;
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "读取本章正文失败");
        }
    }

    /**
     * 计算并夹紧本章正文起点。
     *
     * <p>清单可能比派生文件更新（重解析中途失败等），因此起点不得超过文件实际长度。
     *
     * @param chapter 章节清单
     * @param sliceChars 派生文件字符数
     * @return 正文起点
     */
    private int bodyStartOf(ReaderTextChapter chapter, int sliceChars) {
        Integer stored = chapter.getBodyStartOffset();
        if (stored == null || stored <= 0) {
            return 0;
        }
        return Math.min(stored, sliceChars);
    }

    /**
     * 为 TXT 条目的每一章生成 UTF-8 正文派生资产。
     *
     * <p>非 TXT 条目直接返回。正文文件按 {@code (itemId, manifestVersion)} 命名，
     * 全部章节写入成功后再清理 {@code obsoleteFileNodeIds}（上一版本留下的派生节点）；
     * 中途失败时旧版本仍在，客户端可以继续读到内容而不是两头落空。
     *
     * @param itemId 阅读条目 ID
     * @param fileNodeId TXT 源文件节点 ID
     * @param obsoleteFileNodeIds 待清理的旧版本派生节点 ID
     * @param progressReporter 进度回调，同时作为取消检查点
     */
    public void materialize(
            UUID itemId, UUID fileNodeId, List<UUID> obsoleteFileNodeIds, IntConsumer progressReporter) {
        ReaderItem item = itemRepository.findById(itemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.BOOK_NOT_FOUND, "阅读条目不存在"));
        if (!"TXT".equalsIgnoreCase(item.getItemType())) {
            return;
        }
        List<ReaderTextChapter> chapters = chapterRepository.findByReaderItemIdOrderByChapterIndex(itemId).stream()
                .filter(chapter -> chapter.getSourceStartOffset() != null && chapter.getSourceEndOffset() != null)
                .toList();
        if (chapters.isEmpty()) {
            return;
        }
        FileDescriptor fileNode = requireSourceFile(fileNodeId);
        Charset charset = txtContentDecoder.detectCharset(fileNode);
        int lastReported = reportBodyProgress(progressReporter, PROGRESS_BODY_START, PROGRESS_BODY_START);
        TxtLine lookahead = null;
        long previousEnd = 0L;
        long skippedChars = 0L;
        int skippedRegions = 0;
        try (TxtLineCursor cursor = txtContentDecoder.openCursor(fileNode, charset)) {
            for (int index = 0; index < chapters.size(); index++) {
                ReaderTextChapter chapter = chapters.get(index);
                requireOrdered(chapter, previousEnd);
                long start = chapter.getSourceStartOffset();
                if (start > previousEnd) {
                    skippedRegions++;
                    skippedChars += start - previousEnd;
                }
                lookahead = skipToChapterStart(cursor, lookahead, start);
                lookahead = writeChapter(item, chapter, cursor, lookahead);
                previousEnd = chapter.getSourceEndOffset();
                lastReported = reportBodyProgress(
                        progressReporter, bodyProgress(index + 1, chapters.size()), lastReported);
            }
            if (lookahead != null) {
                skippedRegions++;
                skippedChars += drainToTextEnd(cursor, lookahead) - previousEnd;
                log.warn("TXT 章节清单未覆盖文件末尾，尾部内容已跳过: itemId={}, lastChapterEnd={}, "
                        + "regions={}, skippedChars={}, sourceChars={}",
                        itemId, previousEnd, skippedRegions, skippedChars, cursor.offset());
            } else if (skippedRegions > 0) {
                log.info("TXT 清单跳空区间已跳过: itemId={}, regions={}, skippedChars={}",
                        itemId, skippedRegions, skippedChars);
            }
        }
        sweepObsoleteFileNodes(itemId, obsoleteFileNodeIds);
        log.info("TXT 每章正文派生完成: itemId={}, chapterCount={}, manifestVersion={}, sweptAssets={}",
                itemId, chapters.size(), item.getManifestVersion(),
                obsoleteFileNodeIds == null ? 0 : obsoleteFileNodeIds.size());
    }

    /**
     * 清理旧版本每章正文派生节点。
     *
     * <p>清单行已被重建，这些节点不再有任何数据库引用；逐个删除，失败只记录，
     * 不能因为残留对象把已完成的解析任务判成失败。
     */
    private void sweepObsoleteFileNodes(UUID itemId, List<UUID> obsoleteFileNodeIds) {
        if (obsoleteFileNodeIds == null || obsoleteFileNodeIds.isEmpty()) {
            return;
        }
        for (UUID fileNodeId : obsoleteFileNodeIds) {
            try {
                derivedAssetStorageService.deleteDerivedFileNode(fileNodeId);
            } catch (RuntimeException exception) {
                log.warn("TXT 旧章节正文清理失败: itemId={}, errorType={}",
                        itemId, exception.getClass().getSimpleName());
            }
        }
    }

    /**
     * 写入单章正文并保存为派生资产。
     *
     * @return 首行已落到下一章的预览行，没有则为 null
     */
    private TxtLine writeChapter(ReaderItem item, ReaderTextChapter chapter, TxtLineCursor cursor, TxtLine lookahead) {
        long end = chapter.getSourceEndOffset();
        long expectedChars = end - chapter.getSourceStartOffset();
        Path tempFile = null;
        try {
            tempFile = tempStagingPort.createTempFile(TEMP_SEGMENT, "chapter-", ".txt");
            ChapterWriteResult result = writeLines(tempFile, cursor, lookahead, end, expectedChars);
            long maxBytes = processingLimits.getMaxReaderChapterTextBytes();
            long assetBytes = sizeOf(tempFile);
            if (assetBytes == 0L) {
                // 空正文没有可派生的对象（文件模块拒绝 0 字节），保持未派生由兜底链覆盖
                log.debug("TXT 章节正文为空，跳过派生: itemId={}, chapterIndex={}",
                        item.getId(), chapter.getChapterIndex());
                return result.lookahead();
            }
            if (assetBytes > maxBytes) {
                // 超过单章返回上限：不派生本章，读取端回退本地解析链
                log.warn("TXT 章节正文超过单章上限，跳过派生: itemId={}, chapterIndex={}, bytes={}, limit={}",
                        item.getId(), chapter.getChapterIndex(), assetBytes, maxBytes);
                return result.lookahead();
            }
            String fileName = "v" + item.getManifestVersion() + "_chapter_" + chapter.getChapterIndex() + ".txt";
            UUID fileNodeId = derivedAssetStorageService.store(
                    item.getOwnerUserId(),
                    RESOURCE_TYPE,
                    item.getId(),
                    ASSET_TYPE,
                    fileName,
                    MIME_TYPE,
                    tempFile
            );
            chapter.setContentFileNodeId(fileNodeId);
            if (chapterRepository.updateContentFileNode(
                    chapter.getId(), fileNodeId, chapter.getVersion()) == 0) {
                // 清单已被并发重建：丢弃刚写入的对象并让任务失败，
                // 不能让新版本的行指向另一版本的正文文件
                derivedAssetStorageService.deleteDerivedFileNode(fileNodeId);
                throw new BusinessException(ErrorCode.CONFLICT, "TXT 章节清单已被并发重建");
            }
            log.debug("TXT 章节正文已派生: itemId={}, chapterIndex={}, chars={}",
                    item.getId(), chapter.getChapterIndex(), result.writtenChars());
            return result.lookahead();
        } finally {
            if (tempFile != null) {
                tempStagingPort.deleteQuietly(tempFile);
            }
        }
    }

    /**
     * 按清单偏移把本章内容写入临时文件。
     *
     * <p>行终止符按 1 字符计入偏移域，且归属于其前方内容所在的章节：下一章首行之前的
     * 终止符要写在上一章文件末尾，因此本章末尾不足期望字符数时补一个换行。
     */
    private ChapterWriteResult writeLines(
            Path tempFile, TxtLineCursor cursor, TxtLine lookahead, long end, long expectedChars) {
        long written = 0L;
        TxtLine line = lookahead;
        boolean firstInChapter = true;
        try (BufferedWriter out = Files.newBufferedWriter(tempFile, StandardCharsets.UTF_8)) {
            while (true) {
                if (line == null) {
                    line = cursor.next();
                }
                if (line == null || line.offset() >= end) {
                    break;
                }
                // 行终止符由读到它的行携带：本章首行的终止符属于上一章，
                // 由下方"末尾补足"写进上一章文件，故此处跳过。
                if (!firstInChapter && line.precededBySeparator()) {
                    out.write('\n');
                    written++;
                }
                out.write(line.text());
                written += line.text().length();
                firstInChapter = false;
                line = null;
            }
            if (written < expectedChars) {
                out.write('\n');
                written++;
            }
            if (written != expectedChars) {
                throw new BusinessException(ErrorCode.INTERNAL_ERROR, "TXT 章节正文与清单偏移不一致");
            }
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "TXT 章节正文写入失败");
        }
        return new ChapterWriteResult(written, line);
    }

    /**
     * 丢弃本章起点之前的行。
     *
     * <p>被丢弃的预览副本不属于任何一章，这些行连同各自的行终止符一起跳过；起点落进空洞后
     * 那个终止符留在原地，不写进本章文件。起点没有正好落在行首时清单与源文件已不是同一份内容：
     * 逐章字符数校验同样会拦下来，但那时已经丢过行、报的是长度不符，这里先停并把原因点名。
     *
     * @param cursor 行游标
     * @param lookahead 上一章交接的首行，可能已经在本章起点之后
     * @param start 本章起点偏移
     * @return 起点等于 start 的首行；已到文末时为 null
     */
    private TxtLine skipToChapterStart(TxtLineCursor cursor, TxtLine lookahead, long start) {
        TxtLine line = lookahead;
        // 首章没有上一章交接的行：不先取一行，循环根本不会启动，游标停在文件开头，
        // 于是被丢弃的开头预览副本会被当作本章正文写出去。
        if (line == null && cursor.offset() < start) {
            line = cursor.next();
        }
        while (line != null && line.offset() < start) {
            line = cursor.next();
        }
        if (line != null && line.offset() > start) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "TXT 章节起点不在行边界");
        }
        return line;
    }

    /**
     * 读完末章之后剩余的行，返回解码文本的总字符数。
     *
     * <p>清单不覆盖文件末尾时用它把未覆盖量计入日志；末行没有终止符，所以读到文末为止的
     * 游标偏移就是整本字符数，与 {@link ReaderTextParser} 划定末章终点用的是同一个值。
     *
     * @param cursor 行游标
     * @param lookahead 尚未写出的首行
     * @return 解码文本总字符数
     */
    private long drainToTextEnd(TxtLineCursor cursor, TxtLine lookahead) {
        TxtLine line = lookahead;
        while (line != null) {
            line = cursor.next();
        }
        return cursor.offset();
    }

    private long sizeOf(Path path) {
        try {
            return Files.size(path);
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "TXT 章节正文写入失败");
        }
    }

    /**
     * 校验本章区间与已经读到的位置同向。
     *
     * <p>预览副本被整段丢弃后章节不再首尾相接，因此只要求起点不早于上一章终点；起点晚于终点才是
     * 清单自身畸形。首章起点可以大于 0：抓取站放在文件开头的预览副本从第 0 字符起，被整段丢弃后
     * 首章自然从副本之后开始，这与"没有候选时用整本长度建单章正文"是两种都合法的形状。
     *
     * @param chapter 待校验章节
     * @param previousEnd 上一章终点，首章传 0
     */
    private void requireOrdered(ReaderTextChapter chapter, long previousEnd) {
        long start = chapter.getSourceStartOffset();
        long end = chapter.getSourceEndOffset();
        if (start < previousEnd || start > end) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "TXT 章节区间顺序异常");
        }
    }

    private FileDescriptor requireSourceFile(UUID fileNodeId) {
        FileDescriptor fileNode = fileMetadataQueryService.findById(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "阅读源文件不存在"));
        if (fileNode.deleted() || !"FILE".equals(fileNode.nodeType())) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "阅读源文件不存在");
        }
        return fileNode;
    }

    private int bodyProgress(int completedChapters, int totalChapters) {
        long span = PROGRESS_BODY_END - PROGRESS_BODY_START;
        return PROGRESS_BODY_START + (int) Math.min(span, span * completedChapters / Math.max(1, totalChapters));
    }

    private int reportBodyProgress(IntConsumer progressReporter, int progress, int lastReported) {
        if (progress < lastReported + PROGRESS_BODY_STEP) {
            return lastReported;
        }
        progressReporter.accept(progress);
        return progress;
    }

    /**
     * 单章写入结果。
     *
     * @param writtenChars 已写入字符数，必须等于清单期望值
     * @param lookahead 起点已达到下一章的首行，没有则为 null
     */
    private record ChapterWriteResult(long writtenChars, TxtLine lookahead) {
    }

    /**
     * 单章正文响应。
     *
     * @param chapterIndex 章节顺序
     * @param text 本章正文，已按 bodyStartOffset 去掉标题行
     * @param charCount 返回正文的字符数
     * @param bodyStartOffset 正文在派生文件中的起点，客户端用它还原完整偏移域
     */
    public record ChapterTextDto(String text, int charCount, int bodyStartOffset) {
    }
}
