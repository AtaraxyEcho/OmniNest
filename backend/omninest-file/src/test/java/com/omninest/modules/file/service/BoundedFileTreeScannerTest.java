package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.config.FileTransferLimitsProperties;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * BoundedFileTreeScanner 单元测试。
 *
 * @author OmniNest
 */
class BoundedFileTreeScannerTest {

    @TempDir
    private Path tempDir;

    @Test
    void listRegularFiles_stopsWhenFileCountExceedsLimit() throws Exception {
        FileTransferLimitsProperties limits = new FileTransferLimitsProperties();
        limits.setMaxFilesPerTask(2);
        BoundedFileTreeScanner scanner = new BoundedFileTreeScanner(limits);
        Files.writeString(tempDir.resolve("a.txt"), "a");
        Files.writeString(tempDir.resolve("b.txt"), "b");
        Files.writeString(tempDir.resolve("c.txt"), "c");

        assertThatThrownBy(() -> scanner.listRegularFiles(tempDir))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("最多允许 2 个文件");
    }

    @Test
    void listRegularFiles_returnsSortedFilesWithinLimit() throws Exception {
        BoundedFileTreeScanner scanner = new BoundedFileTreeScanner(new FileTransferLimitsProperties());
        Path nested = Files.createDirectories(tempDir.resolve("nested"));
        Path second = Files.writeString(nested.resolve("b.txt"), "b");
        Path first = Files.writeString(tempDir.resolve("a.txt"), "a");

        List<Path> files = scanner.listRegularFiles(tempDir);

        assertThat(files).containsExactly(first, second);
    }

    @Test
    void deleteTree_removesNestedDirectoryWithoutMaterializingPaths() throws Exception {
        BoundedFileTreeScanner scanner = new BoundedFileTreeScanner(new FileTransferLimitsProperties());
        Path root = Files.createDirectories(tempDir.resolve("task/nested"));
        Files.writeString(root.resolve("file.txt"), "content");

        scanner.deleteTree(tempDir.resolve("task"));

        assertThat(tempDir.resolve("task")).doesNotExist();
    }
}
