package com.omninest.modules.file.service;

import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.function.LongConsumer;

/**
 * 提供外部导入传输使用的进度跟踪与有界读取流。
 *
 * @author OmniNest
 */
final class ExternalImportStreams {

    private ExternalImportStreams() {
    }

    static InputStream tracking(InputStream delegate, LongConsumer onProgress) {
        return new ProgressInputStream(delegate, onProgress);
    }

    static InputStream bounded(RandomAccessFile file, long limit, LongConsumer onProgress) {
        return new BoundedRandomAccessInputStream(file, limit, onProgress);
    }

    /**
     * 计算本地文件的 SHA-256 十六进制摘要。
     *
     * <p>仅用于导入重试的同名同内容比对：调用方先确认目标目录存在同名节点才会调用，
     * 常态导入不会因此多读一遍文件。</p>
     *
     * @param path 待计算文件
     * @return 小写十六进制摘要
     */
    static String sha256Hex(Path path) {
        try (InputStream input = new BufferedInputStream(Files.newInputStream(path), 64 * 1024)) {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = input.read(buffer)) >= 0) {
                digest.update(buffer, 0, read);
            }
            return HexFormat.of().formatHex(digest.digest());
        } catch (IOException e) {
            throw new IllegalStateException("读取文件摘要失败: " + path.getFileName(), e);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("当前运行环境不支持 SHA-256", e);
        }
    }

    /**
     * 在读取时回调累计字节数的输入流。
     *
     * @author OmniNest
     */
    private static final class ProgressInputStream extends InputStream {
        private final InputStream delegate;
        private final LongConsumer onProgress;
        private long totalRead;

        private ProgressInputStream(InputStream delegate, LongConsumer onProgress) {
            this.delegate = delegate;
            this.onProgress = onProgress;
        }

        @Override
        public int read() throws IOException {
            int value = delegate.read();
            if (value >= 0) {
                totalRead++;
                onProgress.accept(totalRead);
            }
            return value;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            int read = delegate.read(buffer, offset, length);
            if (read > 0) {
                totalRead += read;
                onProgress.accept(totalRead);
            }
            return read;
        }

        @Override
        public int available() throws IOException {
            return delegate.available();
        }

        @Override
        public void close() throws IOException {
            delegate.close();
        }
    }

    /**
     * 从随机访问文件当前位置读取固定长度内容的输入流。
     *
     * @author OmniNest
     */
    private static final class BoundedRandomAccessInputStream extends InputStream {
        private final RandomAccessFile file;
        private final long limit;
        private final LongConsumer onProgress;
        private long bytesRead;

        private BoundedRandomAccessInputStream(RandomAccessFile file, long limit, LongConsumer onProgress) {
            this.file = file;
            this.limit = limit;
            this.onProgress = onProgress;
        }

        @Override
        public int read() throws IOException {
            if (bytesRead >= limit) {
                return -1;
            }
            int value = file.read();
            if (value >= 0) {
                bytesRead++;
                onProgress.accept(bytesRead);
            }
            return value;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            if (bytesRead >= limit) {
                return -1;
            }
            int allowedLength = (int) Math.min(length, limit - bytesRead);
            int read = file.read(buffer, offset, allowedLength);
            if (read > 0) {
                bytesRead += read;
                onProgress.accept(bytesRead);
            }
            return read;
        }

        @Override
        public void close() {
            // RandomAccessFile 由调用方的 try-with-resources 管理。
        }
    }
}
