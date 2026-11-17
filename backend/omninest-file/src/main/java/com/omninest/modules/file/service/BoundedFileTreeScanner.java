package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.config.FileTransferLimitsProperties;
import java.io.IOException;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Iterator;
import java.util.List;
import java.util.stream.Stream;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 使用统一数量上限扫描和清理任务目录，避免完整文件树无界进入堆内存。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class BoundedFileTreeScanner {

    private final FileTransferLimitsProperties limits;

    /**
     * 按路径顺序返回目录内的普通文件。
     *
     * @param root 扫描根目录
     * @return 不超过配置上限的文件列表
     * @throws IOException 目录读取失败
     * @throws BusinessException 文件数量超过任务上限
     */
    public List<Path> listRegularFiles(Path root) throws IOException {
        List<Path> files = new ArrayList<>();
        try (Stream<Path> stream = Files.walk(root)) {
            Iterator<Path> paths = stream.iterator();
            while (paths.hasNext()) {
                Path path = paths.next();
                if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
                    continue;
                }
                if (files.size() >= limits.getMaxFilesPerTask()) {
                    throw new BusinessException(
                            ErrorCode.BAD_REQUEST,
                            "任务文件数量超过限制，最多允许 " + limits.getMaxFilesPerTask() + " 个文件"
                    );
                }
                files.add(path);
            }
        }
        files.sort(Comparator.naturalOrder());
        return List.copyOf(files);
    }

    /**
     * 以文件树访问器递归清理目录，不创建完整路径列表。
     *
     * @param root 待清理目录
     * @throws IOException 清理失败
     */
    public void deleteTree(Path root) throws IOException {
        if (!Files.exists(root, LinkOption.NOFOLLOW_LINKS)) {
            return;
        }
        Files.walkFileTree(root, new SimpleFileVisitor<>() {
            @Override
            public FileVisitResult visitFile(Path file, BasicFileAttributes attributes) throws IOException {
                Files.deleteIfExists(file);
                return FileVisitResult.CONTINUE;
            }

            @Override
            public FileVisitResult postVisitDirectory(Path directory, IOException exception) throws IOException {
                if (exception != null) {
                    throw exception;
                }
                Files.deleteIfExists(directory);
                return FileVisitResult.CONTINUE;
            }
        });
    }
}
