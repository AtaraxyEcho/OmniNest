package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.MalwareScanGateway;
import com.omninest.common.security.MalwareScanGateway.ScanResult;
import com.omninest.common.security.MalwareScanGateway.Status;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.SequenceInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.tika.Tika;
import org.apache.tika.mime.MediaType;
import org.springframework.stereotype.Service;

/**
 * 统一执行文件入口的病毒扫描和服务端摘要计算。
 * 同时统计实际字节数并按魔数探测 MIME，供晋升阶段核对申报大小与声明类型。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileIngressSafetyService {

    /**
     * 魔数嗅探读取的前缀上限；Tika 检测绝大多数格式所需的字节远小于此值。
     */
    private static final int MAGIC_SNIFF_LIMIT_BYTES = 64 * 1024;

    /**
     * Tika 门面线程安全，允许静态复用。
     */
    private static final Tika TIKA = new Tika();

    private final MalwareScanGateway malwareScanGateway;
    private final ObjectStorageClient objectStorageClient;

    /**
     * 检查本地待入库文件。
     *
     * @param file 待检查文件
     * @param sourceType 来源类型
     * @param correlationId 来源任务或会话标识
     * @return 安全检查结果
     */
    public InspectionResult inspect(Path file, String sourceType, UUID correlationId) {
        try {
            long sizeBytes = Files.size(file);
            try (InputStream inputStream = Files.newInputStream(file)) {
                return inspectStream(inputStream, sizeBytes, file.getFileName().toString(), sourceType, correlationId);
            }
        } catch (IOException exception) {
            log.warn("读取待入库文件失败: sourceType={}, correlationId={}, errorType={}",
                    sourceType, correlationId, exception.getClass().getSimpleName());
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "无法读取待入库文件");
        }
    }

    /**
     * 检查隔离桶中的待入库对象。
     *
     * @param key 隔离对象键
     * @param sizeBytes 申报的对象大小
     * @param fileName 文件名提示，可为 null（仅凭魔数探测）
     * @param sourceType 来源类型
     * @param correlationId 来源任务或会话标识
     * @return 安全检查结果
     */
    public InspectionResult inspect(
            ObjectStorageKey key,
            long sizeBytes,
            String fileName,
            String sourceType,
            UUID correlationId
    ) {
        try (InputStream inputStream = objectStorageClient.getObject(key)) {
            return inspectStream(inputStream, sizeBytes, fileName, sourceType, correlationId);
        } catch (IOException exception) {
            log.warn("读取隔离对象失败: sourceType={}, correlationId={}, bucket={}, errorType={}",
                    sourceType, correlationId, key.bucket(), exception.getClass().getSimpleName());
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "无法读取待扫描对象");
        }
    }

    private InspectionResult inspectStream(
            InputStream inputStream,
            long declaredSizeBytes,
            String fileName,
            String sourceType,
            UUID correlationId
    ) throws IOException {
        // 申报值小于魔数窗口时只嗅探“申报大小 + 1”：多出的 1 字节足以证明超限，
        // 同时让 actualSizeBytes 对超限对象稳定落在 declared + 1。
        int sniffLimit = declaredSizeBytes >= 0
                        && declaredSizeBytes < MAGIC_SNIFF_LIMIT_BYTES - 1L
                ? (int) (declaredSizeBytes + 1L)
                : MAGIC_SNIFF_LIMIT_BYTES;
        byte[] prefix = inputStream.readNBytes(sniffLimit);
        CountingInputStream remaining = new CountingInputStream(inputStream);
        MessageDigest digest = sha256Digest();
        // 直传预签名不限制请求体大小：低报尺寸的客户端可能把数十 GB 对象写进隔离桶。
        // 扫描与摘要最多读取“申报大小 + 1”字节；多出的 1 字节作为超限证据，
        // 由晋升阶段按实际大小不一致拒绝，避免 Worker 被恶意对象耗尽 I/O。
        long readLimit = declaredSizeBytes < 0 || declaredSizeBytes == Long.MAX_VALUE
                ? Long.MAX_VALUE
                : declaredSizeBytes + 1L;
        ScanResult result;
        try (InputStream bounded = new BoundedInputStream(
                new SequenceInputStream(new ByteArrayInputStream(prefix), remaining), readLimit);
                DigestInputStream digestInputStream = new DigestInputStream(bounded, digest)) {
            result = malwareScanGateway.scan(digestInputStream, declaredSizeBytes);
            digestInputStream.transferTo(OutputStream.nullOutputStream());
        }
        requireAccepted(result, sourceType, correlationId);
        return new InspectionResult(
                result.status(),
                result.message(),
                HexFormat.of().formatHex(digest.digest()),
                prefix.length + remaining.getCount(),
                detectMimeType(prefix, fileName)
        );
    }

    private String detectMimeType(byte[] prefix, String fileName) {
        if (prefix.length == 0) {
            return null;
        }
        try {
            String detected = TIKA.detect(new ByteArrayInputStream(prefix), fileName);
            if (detected == null || detected.isBlank() || MediaType.OCTET_STREAM.toString().equals(detected)) {
                return null;
            }
            return detected;
        } catch (IOException exception) {
            log.debug("MIME 魔数探测失败: errorType={}", exception.getClass().getSimpleName());
            return null;
        }
    }

    private void requireAccepted(ScanResult result, String sourceType, UUID correlationId) {
        if (result.status() == Status.CLEAN || result.status() == Status.SKIPPED) {
            if (result.status() == Status.SKIPPED) {
                log.info("文件安全扫描未启用: sourceType={}, correlationId={}", sourceType, correlationId);
            }
            return;
        }
        if (result.status() == Status.INFECTED) {
            log.warn("待入库文件检测到威胁: sourceType={}, correlationId={}, detail={}",
                    sourceType, correlationId, result.message());
            throw new BusinessException(ErrorCode.FILE_SECURITY_REJECTED, "文件安全扫描未通过，内容已拒绝入库");
        }
        log.warn("文件安全扫描不可用: sourceType={}, correlationId={}, detail={}",
                sourceType, correlationId, result.message());
        throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "ClamAV 安全扫描不可用，文件保持隔离");
    }

    private MessageDigest sha256Digest() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("运行环境不支持 SHA-256", exception);
        }
    }

    /**
     * 统计已读字节数的轻量包装，供实际大小核对使用。
     */
    private static final class CountingInputStream extends InputStream {
        private final InputStream delegate;
        private long count;

        private CountingInputStream(InputStream delegate) {
            this.delegate = delegate;
        }

        @Override
        public int read() throws IOException {
            int value = delegate.read();
            if (value >= 0) {
                count++;
            }
            return value;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            int read = delegate.read(buffer, offset, length);
            if (read > 0) {
                count += read;
            }
            return read;
        }

        @Override
        public void close() throws IOException {
            delegate.close();
        }

        long getCount() {
            return count;
        }
    }

    /**
     * 只允许读取指定上限字节的包装流，超限部分不再读取。
     */
    private static final class BoundedInputStream extends InputStream {
        private final InputStream delegate;
        private long remaining;

        private BoundedInputStream(InputStream delegate, long remaining) {
            this.delegate = delegate;
            this.remaining = remaining;
        }

        @Override
        public int read() throws IOException {
            if (remaining <= 0) {
                return -1;
            }
            int value = delegate.read();
            if (value >= 0) {
                remaining--;
            }
            return value;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            if (remaining <= 0) {
                return -1;
            }
            int read = delegate.read(buffer, offset, (int) Math.min(length, remaining));
            if (read > 0) {
                remaining -= read;
            }
            return read;
        }

        @Override
        public void close() throws IOException {
            delegate.close();
        }
    }

    /**
     * 文件入口安全检查结果。
     *
     * @param status 扫描状态
     * @param message 扫描摘要
     * @param sha256 服务端计算的文件摘要
     * @param actualSizeBytes 服务端统计的实际字节数；未统计（兼容旧调用）时为 -1
     * @param detectedMimeType 魔数探测的 MIME；未识别或探测失败时为 null
     * @author OmniNest
     */
    public record InspectionResult(
            Status status,
            String message,
            String sha256,
            long actualSizeBytes,
            String detectedMimeType
    ) {
        public InspectionResult(Status status, String message, String sha256) {
            this(status, message, sha256, -1L, null);
        }
    }
}
