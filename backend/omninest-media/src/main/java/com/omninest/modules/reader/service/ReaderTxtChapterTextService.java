package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.processing.TempStagingPort;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileMetadataQueryService;
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
 * <p>写入字符数必须逐章等于清单里的 {@code sourceEndOffset - sourceStartOffset}，
 * 不一致说明源文件与清单已经错位，直接失败而不是产出偏移错误的正文。
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
    private final TxtContentDecoder txtContentDecoder;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final TempStagingPort tempStagingPort;

    /**
     * 为 TXT 条目的每一章生成 UTF-8 正文派生资产。
     *
     * <p>非 TXT 条目直接返回。正文文件按 {@code (itemId, manifestVersion)} 命名，
     * 重解析产生新版本后写入新对象，并在写入成功后删除上一章版本的节点。
     *
     * @param itemId 阅读条目 ID
     * @param fileNodeId TXT 源文件节点 ID
     * @param progressReporter 进度回调，同时作为取消检查点
     */
    public void materialize(UUID itemId, UUID fileNodeId, IntConsumer progressReporter) {
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
        try (TxtLineCursor cursor = txtContentDecoder.openCursor(fileNode, charset)) {
            for (int index = 0; index < chapters.size(); index++) {
                ReaderTextChapter chapter = chapters.get(index);
                requireContiguous(chapter, index == 0 ? 0L : chapters.get(index - 1).getSourceEndOffset());
                lookahead = writeChapter(item, chapter, cursor, lookahead);
                lastReported = reportBodyProgress(
                        progressReporter, bodyProgress(index + 1, chapters.size()), lastReported);
            }
        }
        if (lookahead != null) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "TXT 章节清单未覆盖源文件末尾内容");
        }
        log.info("TXT 每章正文派生完成: itemId={}, chapterCount={}, manifestVersion={}",
                itemId, chapters.size(), item.getManifestVersion());
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
            String fileName = "v" + item.getManifestVersion() + "_chapter_" + chapter.getChapterIndex() + ".txt";
            UUID previousFileNodeId = chapter.getContentFileNodeId();
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
            chapterRepository.save(chapter);
            if (previousFileNodeId != null && !previousFileNodeId.equals(fileNodeId)) {
                derivedAssetStorageService.deleteDerivedFileNode(previousFileNodeId);
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
                if (!firstInChapter) {
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

    private void requireContiguous(ReaderTextChapter chapter, long previousEnd) {
        if (chapter.getSourceStartOffset() != previousEnd) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "TXT 章节偏移不连续");
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
}
