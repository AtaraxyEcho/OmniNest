package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.reader.service.ReaderArchiveSafetyPolicy.ArchiveReadSession;
import com.omninest.modules.reader.service.ReaderArchiveSafetyPolicy.EntryReadGuard;
import com.omninest.modules.reader.service.model.ReaderCoverDraft;
import java.io.ByteArrayOutputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipException;
import java.util.zip.ZipInputStream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 漫画 ZIP 归档解析器，负责安全扫描图片条目和提取封面。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderComicArchiveParser {

    private static final long MAX_PAGE_IMAGE_SIZE = 20L * 1024 * 1024;
    private static final int IMAGE_HEADER_BYTES = 64 * 1024;
    /** Windows 压缩工具产出的中文条目名多为 GBK；GB18030 是其超集。 */
    private static final Charset GB18030 = Charset.forName("GB18030");
    private static final Set<String> IMAGE_EXTENSIONS = Set.of(
            ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tiff", ".tif", ".avif"
    );
    private static final Set<String> SYSTEM_PREFIXES = Set.of(
            "__macosx/", ".ds_store", "thumbs.db", "desktop.ini"
    );
    private static final Pattern NATURAL_SPLITTER = Pattern.compile("(\\d+)|(\\D+)");

    private final FileQueryService fileQueryService;
    private final ReaderArchiveSafetyPolicy archiveSafetyPolicy;

    /**
     * 扫描 ZIP 中可阅读的图片条目。
     *
     * @param fileNode 已完成业务授权的文件节点
     * @return 按文件名自然排序的图片条目
     */
    public List<ImageEntry> parseEntries(FileDescriptor fileNode) {
        return parseEntries(
                contentSupplier(fileNode),
                fileNode.sizeBytes(),
                "fileNodeId=" + fileNode.id()
        );
    }

    /**
     * 归档字节流来源：GB18030 重扫需要重开一次，因此是工厂而不是一次性流。
     */
    @FunctionalInterface
    interface ArchiveStreamSupplier {
        InputStream open() throws IOException;
    }

    /**
     * 打开对象存储内容流；包装出的流关闭时同时释放 {@link FileContentStream}。
     */
    private ArchiveStreamSupplier contentSupplier(FileDescriptor fileNode) {
        return () -> {
            FileContentStream content = fileQueryService.openOwnedFileContent(
                    fileNode.ownerUserId(), fileNode.id());
            return new FilterInputStream(content.inputStream()) {
                @Override
                public void close() throws IOException {
                    try {
                        super.close();
                    } finally {
                        content.close();
                    }
                }
            };
        };
    }

    /**
     * 按调用方提供的字节流来源解析条目。
     *
     * <p>调用方已在事务外把归档落盘：这里不再回源对象存储，整包下载因此不会占住数据库连接。
     * 同一份暂存归档也被封面的二次读取复用，避免为取一张封面再下载整包。</p>
     *
     * @param supplier 可重开的归档字节流来源
     * @param sizeBytes 归档字节数，用于先做体积上限校验
     * @param logRef 日志里标识归档来源的短文本
     * @return 按文件名自然排序的图片条目
     */
    public List<ImageEntry> parseEntries(
            ArchiveStreamSupplier supplier, long sizeBytes, String logRef) {
        archiveSafetyPolicy.validateArchiveSize(sizeBytes);
        try {
            return parseEntries(supplier, StandardCharsets.UTF_8, logRef);
        } catch (ArchiveNameEncodingException exception) {
            // 非 UTF-8 条目名会以 MALFORMED 或 invalid LOC header 失败；按 Windows 常见 GBK 重扫一次。
            log.info("漫画归档条目名不是 UTF-8，回退 GB18030 重扫: {}", logRef);
            try {
                return parseEntries(supplier, GB18030, logRef);
            } catch (ArchiveNameEncodingException retryException) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "压缩包条目名编码无法识别");
            }
        }
    }

    private List<ImageEntry> parseEntries(
            ArchiveStreamSupplier supplier, Charset charset, String logRef) {
        ArchiveReadSession session = archiveSafetyPolicy.newReadSession();
        List<ImageEntry> imageEntries = new ArrayList<>();
        try (InputStream raw = supplier.open();
             ZipInputStream input = new ZipInputStream(raw, charset)) {
            ZipEntry entry;
            int entryIndex = 0;
            while ((entry = input.getNextEntry()) != null) {
                String normalizedName = entry.getName().toLowerCase(Locale.ROOT);
                boolean imageEntry = !entry.isDirectory()
                        && !isSystemFile(normalizedName)
                        && isImageFile(normalizedName);
                EntryReadGuard guard = session.beginEntry(
                        entry,
                        imageEntry ? MAX_PAGE_IMAGE_SIZE : Long.MAX_VALUE
                );
                if (entry.isDirectory()) {
                    guard.complete(entry);
                    entryIndex++;
                    continue;
                }
                if (!imageEntry) {
                    drainArchiveEntry(input, guard);
                    guard.complete(entry);
                    entryIndex++;
                    continue;
                }
                byte[] header = new byte[IMAGE_HEADER_BYTES];
                int totalRead = readHeaderAndDrain(input, guard, header);
                int[] dimensions = totalRead > 24
                        ? ComicPageAssetService.readImageDimensions(header)
                        : new int[]{0, 0};
                guard.complete(entry);
                long entrySize = entry.getSize() >= 0 ? entry.getSize() : guard.bytesRead();
                imageEntries.add(new ImageEntry(
                        entry.getName(),
                        entrySize,
                        entryIndex,
                        dimensions[0],
                        dimensions[1]
                ));
                entryIndex++;
            }
        } catch (ZipException exception) {
            if (isEntryNameEncodingFailure(exception)) {
                throw new ArchiveNameEncodingException(exception);
            }
            log.warn("漫画归档读取失败: fileNodeId={}, errorType={}",
                    logRef, exception.getClass().getSimpleName());
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "文件读取失败");
        } catch (IOException exception) {
            log.warn("漫画归档读取失败: fileNodeId={}, errorType={}",
                    logRef, exception.getClass().getSimpleName());
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "文件读取失败");
        }
        imageEntries.sort((left, right) -> naturalCompare(left.name(), right.name()));
        return imageEntries;
    }

    /**
     * 从 ZIP 中提取指定图片作为封面。
     *
     * @param fileNode 已完成业务授权的文件节点
     * @param coverEntry 封面条目
     * @return 封面草稿；读取失败时返回 null
     */
    public ReaderCoverDraft extractCover(FileDescriptor fileNode, ImageEntry coverEntry) {
        return extractCover(contentSupplier(fileNode), coverEntry);
    }

    /**
     * 从已落盘的归档提取封面：与条目解析共用同一次暂存，不再为一张封面二次下载整包。
     *
     * @param supplier 可重开的归档字节流来源
     * @param coverEntry 封面条目
     * @return 封面草稿；读取失败时返回 null
     */
    public ReaderCoverDraft extractCover(
            ArchiveStreamSupplier supplier, ImageEntry coverEntry) {
        ReaderCoverDraft draft = extractCover(supplier, coverEntry, StandardCharsets.UTF_8);
        if (draft != null) {
            return draft;
        }
        return extractCover(supplier, coverEntry, GB18030);
    }

    private ReaderCoverDraft extractCover(
            ArchiveStreamSupplier supplier,
            ImageEntry coverEntry,
            Charset charset
    ) {
        ArchiveReadSession session = archiveSafetyPolicy.newReadSession();
        try (InputStream raw = supplier.open();
             ZipInputStream input = new ZipInputStream(raw, charset)) {
            ZipEntry entry;
            while ((entry = input.getNextEntry()) != null) {
                boolean targetEntry = !entry.isDirectory() && coverEntry.name().equals(entry.getName());
                EntryReadGuard guard = session.beginEntry(
                        entry,
                        targetEntry ? MAX_PAGE_IMAGE_SIZE : Long.MAX_VALUE
                );
                if (targetEntry) {
                    byte[] bytes = readArchiveEntryBytes(input, guard);
                    guard.complete(entry);
                    return new ReaderCoverDraft(
                            bytes,
                            ComicPageAssetService.detectMimeType(coverEntry.name()),
                            coverEntry.name()
                    );
                }
                drainArchiveEntry(input, guard);
                guard.complete(entry);
            }
        } catch (RuntimeException | IOException exception) {
            log.warn("漫画压缩包封面读取失败: errorType={}", exception.getClass().getSimpleName());
        }
        return null;
    }

    /**
     * JDK 对无法按指定字符集解码的条目名会报 "bad entry name"，也可能直接抛 MALFORMED。
     */
    private boolean isEntryNameEncodingFailure(ZipException exception) {
        String message = exception.getMessage();
        return message != null && message.toLowerCase(Locale.ROOT).contains("entry name");
    }

    /**
     * 条目名编码失败信号：仅用于触发一次 GB18030 重扫，不向外暴露。
     */
    private static final class ArchiveNameEncodingException extends RuntimeException {
        private ArchiveNameEncodingException(Throwable cause) {
            super(cause);
        }
    }

    private boolean isSystemFile(String name) {
        String normalized = name.toLowerCase(Locale.ROOT);
        return SYSTEM_PREFIXES.stream().anyMatch(prefix ->
                normalized.startsWith(prefix) || normalized.endsWith("/" + prefix));
    }

    private boolean isImageFile(String name) {
        String normalized = name.toLowerCase(Locale.ROOT);
        return IMAGE_EXTENSIONS.stream().anyMatch(normalized::endsWith);
    }

    static int naturalCompare(String left, String right) {
        var leftMatcher = NATURAL_SPLITTER.matcher(left);
        var rightMatcher = NATURAL_SPLITTER.matcher(right);
        List<String> leftParts = new ArrayList<>();
        List<String> rightParts = new ArrayList<>();
        while (leftMatcher.find()) {
            leftParts.add(leftMatcher.group());
        }
        while (rightMatcher.find()) {
            rightParts.add(rightMatcher.group());
        }
        for (int index = 0; index < Math.min(leftParts.size(), rightParts.size()); index++) {
            String leftPart = leftParts.get(index);
            String rightPart = rightParts.get(index);
            try {
                int compared = Integer.compare(Integer.parseInt(leftPart), Integer.parseInt(rightPart));
                if (compared != 0) {
                    return compared;
                }
            } catch (NumberFormatException exception) {
                int compared = leftPart.compareToIgnoreCase(rightPart);
                if (compared != 0) {
                    return compared;
                }
            }
        }
        return Integer.compare(leftParts.size(), rightParts.size());
    }

    private int readHeaderAndDrain(
            ZipInputStream input,
            EntryReadGuard guard,
            byte[] header
    ) throws IOException {
        byte[] buffer = new byte[8192];
        int headerSize = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            guard.recordBytes(read);
            if (headerSize < header.length) {
                int copied = Math.min(read, header.length - headerSize);
                System.arraycopy(buffer, 0, header, headerSize, copied);
                headerSize += copied;
            }
        }
        return headerSize;
    }

    private byte[] readArchiveEntryBytes(
            ZipInputStream input,
            EntryReadGuard guard
    ) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int read;
        while ((read = input.read(buffer)) != -1) {
            guard.recordBytes(read);
            if (output.size() + read > MAX_PAGE_IMAGE_SIZE) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "漫画页面图片超过大小限制");
            }
            output.write(buffer, 0, read);
        }
        return output.toByteArray();
    }

    private void drainArchiveEntry(ZipInputStream input, EntryReadGuard guard) throws IOException {
        byte[] buffer = new byte[8192];
        int read;
        while ((read = input.read(buffer)) != -1) {
            guard.recordBytes(read);
        }
    }

    /**
     * ZIP 图片条目。
     *
     * @param name 归档内路径
     * @param size 解压后大小
     * @param entryIndex 原始条目序号
     * @param width 图片宽度
     * @param height 图片高度
     */
    public record ImageEntry(
            String name,
            long size,
            int entryIndex,
            int width,
            int height
    ) {
    }
}
