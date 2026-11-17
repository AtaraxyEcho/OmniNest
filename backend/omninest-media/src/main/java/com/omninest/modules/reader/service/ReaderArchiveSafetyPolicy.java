package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.reader.config.ReaderArchiveLimitsProperties;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * Reader 压缩包大小、条目路径和解压预算统一校验策略。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class ReaderArchiveSafetyPolicy {

    private static final int BUFFER_SIZE = 8192;

    private final ReaderArchiveLimitsProperties properties;

    /**
     * 校验压缩文件本身的字节数。
     *
     * @param sizeBytes 压缩文件字节数
     */
    public void validateArchiveSize(long sizeBytes) {
        if (sizeBytes <= 0 || sizeBytes > properties.getMaxArchiveBytes()) {
            throw invalidArchive("压缩文件大小超出限制");
        }
    }

    /**
     * 将压缩文件输入流有界写入本地文件。
     *
     * <p>该方法不关闭输入流，输入流生命周期由调用方管理。
     *
     * @param input 压缩文件输入流
     * @param destination 目标文件
     * @param declaredSize 元数据声明的文件字节数
     * @return 实际写入字节数
     * @throws IOException 本地文件写入失败
     */
    public long copyArchive(InputStream input, Path destination, long declaredSize) throws IOException {
        validateArchiveSize(declaredSize);
        long totalBytes = 0;
        try (OutputStream output = Files.newOutputStream(destination)) {
            byte[] buffer = new byte[BUFFER_SIZE];
            int read;
            while ((read = input.read(buffer)) != -1) {
                totalBytes = addExact(totalBytes, read, "压缩文件大小超出限制");
                if (totalBytes > properties.getMaxArchiveBytes()) {
                    throw invalidArchive("压缩文件大小超出限制");
                }
                output.write(buffer, 0, read);
            }
        }
        validateArchiveSize(totalBytes);
        return totalBytes;
    }

    /**
     * 校验可随机访问 ZIP 的中央目录元数据。
     *
     * @param zipFile ZIP 文件
     */
    public void validateZipFile(ZipFile zipFile) {
        ArchiveReadSession session = newReadSession();
        Enumeration<? extends ZipEntry> entries = zipFile.entries();
        while (entries.hasMoreElements()) {
            ZipEntry entry = entries.nextElement();
            EntryReadGuard guard = session.beginEntry(entry, properties.getMaxEntryBytes());
            guard.complete(entry);
        }
    }

    /**
     * 创建一次顺序解压过程使用的预算会话。
     *
     * @return 解压预算会话
     */
    public ArchiveReadSession newReadSession() {
        return new ArchiveReadSession();
    }

    private String normalizeEntryName(String entryName, boolean directory) {
        if (entryName == null || entryName.isBlank() || entryName.indexOf('\0') >= 0) {
            throw invalidArchive("压缩包条目路径无效");
        }
        String path = entryName.replace('\\', '/');
        if (path.startsWith("/") || hasWindowsDrivePrefix(path)) {
            throw invalidArchive("压缩包条目路径越界");
        }
        Deque<String> segments = new ArrayDeque<>();
        for (String segment : path.split("/")) {
            if (segment.isEmpty() || ".".equals(segment)) {
                continue;
            }
            if ("..".equals(segment)) {
                throw invalidArchive("压缩包条目路径越界");
            }
            segments.addLast(segment);
        }
        if (segments.isEmpty()) {
            if (directory) {
                // 显式根目录项（"./" 或只有 "." 的条目）没有可提取内容。
                return "";
            }
            throw invalidArchive("压缩包条目路径无效");
        }
        return String.join("/", segments);
    }

    private boolean hasWindowsDrivePrefix(String path) {
        return path.length() >= 2
                && Character.isLetter(path.charAt(0))
                && path.charAt(1) == ':';
    }

    private void validateCompressionRatio(long uncompressedBytes, long compressedBytes) {
        if (uncompressedBytes < properties.getCompressionRatioCheckThresholdBytes()
                || compressedBytes <= 0) {
            return;
        }
        double ratio = (double) uncompressedBytes / compressedBytes;
        if (ratio > properties.getMaxCompressionRatio()) {
            throw invalidArchive("压缩包条目压缩比超出限制");
        }
    }

    private long addExact(long current, long delta, String message) {
        try {
            return Math.addExact(current, delta);
        } catch (ArithmeticException exception) {
            throw invalidArchive(message);
        }
    }

    private BusinessException invalidArchive(String message) {
        return new BusinessException(ErrorCode.PARAM_ERROR, message);
    }

    /**
     * 一次顺序解压过程的条目数和总解压字节预算。
     *
     * @author OmniNest
     */
    public final class ArchiveReadSession {

        private final Set<String> normalizedEntryNames = new HashSet<>();
        private int entryCount;
        private long totalUncompressedBytes;

        /**
         * 开始校验并读取一个 ZIP 条目。
         *
         * @param entry ZIP 条目
         * @param operationEntryLimit 当前操作允许的单条目上限
         * @return 条目读取守卫
         */
        public EntryReadGuard beginEntry(ZipEntry entry, long operationEntryLimit) {
            entryCount++;
            if (entryCount > properties.getMaxEntries()) {
                throw invalidArchive("压缩包条目数量超出限制");
            }
            boolean directory = entry.isDirectory();
            String normalizedName = normalizeEntryName(entry.getName(), directory);
            // 目录条目只承载结构信息：部分打包器会把同一条目录项重复写入，
            // 命中重复不该让整包被判为非法；根目录项 "./" 归一化为空串。
            if (!directory && !normalizedEntryNames.add(normalizedName)) {
                throw invalidArchive("压缩包包含重复条目路径");
            }

            long entryLimit = Math.min(properties.getMaxEntryBytes(), operationEntryLimit);
            long declaredSize = entry.getSize();
            if (declaredSize > entryLimit) {
                throw invalidArchive("压缩包条目大小超出限制");
            }
            if (declaredSize >= 0) {
                reserveTotal(declaredSize);
                validateCompressionRatio(declaredSize, entry.getCompressedSize());
            }
            return new EntryReadGuard(this, entryLimit, declaredSize, entry.getCompressedSize());
        }

        private void reserveTotal(long bytes) {
            totalUncompressedBytes = addExact(
                    totalUncompressedBytes,
                    bytes,
                    "压缩包解压后总大小超出限制"
            );
            if (totalUncompressedBytes > properties.getMaxTotalUncompressedBytes()) {
                throw invalidArchive("压缩包解压后总大小超出限制");
            }
        }
    }

    /**
     * 单个 ZIP 条目的实际读取字节守卫。
     *
     * @author OmniNest
     */
    public final class EntryReadGuard {

        private final ArchiveReadSession session;
        private final long entryLimit;
        private final long declaredSize;
        private final long initialCompressedSize;
        private long actualBytes;
        private long reservedBytes;

        private EntryReadGuard(
                ArchiveReadSession session,
                long entryLimit,
                long declaredSize,
                long initialCompressedSize
        ) {
            this.session = session;
            this.entryLimit = entryLimit;
            this.declaredSize = declaredSize;
            this.initialCompressedSize = initialCompressedSize;
            this.reservedBytes = Math.max(0, declaredSize);
        }

        /**
         * 记录当前条目新增读取的解压字节数。
         *
         * @param bytes 新增读取字节数
         */
        public void recordBytes(int bytes) {
            if (bytes <= 0) {
                return;
            }
            actualBytes = addExact(actualBytes, bytes, "压缩包条目大小超出限制");
            if (actualBytes > entryLimit) {
                throw invalidArchive("压缩包条目大小超出限制");
            }
            if (actualBytes > reservedBytes) {
                session.reserveTotal(actualBytes - reservedBytes);
                reservedBytes = actualBytes;
            }
        }

        /**
         * 完成当前条目读取并校验最终压缩比。
         *
         * @param entry 已完成读取的 ZIP 条目
         */
        public void complete(ZipEntry entry) {
            long uncompressedBytes = Math.max(actualBytes, declaredSize);
            long compressedBytes = entry.getCompressedSize() > 0
                    ? entry.getCompressedSize()
                    : initialCompressedSize;
            validateCompressionRatio(uncompressedBytes, compressedBytes);
        }

        /**
         * 返回当前条目已读取的解压字节数。
         *
         * @return 已读取字节数
         */
        public long bytesRead() {
            return actualBytes;
        }
    }
}
