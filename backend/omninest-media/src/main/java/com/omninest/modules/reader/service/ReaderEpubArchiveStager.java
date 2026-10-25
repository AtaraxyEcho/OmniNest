package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.processing.TempStagingPort;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileQueryService;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * EPUB 归档暂存服务，负责将对象存储中的归档安全写入临时文件并清理。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderEpubArchiveStager {

    private final FileQueryService fileQueryService;
    private final ReaderArchiveSafetyPolicy archiveSafetyPolicy;
    private final TempStagingPort tempStagingPort;

    /**
     * 将 EPUB 对象暂存到本地临时文件。
     *
     * @param fileNode 文件节点描述符
     * @return 可自动清理的暂存归档
     */
    public StagedArchive stage(FileDescriptor fileNode) {
        Path tempFile = null;
        try {
            tempFile = tempStagingPort.createTempFile("reader-epub", "omninest-epub-", ".epub");
            try (FileContentStream content = fileQueryService.openOwnedFileContent(
                    fileNode.ownerUserId(),
                    fileNode.id())) {
                archiveSafetyPolicy.copyArchive(
                        content.inputStream(),
                        tempFile,
                        fileNode.sizeBytes()
                );
            }
            return new StagedArchive(tempFile);
        } catch (BusinessException exception) {
            deleteTemporaryArchive(tempFile);
            throw exception;
        } catch (IOException exception) {
            deleteTemporaryArchive(tempFile);
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "EPUB 读取失败: " + exception.getMessage());
        }
    }

    private static void deleteTemporaryArchive(Path tempFile) {
        if (tempFile == null) {
            return;
        }
        try {
            Files.deleteIfExists(tempFile);
        } catch (IOException exception) {
            log.warn("EPUB 临时文件删除失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    /**
     * 可自动清理的 EPUB 暂存归档。
     *
     * @author OmniNest
     */
    public static final class StagedArchive implements AutoCloseable {

        private final Path path;

        private StagedArchive(Path path) {
            this.path = path;
        }

        /**
         * 获取临时归档路径。
         *
         * @return 临时归档路径
         */
        public Path path() {
            return path;
        }

        /**
         * 删除临时归档。
         */
        @Override
        public void close() {
            deleteTemporaryArchive(path);
        }
    }
}
