package com.omninest.modules.reader.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
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
import java.util.zip.ZipInputStream;
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
    private final FileMetadataQueryService fileMetadataQueryService;
    private final FileQueryService fileQueryService;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final ReaderArchiveSafetyPolicy archiveSafetyPolicy;

    PageDownloadDescriptor preparePageImageDownload(UUID ownerUserId, UUID pageId) {
        ReaderPage page = pageRepository.findById(pageId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "页面不存在"));
        ReaderItemSource source = sourceRepository.findById(page.getSourceId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "来源文件不存在"));
        ReaderItem item = itemRepository.findById(source.getReaderItemId())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "条目不存在"));
        if (!item.getOwnerUserId().equals(ownerUserId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权访问此页面");
        }

        ReaderPageAsset asset = findPageAsset(pageId, item.getManifestVersion());
        if (asset != null) {
            validatePageImageSize(asset.getByteSize());
            return new PageDownloadDescriptor(
                    ownerUserId,
                    null,
                    asset.getId(),
                    null,
                    null,
                    asset.getMimeType(),
                    asset.getByteSize(),
                    false
            );
        }

        FileDescriptor fileNode = loadFileNode(source.getFileNodeId());
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
                ownerUserId,
                fileNode.id(),
                null,
                page.getSourcePath(),
                page.getEntryIndex(),
                mimeType,
                pageSize,
                true
        );
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

    static int[] readImageDimensions(byte[] header) {
        if (header == null || header.length < 24) {
            return new int[]{0, 0};
        }

        if (header[0] == (byte) 0x89 && header[1] == (byte) 0x50) {
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

        if (header[0] == (byte) 0xFF && header[1] == (byte) 0xD8) {
            int index = 2;
            while (index < header.length - 9) {
                if (header[index] != (byte) 0xFF) {
                    index++;
                    continue;
                }
                int marker = header[index + 1] & 0xFF;
                if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
                    int height = ((header[index + 5] & 0xFF) << 8) | (header[index + 6] & 0xFF);
                    int width = ((header[index + 7] & 0xFF) << 8) | (header[index + 8] & 0xFF);
                    return new int[]{width, height};
                }
                if (marker >= 0xD0 && marker <= 0xD9) {
                    index += 2;
                    continue;
                }
                int length = ((header[index + 2] & 0xFF) << 8) | (header[index + 3] & 0xFF);
                index += 2 + length;
            }
        }

        if (header.length >= 30 && header[0] == 'R' && header[8] == 'W'
                && header[12] == 'V' && header[13] == 'P' && header[15] == ' ') {
            int width = ((header[26] & 0xFF) | ((header[27] & 0xFF) << 8)) & 0x3FFF;
            int height = ((header[28] & 0xFF) | ((header[29] & 0xFF) << 8)) & 0x3FFF;
            return new int[]{width, height};
        }

        return new int[]{0, 0};
    }

    private ReaderPageAsset findPageAsset(UUID pageId, int manifestVersion) {
        return pageAssetRepository.findByPageIdAndManifestVersion(pageId, manifestVersion)
                .or(() -> pageAssetRepository.findFirstByPageIdOrderByManifestVersionDesc(pageId))
                .orElse(null);
    }

    private void streamPageImageFromSourceArchive(
            PageDownloadDescriptor descriptor,
            OutputStream outputStream
    ) throws IOException {
        ArchiveReadSession session = archiveSafetyPolicy.newReadSession();
        try (FileContentStream content = fileQueryService.openOwnedFileContent(
                descriptor.ownerUserId(), descriptor.sourceFileNodeId());
             ZipInputStream input = new ZipInputStream(content.inputStream())) {
            ZipEntry entry;
            int currentEntryIndex = -1;
            while ((entry = input.getNextEntry()) != null) {
                currentEntryIndex++;
                boolean targetEntry = entry.getName().equals(descriptor.sourcePath())
                        && (descriptor.entryIndex() == null || currentEntryIndex == descriptor.entryIndex());
                EntryReadGuard guard = session.beginEntry(
                        entry,
                        targetEntry ? processingLimits.getMaxComicPageImageBytes() : Long.MAX_VALUE
                );
                if (entry.isDirectory()) {
                    guard.complete(entry);
                    continue;
                }
                if (targetEntry) {
                    copyArchiveEntry(input, outputStream, guard, processingLimits.getMaxComicPageImageBytes());
                    guard.complete(entry);
                    return;
                }
                drainArchiveEntry(input, guard);
                guard.complete(entry);
            }
        }
        throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "漫画页面来源条目不存在");
    }

    private FileDescriptor loadFileNode(UUID fileNodeId) {
        FileDescriptor fileNode = fileMetadataQueryService.findById(fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        if (fileNode.deleted() || !"FILE".equals(fileNode.nodeType())) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在");
        }
        return fileNode;
    }

    private void copyArchiveEntry(
            ZipInputStream input,
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

    private void drainArchiveEntry(ZipInputStream input, EntryReadGuard guard) throws IOException {
        byte[] buffer = new byte[8192];
        int read;
        while ((read = input.read(buffer)) != -1) {
            guard.recordBytes(read);
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
            boolean sourceArchive
    ) {
    }
}
