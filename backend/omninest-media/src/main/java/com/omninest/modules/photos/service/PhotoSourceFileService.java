package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.processing.TempStagingPort;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileQueryService;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 照片源文件的受限临时文件服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoSourceFileService {

    private static final int BUFFER_SIZE = 8192;

    private final FileQueryService fileQueryService;
    private final PhotoFileDetector fileDetector;
    private final PhotoInputGuard inputGuard;
    private final TempStagingPort tempStagingPort;

    /**
     * 将用户拥有的照片文件流式写入受控临时文件。
     *
     * @param ownerUserId 当前用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 需要由调用方关闭的临时文件句柄
     */
    public StagedPhotoFile stageOwned(UUID ownerUserId, UUID fileNodeId) {
        return stage(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId));
    }

    /**
     * 将用户可查看的照片文件流式写入受控临时文件。
     *
     * @param userId 当前用户 ID
     * @param fileNodeId 文件节点 ID
     * @return 需要由调用方关闭的临时文件句柄
     */
    public StagedPhotoFile stageReadable(UUID userId, UUID fileNodeId) {
        return stage(fileQueryService.openReadableFileContent(userId, fileNodeId));
    }

    /**
     * 将调用方提供的照片流写入受控临时文件。
     *
     * <p>该方法不关闭输入流，输入流生命周期由调用方管理。
     *
     * @param input 照片输入流
     * @param fileName 原始文件名
     * @param mimeType 文件 MIME 类型
     * @return 需要由调用方关闭的临时文件句柄
     */
    public StagedPhotoFile stageInput(InputStream input, String fileName, String mimeType) {
        boolean raw = fileDetector.isRaw(fileName);
        long maxBytes = inputGuard.maxFileBytes(raw);
        Path tempFile = null;
        try {
            tempFile = tempStagingPort.createTempFile("photo-source", "omninest-photo-source-", ".img");
            long actualSize = copyBounded(input, tempFile, maxBytes);
            inputGuard.validateFileSize(actualSize, raw);
            return new StagedPhotoFile(tempFile, fileName, actualSize, mimeType, raw);
        } catch (BusinessException exception) {
            deleteQuietly(tempFile);
            throw exception;
        } catch (IOException exception) {
            deleteQuietly(tempFile);
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "照片源文件暂存失败");
        }
    }

    private StagedPhotoFile stage(FileContentStream content) {
        StagedPhotoFile staged = null;
        try (content) {
            boolean raw = fileDetector.isRaw(content.fileName());
            inputGuard.validateFileSize(content.sizeBytes(), raw);
            staged = stageInput(content.inputStream(), content.fileName(), content.mimeType());
        } catch (IOException exception) {
            if (staged != null) {
                staged.close();
            }
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "照片源文件暂存失败");
        }
        return staged;
    }

    private long copyBounded(InputStream input, Path destination, long maxBytes) throws IOException {
        try (OutputStream output = Files.newOutputStream(destination)) {
            byte[] buffer = new byte[BUFFER_SIZE];
            long totalBytes = 0;
            int read;
            while ((read = input.read(buffer)) != -1) {
                totalBytes += read;
                if (totalBytes > maxBytes) {
                    throw new BusinessException(ErrorCode.PARAM_ERROR, "照片源文件超过大小限制");
                }
                output.write(buffer, 0, read);
            }
            return totalBytes;
        }
    }

    private static void deleteQuietly(Path file) {
        if (file == null) {
            return;
        }
        try {
            Files.deleteIfExists(file);
        } catch (IOException exception) {
            log.debug("照片临时文件清理失败，交由系统临时目录策略兜底: file={}", file, exception);
        }
    }

    /**
     * 受控照片临时文件句柄。
     *
     * @param path 临时文件路径
     * @param fileName 原始文件名
     * @param sizeBytes 源文件字节数
     * @param mimeType 源文件 MIME 类型
     * @param raw 是否为 RAW 文件
     */
    public record StagedPhotoFile(
            Path path,
            String fileName,
            long sizeBytes,
            String mimeType,
            boolean raw
    ) implements AutoCloseable {

        @Override
        public void close() {
            deleteQuietly(path);
        }
    }
}
