package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.dto.FileContentRange;
import com.omninest.modules.file.dto.FileContentStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 媒体探测输入暂存服务：把对象存储内容取成**本地文件**，供 ffprobe 读取。
 *
 * <p>存在的理由是探测输入形态决定的安全性质：ffprobe 拿到 URL 输入时，媒体内容里内嵌的
 * 远程引用（HLS/DASH 播放列表的分片地址、concat 列表）会被它自己跟随，任何提交前的地址校验
 * 都覆盖不到那批地址；而本地文件输入下 ffmpeg 的默认协议集就是 {@code file,crypto,data}，
 * 远程嵌套引用直接被拒。所以探测必须吃本地路径，不能吃预签名地址。
 *
 * <p>本地文件也不能是"下载完的整对象"：非 faststart 的 MP4 把 {@code moov} 放在文件末尾，
 * 只给头部会报 {@code moov atom not found}，但整对象落盘要付磁盘峰值。折中是只取头部与尾部
 * 两个有界窗口，按对象原始长度写成中间留空洞的稀疏文件——空洞填的是零，ffprobe 读到零
 * 不会得到看似合理但错误的元数据，只会干净失败并回空结果。
 *
 * <p>尾部窗口要能装下整份 {@code moov}：样本表随时长线性增长，长影片可到数 MB 级，因此默认取 8 MiB。
 * 索引大过默认窗口时探测只会得到空结果，所以还留一档放大重试（{@link #ESCALATED_TAIL_BYTES}），
 * 由调用方在"空结果且确实还有未覆盖字节"时触发；两次都不行才算这档内容没有元数据。
 * 工具缺失、超时等失败与这里同一条降级路径，都回空结果。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MediaProbeSourceStager {

    private static final long HEAD_BYTES = 2L * 1024 * 1024;
    /** 默认尾窗：实测够装常规时长的容器索引（90 分钟级影片样本表约 1–3 MiB）。 */
    public static final long DEFAULT_TAIL_BYTES = 8L * 1024 * 1024;
    /** 放大尾窗：默认窗探测为空且对象确实超出已覆盖字节时，只再多试这一档。 */
    public static final long ESCALATED_TAIL_BYTES = 32L * 1024 * 1024;
    private static final int COPY_BUFFER_BYTES = 64 * 1024;
    private static final Path PROCESSING_ROOT = Path.of(
            System.getProperty("java.io.tmpdir"), "omninest-probe");

    private final FileContentAccessService fileContentAccessService;

    /**
     * 用默认窗口为节点准备本地探测输入。
     *
     * @param node 已完成权限校验的文件节点
     * @return 探测输入；内容长度未知、提供者不支持区间读或读取失败时返回空
     */
    public Optional<StagedSource> stage(FileNode node) {
        return stage(node, DEFAULT_TAIL_BYTES);
    }

    /**
     * 按指定尾窗上限为节点准备本地探测输入。
     *
     * @param node 已完成权限校验的文件节点
     * @param maxTailBytes 尾窗字节上限
     * @return 探测输入；内容长度未知、提供者不支持区间读或读取失败时返回空
     */
    public Optional<StagedSource> stage(FileNode node, long maxTailBytes) {
        Path tempFile = null;
        try {
            Files.createDirectories(PROCESSING_ROOT);
            tempFile = Files.createTempFile(PROCESSING_ROOT, "probe-", ".bin");
            long totalBytes;
            long headBytes;
            try (FileContentStream head = fileContentAccessService.open(node);
                 OutputStream output = Files.newOutputStream(tempFile)) {
                totalBytes = head.sizeBytes();
                if (totalBytes <= 0) {
                    deleteQuietly(tempFile);
                    log.warn("媒体探测暂存跳过，内容长度未知: fileId={}", node.getId());
                    return Optional.empty();
                }
                headBytes = copyAtMost(head.inputStream(), output, Math.min(HEAD_BYTES, totalBytes));
            }
            long tailBytes = 0;
            if (totalBytes > headBytes) {
                tailBytes = Math.min(maxTailBytes, totalBytes - headBytes);
                long tailOffset = totalBytes - tailBytes;
                Optional<FileContentRange> range = fileContentAccessService.openRange(node, tailOffset, tailBytes);
                if (range.isEmpty()) {
                    deleteQuietly(tempFile);
                    log.warn("媒体探测暂存跳过，内容提供者不支持区间读: fileId={}", node.getId());
                    return Optional.empty();
                }
                try (FileContentRange tail = range.get()) {
                    writeAt(tempFile, tailOffset, tail.inputStream(), tailBytes);
                }
            }
            return Optional.of(new StagedSource(tempFile, true, totalBytes, headBytes + tailBytes));
        } catch (IOException | RuntimeException e) {
            if (tempFile != null) {
                deleteQuietly(tempFile);
            }
            log.warn("媒体探测暂存失败: fileId={}, message={}", node.getId(), e.getMessage());
            return Optional.empty();
        }
    }

    /**
     * 把区间字节写到稀疏文件的对象内真实偏移处。
     *
     * <p>位置不能压缩到头部之后：容器索引里的样本偏移是相对整份对象计算的，摆错位置会让
     * ffprobe 读到结构合法但内容错误的元数据，比失败更难发现。
     */
    private static void writeAt(Path file, long offset, InputStream input, long maxLength) throws IOException {
        byte[] buffer = new byte[COPY_BUFFER_BYTES];
        try (FileChannel channel = FileChannel.open(file, StandardOpenOption.WRITE)) {
            channel.position(offset);
            long written = 0;
            while (written < maxLength) {
                int requested = (int) Math.min(buffer.length, maxLength - written);
                int read = input.read(buffer, 0, requested);
                if (read == -1) {
                    break;
                }
                ByteBuffer pending = ByteBuffer.wrap(buffer, 0, read);
                while (pending.hasRemaining()) {
                    written += channel.write(pending);
                }
            }
        }
    }

    private static long copyAtMost(InputStream input, OutputStream output, long maxBytes) throws IOException {
        byte[] buffer = new byte[COPY_BUFFER_BYTES];
        long copied = 0;
        while (copied < maxBytes) {
            int requested = (int) Math.min(buffer.length, maxBytes - copied);
            int read = input.read(buffer, 0, requested);
            if (read == -1) {
                break;
            }
            output.write(buffer, 0, read);
            copied += read;
        }
        return copied;
    }

    private static void deleteQuietly(Path file) {
        try {
            Files.deleteIfExists(file);
        } catch (IOException e) {
            log.debug("媒体探测临时文件清理失败: {}", e.getMessage());
        }
    }

    /**
     * 探测输入句柄。
     *
     * <p>{@code close()} 只删除本类创建的临时文件；调用方不得把该路径交给他人长期持有。
     */
    public static final class StagedSource implements AutoCloseable {

        private final Path path;
        private final boolean tempFile;
        private final long totalBytes;
        private final long coveredBytes;

        private StagedSource(Path path, boolean tempFile, long totalBytes, long coveredBytes) {
            this.path = path;
            this.tempFile = tempFile;
            this.totalBytes = totalBytes;
            this.coveredBytes = coveredBytes;
        }

        /**
         * @return 供 ffprobe 直接读取的本地路径
         */
        public Path path() {
            return path;
        }

        /**
         * 判断"放大尾窗再试一次"是否可能取到还没覆盖到的字节。
         *
         * <p>容器索引落在已取回的两段窗口之外时，探测只能得到空结果；此时唯一还有意义的补救
         * 就是把尾窗拉长。对象已被完整覆盖时返回 false，避免对真的没有元数据的内容反复付费。
         *
         * @return 仍有未覆盖字节时返回 true
         */
        public boolean widerTailCouldHelp() {
            return totalBytes > coveredBytes;
        }

        @Override
        public void close() {
            if (tempFile) {
                deleteQuietly(path);
            }
        }
    }
}
