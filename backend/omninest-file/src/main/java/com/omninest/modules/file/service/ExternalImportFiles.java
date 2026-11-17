package com.omninest.modules.file.service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import lombok.extern.slf4j.Slf4j;

/**
 * 外部导入的文件级小工具：MIME 推断、大小读取、错误摘要与轮询等待。
 *
 * <p>从执行服务拆出，避免主流程类因这些无状态辅助方法越过源码行数上限。</p>
 *
 * @author OmniNest
 */
@Slf4j
final class ExternalImportFiles {

    private ExternalImportFiles() {
    }

    /**
     * 只用于隔离上传阶段的 Content-Type 种子：外部来源没有客户端申报，先按扩展名与系统探测给一个候选值，
     * 真实类型以扫描阶段 {@link FileIngressSafetyService} 的魔数结果为准。
     */
    static String detectMimeType(Path file) {
        try {
            String mimeType = Files.probeContentType(file);
            if (mimeType != null && !mimeType.isBlank()) {
                return mimeType;
            }
        } catch (IOException e) {
            log.debug("系统探测 MIME 失败，降级到扩展名推断: file={}", file.getFileName(), e);
        }
        return FileUploadSessionService.guessMimeTypeByFileName(
                file.getFileName().toString());
    }

    /**
     * 以魔数结果修正入库 MIME，规则与 {@code FileIngressPromotionService} 的晋升一致：
     * 探测无结论（null）时保留推断值，否则一律采用探测值。外部来源的文件名与字节经常不一致
     * （改名、无扩展名、伪装扩展名），错误的 MIME 会让下载与内联播放拿到错的 Content-Type。
     */
    static String resolveDetectedMimeType(String fileName, String guessedMimeType, String detectedMimeType) {
        if (detectedMimeType == null || detectedMimeType.equals(guessedMimeType)) {
            return guessedMimeType;
        }
        log.info("外部导入 MIME 按魔数修正: fileName={}, guessed={}, detected={}",
                fileName, guessedMimeType, detectedMimeType);
        return detectedMimeType;
    }

    static long fileSize(Path file) {
        try {
            return Files.size(file);
        } catch (IOException e) {
            throw new IllegalStateException("读取文件大小失败", e);
        }
    }

    static String summarize(Exception exception) {
        String message = exception.getMessage();
        if (message == null || message.isBlank()) {
            return exception.getClass().getSimpleName();
        }
        return message.length() > 500 ? message.substring(0, 500) : message;
    }

    static void sleep(int seconds) {
        try {
            Thread.sleep(Duration.ofSeconds(seconds).toMillis());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("导入轮询被中断", e);
        }
    }

    static void cleanupTempDir(BoundedFileTreeScanner scanner, Path tempDir) {
        try {
            scanner.deleteTree(tempDir);
        } catch (IOException exception) {
            log.debug("导入临时目录清理失败，不影响主流程: dir={}", tempDir, exception);
        }
    }
}
