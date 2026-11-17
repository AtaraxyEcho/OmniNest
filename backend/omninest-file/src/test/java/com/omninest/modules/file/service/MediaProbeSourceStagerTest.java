package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.dto.FileContentRange;
import com.omninest.modules.file.dto.FileProcessInput;
import com.omninest.modules.file.dto.FileContentStream;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 探测输入暂存测试：窗口切分、稀疏落位与失败清理。
 *
 * @author OmniNest
 */
@DisplayName("MediaProbeSourceStager 窗口与清理测试")
class MediaProbeSourceStagerTest {

    private static final long HEAD_BYTES = 2L * 1024 * 1024;
    private static final long TAIL_BYTES = 8L * 1024 * 1024;
    private static final Path PROCESSING_ROOT = Path.of(
            System.getProperty("java.io.tmpdir"), "omninest-probe");

    private final FileContentAccessService fileContentAccessService =
            mock(FileContentAccessService.class);
    private final MediaProbeSourceStager stager =
            new MediaProbeSourceStager(fileContentAccessService, new TestTempStagingPort());

    @Test
    @DisplayName("不超过头窗口的对象整份取回，不请求区间读")
    void copiesSmallObjectWithoutRangedRead() throws IOException {
        byte[] content = pattern(1024);
        FileNode node = node();
        stubHead(node, content, content.length);

        Optional<MediaProbeSourceStager.StagedSource> staged = stager.stage(node);
        assertThat(staged).isPresent();
        try (MediaProbeSourceStager.StagedSource source = staged.get()) {
            assertThat(Files.readAllBytes(source.path())).containsExactly(content);
        }
        verify(fileContentAccessService, never()).openRange(any(), anyLong(), anyLong());
    }

    @Test
    @DisplayName("尾部窗口按对象内真实偏移落位，中间留零空洞")
    void writesTailAtItsRealOffsetAndLeavesZeroHole() throws IOException {
        long total = 12L * 1024 * 1024;
        byte[] full = pattern(total);
        byte[] head = Arrays.copyOfRange(full, 0, (int) HEAD_BYTES);
        long tailOffset = total - TAIL_BYTES;
        byte[] tail = Arrays.copyOfRange(full, (int) tailOffset, (int) total);
        FileNode node = node();
        stubHead(node, head, total);
        when(fileContentAccessService.openRange(node, tailOffset, TAIL_BYTES))
                .thenReturn(Optional.of(new FileContentRange(new ByteArrayInputStream(tail), total)));

        Optional<MediaProbeSourceStager.StagedSource> staged = stager.stage(node);
        assertThat(staged).isPresent();
        byte[] stagedBytes;
        try (MediaProbeSourceStager.StagedSource source = staged.get()) {
            assertThat(Files.size(source.path())).isEqualTo(total);
            stagedBytes = Files.readAllBytes(source.path());
        }

        assertThat(Arrays.copyOfRange(stagedBytes, 0, (int) HEAD_BYTES)).containsExactly(head);
        assertThat(Arrays.copyOfRange(stagedBytes, (int) tailOffset, (int) total)).containsExactly(tail);
        byte[] hole = Arrays.copyOfRange(stagedBytes, (int) HEAD_BYTES, (int) tailOffset);
        assertThat(Arrays.mismatch(hole, new byte[hole.length]))
                .as("空洞必须全是零：非零字节会让 ffprobe 读出结构合法但内容错误的元数据")
                .isEqualTo(-1);
    }

    @Test
    @DisplayName("提供者不支持区间读时放弃暂存并删掉已建的临时文件")
    void givesUpWhenProviderCannotReadRange() throws IOException {
        long total = HEAD_BYTES + 1024;
        FileNode node = node();
        stubHead(node, pattern(HEAD_BYTES), total);
        when(fileContentAccessService.openRange(eq(node), anyLong(), anyLong()))
                .thenReturn(Optional.empty());
        when(fileContentAccessService.createProcessInput(node))
                .thenReturn(new FileProcessInput(node.getId(), "MINIO", "http://minio/object"));
        Set<Path> before = probeFiles();

        assertThat(stager.stage(node)).isEmpty();
        assertNoProbeFileCreated(before);
    }

    @Test
    @DisplayName("本地只读来源直接返回本机路径且不复制")
    void returnsLocalPathForLocalFilesystemProvider() throws IOException {
        Path local = Files.createTempFile("probe-local-", ".mkv");
        Files.write(local, new byte[]{1, 2, 3});
        try {
            FileNode node = node();
            stubHead(node, pattern(HEAD_BYTES), HEAD_BYTES + 1);
            when(fileContentAccessService.openRange(eq(node), anyLong(), anyLong()))
                    .thenReturn(Optional.empty());
            when(fileContentAccessService.createProcessInput(node))
                    .thenReturn(new FileProcessInput(node.getId(), "LOCAL_FILESYSTEM", local.toString()));
            Set<Path> before = probeFiles();

            MediaProbeSourceStager.StagedSource source = stager.stage(node).orElseThrow();
            try (source) {
                assertThat(source.path()).isEqualTo(local);
                assertThat(source.widerTailCouldHelp()).isFalse();
            }
            assertNoProbeFileCreated(before);
        } finally {
            Files.deleteIfExists(local);
        }
    }

    @Test
    @DisplayName("内容长度未知时不暂存")
    void givesUpWhenSizeUnknown() throws IOException {
        FileNode node = node();
        stubHead(node, new byte[0], 0L);
        Set<Path> before = probeFiles();

        assertThat(stager.stage(node)).isEmpty();
        assertNoProbeFileCreated(before);
        verify(fileContentAccessService, never()).openRange(any(), anyLong(), anyLong());
    }

    @Test
    @DisplayName("内容读取抛异常时不暂存也不留文件")
    void givesUpWhenContentReadFails() throws IOException {
        FileNode node = node();
        when(fileContentAccessService.open(node))
                .thenThrow(new UncheckedIOException(new IOException("对象存储不可达")));
        Set<Path> before = probeFiles();

        assertThat(stager.stage(node)).isEmpty();
        assertNoProbeFileCreated(before);
    }

    @Test
    @DisplayName("关闭句柄即删除临时文件")
    void deletesTempFileOnClose() throws IOException {
        byte[] content = pattern(4096);
        FileNode node = node();
        stubHead(node, content, content.length);

        MediaProbeSourceStager.StagedSource source = stager.stage(node).orElseThrow();
        Path path = source.path();
        assertThat(Files.exists(path)).isTrue();
        source.close();
        assertThat(Files.exists(path)).isFalse();
    }

    @Test
    @DisplayName("放大尾窗按新窗口重新落位，而不是补在默认窗后面")
    void escalatedWindowRewritesTailAtNewOffset() throws IOException {
        long total = 12L * 1024 * 1024;
        long tailBytes = 4L * 1024 * 1024;
        byte[] full = pattern(total);
        long tailOffset = total - tailBytes;
        FileNode node = node();
        stubHead(node, Arrays.copyOfRange(full, 0, (int) HEAD_BYTES), total);
        when(fileContentAccessService.openRange(node, tailOffset, tailBytes))
                .thenReturn(Optional.of(new FileContentRange(
                        new ByteArrayInputStream(Arrays.copyOfRange(full, (int) tailOffset, (int) total)), total)));

        byte[] stagedBytes;
        try (MediaProbeSourceStager.StagedSource source = stager.stage(node, tailBytes).orElseThrow()) {
            stagedBytes = Files.readAllBytes(source.path());
            assertThat(Files.size(source.path())).isEqualTo(total);
        }

        assertThat(Arrays.copyOfRange(stagedBytes, (int) tailOffset, (int) total))
                .containsExactly(Arrays.copyOfRange(full, (int) tailOffset, (int) total));
        byte[] hole = Arrays.copyOfRange(stagedBytes, (int) HEAD_BYTES, (int) tailOffset);
        assertThat(Arrays.mismatch(hole, new byte[hole.length]))
                .as("尾窗换档后新增的空洞同样必须是零，否则 ffprobe 会读出结构合法但内容错误的元数据")
                .isEqualTo(-1);
    }

    @Test
    @DisplayName("默认窗没覆盖完整对象时才允许放大重试")
    void escalationOnlyWhenBytesRemainUncovered() throws IOException {
        long twelveMegabytes = 12L * 1024 * 1024;
        FileNode big = node();
        stubHead(big, pattern(HEAD_BYTES), twelveMegabytes);
        when(fileContentAccessService.openRange(eq(big), anyLong(), anyLong()))
                .thenReturn(Optional.of(new FileContentRange(
                        new ByteArrayInputStream(pattern(
                                MediaProbeSourceStager.DEFAULT_TAIL_BYTES)), twelveMegabytes)));
        try (MediaProbeSourceStager.StagedSource source = stager.stage(big).orElseThrow()) {
            assertThat(source.widerTailCouldHelp()).isTrue();
        }

        long fiveMegabytes = 5L * 1024 * 1024;
        FileNode covered = node();
        stubHead(covered, pattern(HEAD_BYTES), fiveMegabytes);
        when(fileContentAccessService.openRange(eq(covered), anyLong(), anyLong()))
                .thenReturn(Optional.of(new FileContentRange(
                        new ByteArrayInputStream(pattern(fiveMegabytes - HEAD_BYTES)), fiveMegabytes)));
        try (MediaProbeSourceStager.StagedSource source = stager.stage(covered).orElseThrow()) {
            assertThat(source.widerTailCouldHelp())
                    .as("对象已被头尾两窗完整覆盖时，放大尾窗只会重复读同样的字节")
                    .isFalse();
        }
    }

    private void stubHead(FileNode node, byte[] head, long totalBytes) {
        when(fileContentAccessService.open(node)).thenReturn(new FileContentStream(
                new ByteArrayInputStream(head), "clip.mp4", totalBytes, "video/mp4"));
    }

    /** 暂存目录当前的文件集合，用作"本次没有留下新文件"的对照基线。 */
    private static Set<Path> probeFiles() throws IOException {
        if (!Files.isDirectory(PROCESSING_ROOT)) {
            return Set.of();
        }
        try (var files = Files.list(PROCESSING_ROOT)) {
            return files.collect(Collectors.toSet());
        }
    }

    private static void assertNoProbeFileCreated(Set<Path> before) throws IOException {
        Set<Path> after = probeFiles();
        Set<Path> created = new HashSet<>(after);
        created.removeAll(before);
        assertThat(created).as("失败路径不得留下探测临时文件").isEmpty();
    }

    /** 按位置取模的字节图案，用来证明窗口落点而不是只证明写了多少字节。 */
    private static byte[] pattern(long length) {
        byte[] bytes = new byte[(int) length];
        for (int i = 0; i < bytes.length; i++) {
            bytes[i] = (byte) (i % 251);
        }
        return bytes;
    }

    private static FileNode node() {
        FileNode node = new FileNode();
        node.setId(UUID.fromString("30000000-0000-0000-0000-000000000001"));
        node.setName("clip.mp4");
        node.setMimeType("video/mp4");
        node.setCurrentObjectId(UUID.fromString("30000000-0000-0000-0000-000000000002"));
        return node;
    }
}
