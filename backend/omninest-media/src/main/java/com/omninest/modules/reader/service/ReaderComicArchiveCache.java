package com.omninest.modules.reader.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.github.benmanes.caffeine.cache.RemovalCause;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.processing.TempStagingPort;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileQueryService;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.time.Duration;
import java.util.Enumeration;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 漫画来源归档的本地受控缓存。
 *
 * <p>按页读取 ZIP/CBZ 时若每次都从对象存储重新下载并顺序解压，
 * 翻到后半册会产生 O(N) 的无效流量与解压开销。这里把归档暂存到
 * {@code omninest.processing.root} 下的自有子目录，按文件节点 + 大小 + 更新时间缓存路径，
 * 每页再用 {@link java.util.zip.ZipFile} 按中央目录 O(1) 定位条目。</p>
 *
 * <p>缓存条目按访问时间过期并按总字节数淘汰；被淘汰的文件立即尽力删除，
 * 删除失败（Windows 上仍被读取句柄占用）的残留由后续扫描按修改时间兜底清理。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class ReaderComicArchiveCache {

    private static final String SEGMENT = "reader-comic";
    private static final Duration ENTRY_TTL = Duration.ofMinutes(30);
    private static final long MAX_CACHED_BYTES = 2L * 1024 * 1024 * 1024;
    private static final long SWEEP_INTERVAL_MILLIS = Duration.ofMinutes(10).toMillis();
    private static final long SWEEP_AGE_MILLIS = Duration.ofHours(1).toMillis();
    /** Windows 压缩工具产出的中文条目名多为 GBK；GB18030 是其超集。 */
    private static final Charset GB18030 = Charset.forName("GB18030");

    private final FileQueryService fileQueryService;
    private final ReaderArchiveSafetyPolicy archiveSafetyPolicy;
    private final TempStagingPort tempStagingPort;

    private final Cache<CacheKey, Path> archives;

    private final AtomicLong lastSweepAt = new AtomicLong(0L);

    public ReaderComicArchiveCache(
            FileQueryService fileQueryService,
            ReaderArchiveSafetyPolicy archiveSafetyPolicy,
            TempStagingPort tempStagingPort
    ) {
        this.fileQueryService = fileQueryService;
        this.archiveSafetyPolicy = archiveSafetyPolicy;
        this.tempStagingPort = tempStagingPort;
        this.archives = Caffeine.newBuilder()
                .maximumWeight(MAX_CACHED_BYTES)
                .weigher((CacheKey key, Path path) -> (int) Math.min(Integer.MAX_VALUE, key.sizeBytes()))
                .expireAfterAccess(ENTRY_TTL)
                .removalListener((CacheKey key, Path path, RemovalCause cause) ->
                        tempStagingPort.deleteQuietly(path))
                .build();
    }

    /**
     * 获取归档的本地路径；未缓存或缓存文件已丢失时重新暂存。
     *
     * @param ownerUserId 文件所有者
     * @param fileNodeId 文件节点
     * @param sizeBytes 文件字节数
     * @param updatedAtMillis 文件更新时间毫秒值，用于让替换过的内容重新暂存
     * @return 本地归档路径
     */
    public Path acquire(UUID ownerUserId, UUID fileNodeId, long sizeBytes, long updatedAtMillis) {
        if (sizeBytes <= 0) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "漫画来源文件不存在");
        }
        sweepExpiredFiles();
        CacheKey key = new CacheKey(fileNodeId, sizeBytes, updatedAtMillis);
        Path path = archives.get(key, ignored -> stage(ownerUserId, fileNodeId, sizeBytes));
        if (path == null || !Files.isRegularFile(path)) {
            // 淘汰或外部清理可能只删掉了文件而条目尚未失效；重建一次而不是让本次读页失败。
            archives.invalidate(key);
            path = archives.get(key, ignored -> stage(ownerUserId, fileNodeId, sizeBytes));
        }
        touch(path);
        return path;
    }

    /**
     * 打开缓存归档；调用方必须关闭返回对象，ZipFile 句柄不会跨请求复用。
     *
     * @param ownerUserId 文件所有者
     * @param fileNodeId 文件节点
     * @param sizeBytes 文件字节数
     * @param updatedAtMillis 文件更新时间毫秒值
     * @return 可关闭的归档视图
     */
    public CachedArchive open(UUID ownerUserId, UUID fileNodeId, long sizeBytes, long updatedAtMillis) {
        Path path = acquire(ownerUserId, fileNodeId, sizeBytes, updatedAtMillis);
        return new CachedArchive(openArchive(path));
    }

    /**
     * 先按 UTF-8 解码条目名，失败后回退 GB18030。
     */
    private ZipFile openArchive(Path archivePath) {
        try {
            return new ZipFile(archivePath.toFile(), StandardCharsets.UTF_8);
        } catch (IOException | IllegalArgumentException utf8Failure) {
            log.debug("漫画归档按 UTF-8 打开失败，回退 GB18030: errorType={}",
                    utf8Failure.getClass().getSimpleName());
        }
        try {
            return new ZipFile(archivePath.toFile(), GB18030);
        } catch (IOException | IllegalArgumentException exception) {
            log.warn("漫画归档无法打开: errorType={}", exception.getClass().getSimpleName());
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "漫画压缩包无法读取");
        }
    }

    private Path stage(UUID ownerUserId, UUID fileNodeId, long sizeBytes) {
        Path tempFile = tempStagingPort.createTempFile(SEGMENT, "comic-", ".zip");
        try (FileContentStream content = fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId)) {
            archiveSafetyPolicy.copyArchive(content.inputStream(), tempFile, sizeBytes);
        } catch (BusinessException exception) {
            tempStagingPort.deleteQuietly(tempFile);
            throw exception;
        } catch (IOException exception) {
            tempStagingPort.deleteQuietly(tempFile);
            log.warn("漫画归档暂存失败: fileNodeId={}, errorType={}",
                    fileNodeId, exception.getClass().getSimpleName());
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "漫画归档读取失败");
        } catch (RuntimeException exception) {
            tempStagingPort.deleteQuietly(tempFile);
            throw exception;
        }
        return tempFile;
    }

    private void touch(Path path) {
        try {
            Files.setLastModifiedTime(path, FileTime.fromMillis(System.currentTimeMillis()));
        } catch (IOException exception) {
            log.debug("刷新漫画归档缓存访问时间失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    /**
     * 周期清理暂存目录中长时间未访问的残留文件，覆盖淘汰时删除失败的场景。
     */
    private void sweepExpiredFiles() {
        long now = System.currentTimeMillis();
        long last = lastSweepAt.get();
        if (now - last < SWEEP_INTERVAL_MILLIS || !lastSweepAt.compareAndSet(last, now)) {
            return;
        }
        Path directory = tempStagingPort.ensureDirectory(SEGMENT);
        try (var files = Files.list(directory)) {
            files.filter(Files::isRegularFile)
                    .filter(file -> isExpired(file, now))
                    .forEach(tempStagingPort::deleteQuietly);
        } catch (IOException exception) {
            log.warn("清理漫画归档缓存目录失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    private boolean isExpired(Path file, long now) {
        try {
            return now - Files.getLastModifiedTime(file).toMillis() > SWEEP_AGE_MILLIS;
        } catch (IOException exception) {
            return false;
        }
    }

    /**
     * 一次请求内的归档视图：ZipFile 是线程安全的读取入口，关闭责任在调用方。
     */
    public static final class CachedArchive implements AutoCloseable {

        private final ZipFile zipFile;

        private CachedArchive(ZipFile zipFile) {
            this.zipFile = zipFile;
        }

        /**
         * 按精确路径定位条目；带序号顺序扫描的 ZIP/CBZ 不做大小写回退，
         * EPUB 页（entryIndex 为空）允许忽略大小写。
         */
        public ZipEntry findEntry(String sourcePath, Integer entryIndex) {
            if (sourcePath == null || sourcePath.isBlank()) {
                return null;
            }
            ZipEntry exact = zipFile.getEntry(sourcePath);
            if (exact != null) {
                return exact.isDirectory() ? null : exact;
            }
            if (entryIndex != null) {
                return null;
            }
            Enumeration<? extends ZipEntry> entries = zipFile.entries();
            while (entries.hasMoreElements()) {
                ZipEntry candidate = entries.nextElement();
                if (!candidate.isDirectory() && candidate.getName().equalsIgnoreCase(sourcePath)) {
                    return candidate;
                }
            }
            return null;
        }

        /**
         * 打开条目内容流。
         */
        public InputStream openEntry(ZipEntry entry) throws IOException {
            return zipFile.getInputStream(entry);
        }

        @Override
        public void close() throws IOException {
            zipFile.close();
        }
    }

    /**
     * 缓存键：节点标识、字节数与更新时间共同定位一份不可变归档内容。
     */
    private record CacheKey(UUID fileNodeId, long sizeBytes, long updatedAtMillis) {
    }
}
