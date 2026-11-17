package com.omninest.modules.reader.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;

import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPage;
import com.omninest.modules.reader.domain.ReaderPageAsset;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageAssetRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.service.ReaderArchiveSafetyPolicy.ArchiveReadSession;
import com.omninest.modules.reader.service.ReaderArchiveSafetyPolicy.EntryReadGuard;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Collection;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.zip.ZipEntry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 管理漫画页面派生资源及页面流式读取。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ComicPageAssetService {


    private final MediaProcessingLimitsProperties processingLimits;
    private final ReaderItemRepository itemRepository;
    private final ReaderItemSourceRepository sourceRepository;
    private final ReaderPageRepository pageRepository;
    private final ReaderPageAssetRepository pageAssetRepository;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final FileQueryService fileQueryService;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final ReaderArchiveSafetyPolicy archiveSafetyPolicy;
    private final ReaderComicArchiveCache archiveCache;

    PageDownloadDescriptor preparePageImageDownload(UUID ownerUserId, UUID pageId) {
        ReaderPage page = pageRepository.findById(pageId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "页面不存在"));
        ReaderItemSource source = sourceRepository.findById(page.getSourceId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "来源文件不存在"));
        ReaderItem item = itemRepository.findById(source.getReaderItemId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "条目不存在"));
        // 共享空间的漫画对空间内其他用户同样可见：清单侧走的是 requireItem（含空间可见性），
        // 页面图若还按"创建者相等"放行，就是列表能翻、每一张图都 403。
        // 创建者本人不必再查一次空间权限：页面图是按页请求的热路径，多数漫画只有上传者。
        FileDescriptor sharedSourceNode = null;
        if (!item.getOwnerUserId().equals(ownerUserId)) {
            if (source.getFileNodeId() == null) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "无权访问此页面");
            }
            sharedSourceNode = fileLifecycleGuard.requireReadable(ownerUserId, source.getFileNodeId());
            if (!"FILE".equals(sharedSourceNode.nodeType())) {
                throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在");
            }
        }

        ReaderPageAsset asset = findPageAsset(pageId, item.getManifestVersion());
        if (asset != null) {
            validatePageImageSize(asset.getByteSize());
            // 派生页资产挂在条目所有者名下：读取用节点的真实所有者，请求者只用于上面的授权判定。
            return new PageDownloadDescriptor(
                    item.getOwnerUserId(),
                    null,
                    asset.getId(),
                    null,
                    null,
                    asset.getMimeType(),
                    asset.getByteSize(),
                    false,
                    0L,
                    0L
            );
        }

        FileDescriptor fileNode = sharedSourceNode != null
                ? sharedSourceNode
                : loadFileNode(source.getFileNodeId());
        archiveSafetyPolicy.validateArchiveSize(fileNode.sizeBytes());
        long pageSize = page.getByteSize() == null || page.getByteSize() <= 0
                ? -1L
                : page.getByteSize();
        if (pageSize >= 0) {
            validatePageImageSize(pageSize);
        }
        String mimeType = page.getMimeType() != null
                ? page.getMimeType()
                : detectMimeType(page.getSourcePath());
        return new PageDownloadDescriptor(
                fileNode.ownerUserId(),
                fileNode.id(),
                null,
                page.getSourcePath(),
                page.getEntryIndex(),
                mimeType,
                pageSize,
                true,
                fileNode.sizeBytes(),
                fileNode.updatedAt() == null ? 0L : fileNode.updatedAt().toEpochMilli()
        );
    }

    private FileDescriptor loadFileNode(UUID fileNodeId) {
        FileDescriptor fileNode = fileMetadataQueryService.findById(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (fileNode.deleted() || !"FILE".equals(fileNode.nodeType())) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在");
        }
        return fileNode;
    }

    void streamPageImage(
            PageDownloadDescriptor descriptor,
            OutputStream outputStream
    ) throws IOException {
        if (!descriptor.sourceArchive()) {
            ReaderPageAsset asset = pageAssetRepository.findById(descriptor.derivedAssetId())
                    .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "漫画页面资源不存在"));
            try (FileContentStream content = fileQueryService.openOwnedFileContent(
                    descriptor.ownerUserId(), asset.getFileNodeId());
                 InputStream inputStream = content.inputStream()) {
                copyBounded(inputStream, outputStream, processingLimits.getMaxComicPageImageBytes());
            }
            return;
        }
        streamPageImageFromSourceArchive(descriptor, outputStream);
    }

    void deletePageAssets(UUID sourceId) {
        deletePageAssets(pageAssetRepository.findBySourceId(sourceId));
    }

    /**
     * 同步删除指定页面资产。物理对象删除失败时不会删除数据库记录。
     *
     * @param assets 页面资产集合
     */
    void deletePageAssets(Collection<ReaderPageAsset> assets) {
        if (assets == null || assets.isEmpty()) {
            return;
        }
        for (ReaderPageAsset asset : assets) {
            derivedAssetStorageService.deleteDerivedFileNode(asset.getFileNodeId());
        }
        pageAssetRepository.deleteAllById(assets.stream().map(ReaderPageAsset::getId).toList());
    }

    /**
     * 在来源事务提交后清理旧页面资产。清理失败时保留元数据，便于后续重试。
     *
     * @param assets 已经脱离当前清单的旧页面资产
     */
    void cleanupPageAssetsAfterCommit(Collection<ReaderPageAsset> assets) {
        if (assets == null || assets.isEmpty()) {
            return;
        }
        RuntimeException firstFailure = null;
        for (ReaderPageAsset asset : assets) {
            try {
                derivedAssetStorageService.deleteDerivedFileNode(asset.getFileNodeId());
            } catch (RuntimeException exception) {
                if (firstFailure == null) {
                    firstFailure = exception;
                }
                log.warn("漫画旧页面对象清理失败，将保留资产记录: assetId={}, errorType={}",
                        asset.getId(), exception.getClass().getSimpleName());
            }
        }
        if (firstFailure == null) {
            pageAssetRepository.deleteAllById(assets.stream().map(ReaderPageAsset::getId).toList());
        } else {
            log.warn("漫画旧页面资产未完成清理: assetCount={}, errorType={}",
                    assets.size(), firstFailure.getClass().getSimpleName());
        }
    }

    /**
     * 查询来源下的页面资产快照。
     *
     * @param sourceId 来源 ID
     * @return 页面资产快照
     */
    List<ReaderPageAsset> findPageAssets(UUID sourceId) {
        return List.copyOf(pageAssetRepository.findBySourceId(sourceId));
    }

    /**
     * 从图片头部字节嗅探宽高。
     *
     * <p>漫画的页面图来源五花八门：压制工具产出的 WebP 多数是 {@code VP8L}（无损）或
     * {@code VP8X}（扩展），只认最老的 {@code VP8 } 有损块会把它们一律报成 0x0；
     * 宽高缺失时清单里的页没有尺寸，滚动侧的高度索引与装页都只能靠猜。
     * JPEG 还要跳过段前的连续 {@code 0xFF} 填充字节，否则标记解析直接跑偏。
     *
     * @param header 图片头部字节（调用方按上限截断读取）
     * @return 长度为 2 的宽高数组；识别不出时返回 {0, 0}
     */
    static int[] readImageDimensions(byte[] header) {
        if (header == null || header.length < 10) {
            return new int[]{0, 0};
        }

        if (header.length >= 24 && header[0] == (byte) 0x89 && header[1] == (byte) 0x50) {
            int width = ((header[16] & 0xFF) << 24) | ((header[17] & 0xFF) << 16)
                    | ((header[18] & 0xFF) << 8) | (header[19] & 0xFF);
            int height = ((header[20] & 0xFF) << 24) | ((header[21] & 0xFF) << 16)
                    | ((header[22] & 0xFF) << 8) | (header[23] & 0xFF);
            return new int[]{width, height};
        }

        if (header[0] == 'G' && header[1] == 'I' && header[2] == 'F') {
            int width = (header[6] & 0xFF) | ((header[7] & 0xFF) << 8);
            int height = (header[8] & 0xFF) | ((header[9] & 0xFF) << 8);
            return new int[]{width, height};
        }

        if (header.length >= 26 && header[0] == 'B' && header[1] == 'M') {
            int width = readLittleEndian32(header, 18);
            int height = readLittleEndian32(header, 22);
            return new int[]{Math.abs(width), Math.abs(height)};
        }

        if (header[0] == (byte) 0xFF && header[1] == (byte) 0xD8) {
            return readJpegDimensions(header);
        }

        if (header.length >= 30 && header[0] == 'R' && header[8] == 'W'
                && header[12] == 'V' && header[13] == 'P' && header[14] == '8') {
            byte chunk = header[15];
            if (chunk == ' ') {
                int width = ((header[26] & 0xFF) | ((header[27] & 0xFF) << 8)) & 0x3FFF;
                int height = ((header[28] & 0xFF) | ((header[29] & 0xFF) << 8)) & 0x3FFF;
                return new int[]{width, height};
            }
            if (chunk == 'L' && header.length >= 25) {
                int b0 = header[21] & 0xFF;
                int b1 = header[22] & 0xFF;
                int b2 = header[23] & 0xFF;
                int b3 = header[24] & 0xFF;
                int width = 1 + (b0 | ((b1 & 0x3F) << 8));
                int height = 1 + (((b1 & 0xC0) >> 6) | (b2 << 2) | ((b3 & 0x0F) << 10));
                return new int[]{width, height};
            }
            if (chunk == 'X') {
                int width = 1 + (header[24] & 0xFF) + ((header[25] & 0xFF) << 8)
                        + ((header[26] & 0xFF) << 16);
                int height = 1 + (header[27] & 0xFF) + ((header[28] & 0xFF) << 8)
                        + ((header[29] & 0xFF) << 16);
                return new int[]{width, height};
            }
        }

        return new int[]{0, 0};
    }

    /**
     * 扫描 JPEG 段找 SOF 帧头。
     *
     * <p>段标记前允许任意个 {@code 0xFF} 填充字节（JFIF 与相机产出都常见），
     * 把它们当成标记本身会把后两字节读成"长度"，游标随即跑偏并扫不到 SOF。
     * 扩展 SOF（0xC1/0xC2 与 0xC5-0xCF 里的差分/渐进变体）都要认，只认 0xC0
     * 会让渐进 JPEG 报成无尺寸。
     *
     * @param header 图片头部字节
     * @return 宽高；扫完仍未命中时返回 {0, 0}
     */
    private static int[] readJpegDimensions(byte[] header) {
        int index = 2;
        while (index + 4 < header.length) {
            if (header[index] != (byte) 0xFF) {
                index++;
                continue;
            }
            while (index < header.length && header[index] == (byte) 0xFF) {
                index++;
            }
            if (index >= header.length) {
                break;
            }
            int marker = header[index] & 0xFF;
            index++;
            if (marker == 0x00 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
                continue;
            }
            if (index + 2 > header.length) {
                break;
            }
            int length = ((header[index] & 0xFF) << 8) | (header[index + 1] & 0xFF);
            if (length < 2) {
                break;
            }
            if (isStartOfFrame(marker)) {
                if (index + 7 <= header.length) {
                    int height = ((header[index + 3] & 0xFF) << 8) | (header[index + 4] & 0xFF);
                    int width = ((header[index + 5] & 0xFF) << 8) | (header[index + 6] & 0xFF);
                    if (width > 0 && height > 0) {
                        return new int[]{width, height};
                    }
                }
                break;
            }
            index += length;
        }
        return new int[]{0, 0};
    }

    private static boolean isStartOfFrame(int marker) {
        return (marker >= 0xC0 && marker <= 0xC3)
                || (marker >= 0xC5 && marker <= 0xC7)
                || (marker >= 0xC9 && marker <= 0xCB)
                || (marker >= 0xCD && marker <= 0xCF);
    }

    private static int readLittleEndian32(byte[] header, int offset) {
        return (header[offset] & 0xFF) | ((header[offset + 1] & 0xFF) << 8)
                | ((header[offset + 2] & 0xFF) << 16) | ((header[offset + 3] & 0xFF) << 24);
    }

    private ReaderPageAsset findPageAsset(UUID pageId, int manifestVersion) {
        return pageAssetRepository.findByPageIdAndManifestVersion(pageId, manifestVersion)
                .or(() -> pageAssetRepository.findFirstByPageIdOrderByManifestVersionDesc(pageId))
                .orElse(null);
    }

    /**
     * 从本地缓存归档按中央目录直接定位目标页，避免每次请求顺序解压前序条目。
     */
    private void streamPageImageFromSourceArchive(
            PageDownloadDescriptor descriptor,
            OutputStream outputStream
    ) throws IOException {
        try (ReaderComicArchiveCache.CachedArchive archive = archiveCache.open(
                descriptor.ownerUserId(),
                descriptor.sourceFileNodeId(),
                descriptor.sourceSizeBytes(),
                descriptor.sourceUpdatedAtMillis()
        )) {
            ZipEntry entry = archive.findEntry(descriptor.sourcePath(), descriptor.entryIndex());
            if (entry == null) {
                throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "漫画页面来源条目不存在");
            }
            ArchiveReadSession session = archiveSafetyPolicy.newReadSession();
            EntryReadGuard guard = session.beginEntry(
                    entry,
                    processingLimits.getMaxComicPageImageBytes()
            );
            try (InputStream input = archive.openEntry(entry)) {
                copyArchiveEntry(input, outputStream, guard, processingLimits.getMaxComicPageImageBytes());
            }
            guard.complete(entry);
        }
    }

    private void copyArchiveEntry(
            InputStream input,
            OutputStream output,
            EntryReadGuard guard,
            long maxBytes
    ) throws IOException {
        byte[] buffer = new byte[8192];
        long totalRead = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            guard.recordBytes(read);
            totalRead += read;
            if (totalRead > maxBytes) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "图片过大");
            }
            output.write(buffer, 0, read);
        }
    }

    private void copyBounded(
            InputStream input,
            OutputStream output,
            long maxBytes
    ) throws IOException {
        byte[] buffer = new byte[8192];
        long totalRead = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            totalRead += read;
            if (totalRead > maxBytes) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "图片过大");
            }
            output.write(buffer, 0, read);
        }
    }

    private void validatePageImageSize(long sizeBytes) {
        if (sizeBytes > processingLimits.getMaxComicPageImageBytes()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "图片过大");
        }
    }

    static String detectMimeType(String path) {
        if (path == null) {
            return "application/octet-stream";
        }
        String lower = path.toLowerCase(Locale.ROOT);
        if (lower.endsWith(".png")) {
            return "image/png";
        }
        if (lower.endsWith(".gif")) {
            return "image/gif";
        }
        if (lower.endsWith(".webp")) {
            return "image/webp";
        }
        if (lower.endsWith(".bmp")) {
            return "image/bmp";
        }
        if (lower.endsWith(".tiff") || lower.endsWith(".tif")) {
            return "image/tiff";
        }
        if (lower.endsWith(".avif")) {
            return "image/avif";
        }
        return "image/jpeg";
    }

    /**
     * 漫画页面流式下载描述。
     *
     * @param ownerUserId 页面所有者用户 ID
     * @param sourceFileNodeId 来源文件节点 ID
     * @param derivedAssetId 已物化的遗留页面资产 ID
     * @param sourcePath 来源压缩包内路径
     * @param entryIndex 来源压缩包内条目序号
     * @param mimeType 图片媒体类型
     * @param sizeBytes 图片字节数，未知时为 -1
     * @param sourceArchive 是否需要从来源压缩包读取
     * @param sourceSizeBytes 来源压缩包字节数，用于本地归档缓存定位
     * @param sourceUpdatedAtMillis 来源压缩包更新时间，用于让替换后的内容重新暂存
     * @author OmniNest
     */
    public record PageDownloadDescriptor(
            UUID ownerUserId,
            UUID sourceFileNodeId,
            UUID derivedAssetId,
            String sourcePath,
            Integer entryIndex,
            String mimeType,
            long sizeBytes,
            boolean sourceArchive,
            long sourceSizeBytes,
            long sourceUpdatedAtMillis
    ) {
    }
}
