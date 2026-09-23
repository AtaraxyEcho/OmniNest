package com.omninest.modules.music.service;

import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileQueryService;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Iterator;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.coobird.thumbnailator.Thumbnails;
import org.springframework.stereotype.Service;

/**
 * 音乐封面缩略图的按需派生服务。
 *
 * <p>列表与封面格子只需要小尺寸图像，直接回源原图会放大传输与解码开销。首次请求
 * 缩略图时把原图缩到 300px 存为派生资产，之后按同一对象键复用。源图超出受理上限、
 * 编码不受支持、并发派生达到上限或生成失败时返回空，由调用方回退原图，展示链路不会
 * 因派生失败而缺图。</p>
 *
 * <p>派生键以封面文件标识作资源标识（{@code MUSIC_COVER/{coverFileId}/THUMBNAIL}），
 * 与上传、刮削写入原图时各自随机的资源标识解耦，因此两条写入路径的封面都能命中。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicCoverThumbnailService {

    private static final int THUMBNAIL_SIZE_PX = 300;
    private static final double OUTPUT_QUALITY = 0.82;
    private static final String RESOURCE_TYPE = "MUSIC_COVER";
    private static final String ASSET_TYPE = "THUMBNAIL";
    private static final String FILE_NAME = "cover_300.jpg";
    /** 统一输出 JPEG：300px 小图下体积远小于 PNG，透明通道压到黑底与深色主题一致。 */
    private static final String OUTPUT_FORMAT = "jpg";
    private static final String OUTPUT_MIME_TYPE = "image/jpeg";

    /**
     * 受理缩略图派生的原图字节上限。与上传入口一致：更大的原图只可能来自刮削或
     * 历史数据，为其整段解码换一张 300px 小图不划算，直接回退原图。
     */
    private static final long MAX_SOURCE_BYTES = 8L * 1024 * 1024;

    /** 解码前的像素总量上限，拦截字节数合规但尺寸巨大的图像占满堆内存。 */
    private static final long MAX_SOURCE_PIXELS = 25_000_000L;

    /** 同一时刻允许解码的封面数：冷启动首屏会一次请求几十张不同缩略图，超限时先回原图。 */
    private static final int MAX_CONCURRENT_DERIVATIONS = 4;

    private static final Duration GENERATION_WAIT = Duration.ofSeconds(60);
    private static final Path PROCESSING_ROOT = Path.of(
            System.getProperty("java.io.tmpdir"), "omninest-music-cover");

    private final DerivedAssetStorageService derivedAssetStorageService;
    private final FileQueryService fileQueryService;

    /** 同一封面的并发首请求只派生一次，其余请求等待结果后复用同一对象键。 */
    private final ConcurrentHashMap<UUID, CompletableFuture<UUID>> inFlight = new ConcurrentHashMap<>();
    private final Semaphore derivationPermits = new Semaphore(MAX_CONCURRENT_DERIVATIONS);

    /**
     * 查询封面缩略图的派生文件节点，缺失时按需生成。
     *
     * @param ownerUserId 所有者用户 ID
     * @param coverFileId 封面原图文件节点 ID
     * @param sourceSizeBytes 封面原图字节数，用于跳过不受理的大图
     * @return 缩略图文件节点 ID；原图不受理、并发达到上限或生成失败时返回空
     */
    public Optional<UUID> ensureThumbnail(UUID ownerUserId, UUID coverFileId, long sourceSizeBytes) {
        Optional<UUID> stored = findStored(ownerUserId, coverFileId);
        if (stored.isPresent()) {
            return stored;
        }
        if (sourceSizeBytes > MAX_SOURCE_BYTES) {
            return Optional.empty();
        }
        CompletableFuture<UUID> future = new CompletableFuture<>();
        CompletableFuture<UUID> running = inFlight.putIfAbsent(coverFileId, future);
        if (running != null) {
            return awaitRunning(running, coverFileId);
        }
        UUID generated = null;
        try {
            generated = generate(ownerUserId, coverFileId);
        } finally {
            inFlight.remove(coverFileId, future);
            future.complete(generated);
        }
        return Optional.ofNullable(generated);
    }

    private Optional<UUID> findStored(UUID ownerUserId, UUID coverFileId) {
        return derivedAssetStorageService.findStoredFileNodeId(
                ownerUserId,
                RESOURCE_TYPE,
                coverFileId,
                ASSET_TYPE,
                FILE_NAME
        );
    }

    private Optional<UUID> awaitRunning(CompletableFuture<UUID> running, UUID coverFileId) {
        try {
            return Optional.ofNullable(running.get(GENERATION_WAIT.toSeconds(), TimeUnit.SECONDS));
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            return Optional.empty();
        } catch (TimeoutException | ExecutionException ex) {
            log.warn("等待封面缩略图生成失败: coverFileId={}, errorType={}",
                    coverFileId, ex.getClass().getSimpleName());
            return Optional.empty();
        }
    }

    private UUID generate(UUID ownerUserId, UUID coverFileId) {
        if (!derivationPermits.tryAcquire()) {
            log.info("封面缩略图并发派生已达上限，本次回退原图: coverFileId={}", coverFileId);
            return null;
        }
        Path source = null;
        Path output = null;
        try {
            source = stageSource(ownerUserId, coverFileId);
            if (source == null || !isWithinDecodeLimits(source)) {
                return null;
            }
            Files.createDirectories(PROCESSING_ROOT);
            output = Files.createTempFile(PROCESSING_ROOT, "thumbnail-", "." + OUTPUT_FORMAT);
            Thumbnails.of(source.toFile())
                    .size(THUMBNAIL_SIZE_PX, THUMBNAIL_SIZE_PX)
                    .keepAspectRatio(true)
                    .imageType(BufferedImage.TYPE_INT_RGB)
                    .outputFormat(OUTPUT_FORMAT)
                    .outputQuality(OUTPUT_QUALITY)
                    .toFile(output.toFile());
            return derivedAssetStorageService.store(
                    ownerUserId,
                    RESOURCE_TYPE,
                    coverFileId,
                    ASSET_TYPE,
                    FILE_NAME,
                    OUTPUT_MIME_TYPE,
                    output
            );
        } catch (IOException | RuntimeException ex) {
            log.warn("封面缩略图生成失败: coverFileId={}, errorType={}",
                    coverFileId, ex.getClass().getSimpleName());
            return null;
        } finally {
            deleteQuietly(source);
            deleteQuietly(output);
            derivationPermits.release();
        }
    }

    /**
     * 把原图落到临时目录，超过受理上限或读不到内容时返回空。
     */
    private Path stageSource(UUID ownerUserId, UUID coverFileId) throws IOException {
        Files.createDirectories(PROCESSING_ROOT);
        Path target = Files.createTempFile(PROCESSING_ROOT, "source-", ".img");
        try (FileContentStream content = fileQueryService.openReadableFileContent(ownerUserId, coverFileId);
             InputStream input = content.inputStream();
             OutputStream output = Files.newOutputStream(target)) {
            long copied = copyBounded(input, output);
            if (copied <= 0) {
                deleteQuietly(target);
                return null;
            }
            return target;
        } catch (IOException | RuntimeException ex) {
            deleteQuietly(target);
            throw ex;
        }
    }

    private long copyBounded(InputStream input, OutputStream output) throws IOException {
        byte[] buffer = new byte[8192];
        long copied = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            copied += read;
            if (copied > MAX_SOURCE_BYTES) {
                return -1;
            }
            output.write(buffer, 0, read);
        }
        return copied;
    }

    /**
     * 仅读图像头信息校验格式与像素总量，不做完整解码。
     */
    private boolean isWithinDecodeLimits(Path source) throws IOException {
        try (ImageInputStream imageInput = ImageIO.createImageInputStream(source.toFile())) {
            if (imageInput == null) {
                return false;
            }
            Iterator<ImageReader> readers = ImageIO.getImageReaders(imageInput);
            if (!readers.hasNext()) {
                return false;
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(imageInput, true, true);
                long pixels = Math.multiplyExact((long) reader.getWidth(0), (long) reader.getHeight(0));
                return pixels <= MAX_SOURCE_PIXELS;
            } finally {
                reader.dispose();
            }
        } catch (IOException | RuntimeException ex) {
            log.warn("封面缩略图源图检查失败: errorType={}", ex.getClass().getSimpleName());
            return false;
        }
    }

    private void deleteQuietly(Path file) {
        if (file == null) {
            return;
        }
        try {
            Files.deleteIfExists(file);
        } catch (IOException ex) {
            log.debug("封面缩略图临时文件清理失败: errorType={}", ex.getClass().getSimpleName());
        }
    }
}
