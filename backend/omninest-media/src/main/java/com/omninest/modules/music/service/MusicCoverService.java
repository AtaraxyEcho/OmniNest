package com.omninest.modules.music.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.music.dto.MusicDtos.MusicCoverUploadDto;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PushbackInputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

/**
 * 负责音乐封面的校验、存储、所有权检查和流式读取。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicCoverService {


    /**
     * 流式读取防御上限。仅作恶意/异常资源护栏：刮削下载与派生存储
     * 不经过上传入口的 8MB 校验，正常封面远小于此值。
     */


    private final MediaProcessingLimitsProperties processingLimits;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final FileQueryService fileQueryService;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final MusicCoverThumbnailService coverThumbnailService;

    /**
     * 已完成权限校验的封面流式读取描述。
     *
     * @param ownerUserId 所属用户标识
     * @param fileId 封面文件标识
     * @param contentType 响应 MIME 类型
     * @param sizeBytes 响应字节数
     */
    public record CoverStreamDescriptor(
            UUID ownerUserId,
            UUID fileId,
            String contentType,
            long sizeBytes
    ) {
    }

    /**
     * 校验封面可被当前用户读取并返回流式描述。
     *
     * @param ownerUserId 所属用户标识
     * @param fileId 封面文件标识
     * @return 流式读取描述
     */
    public CoverStreamDescriptor prepareCoverStream(UUID ownerUserId, UUID fileId) {
        fileQueryService.validateOwnedImage(ownerUserId, fileId);
        FileDescriptor node = fileMetadataQueryService.findActiveById(fileId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "封面文件不存在"));
        if (!NodeType.FILE.getValue().equals(node.nodeType())
                || node.sizeBytes() > processingLimits.getMaxStreamCoverBytes()) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "封面文件不存在");
        }
        String contentType = node.mimeType();
        if (contentType == null || contentType.isBlank()) {
            contentType = "image/jpeg";
        }
        return new CoverStreamDescriptor(ownerUserId, fileId, contentType, node.sizeBytes());
    }

    /**
     * 缩略图响应的可缓存程度，决定客户端多久后会再看到真正的缩略图。
     */
    public enum ThumbnailFreshness {
        /** 派生缩略图：路径稳定且内容不变，可长期缓存。 */
        DERIVED,
        /** 回退原图且这张封面不会再有缩略图：按原图节奏缓存，避免反复下载大文件。 */
        STABLE_FALLBACK,
        /** 回退原图且值得重试（并发繁忙或临时失败）：只短期缓存。 */
        RETRY_SOON
    }

    /**
     * 缩略图流式读取结果。
     *
     * @param descriptor 实际写出的内容描述
     * @param freshness 响应的可缓存程度
     */
    public record ThumbnailStream(CoverStreamDescriptor descriptor, ThumbnailFreshness freshness) {
    }

    /**
     * 校验封面缩略图可被当前用户读取并返回流式描述。
     *
     * <p>缩略图缺失时按需派生；原图不受理、派生并发达到上限或生成失败时回退原图描述，
     * 因此该入口始终能渲染出图像，只是尺寸可能未缩小。调用方须按
     * {@link ThumbnailStream#freshness()} 区分缓存策略：回退的原图既不能长期占住稳定
     * 缩略图路径，也不能按分钟反复下载。</p>
     *
     * @param ownerUserId 所属用户标识
     * @param fileId 封面原图文件标识
     * @return 缩略图或回退原图的流式读取结果
     */
    public ThumbnailStream prepareThumbnailStream(UUID ownerUserId, UUID fileId) {
        CoverStreamDescriptor source = prepareCoverStream(ownerUserId, fileId);
        MusicCoverThumbnailService.ThumbnailResult result = coverThumbnailService.ensureThumbnail(
                ownerUserId,
                fileId,
                source.sizeBytes()
        );
        UUID thumbnailFileId = result.fileId();
        if (thumbnailFileId == null) {
            return new ThumbnailStream(
                    source,
                    result.retryLater()
                            ? ThumbnailFreshness.RETRY_SOON
                            : ThumbnailFreshness.STABLE_FALLBACK
            );
        }
        if (thumbnailFileId.equals(fileId)) {
            return new ThumbnailStream(source, ThumbnailFreshness.DERIVED);
        }
        return new ThumbnailStream(
                prepareCoverStream(ownerUserId, thumbnailFileId),
                ThumbnailFreshness.DERIVED
        );
    }

    /**
     * 将封面内容流式写出。流句柄由本方法持有并在写完后关闭。
     *
     * @param descriptor 权限校验后的流式描述
     * @param outputStream 响应输出流
     * @throws IOException 内容读取或写出失败
     */
    public void streamCover(CoverStreamDescriptor descriptor, OutputStream outputStream) throws IOException {
        try (FileContentStream content = fileQueryService.openReadableFileContent(
                descriptor.ownerUserId(), descriptor.fileId())) {
            content.inputStream().transferTo(outputStream);
        }
    }

    /**
     * 将用户上传的图片保存为音乐封面资产。
     *
     * @param ownerUserId 所属用户标识
     * @param file 上传文件
     * @return 封面文件标识
     */
    public MusicCoverUploadDto upload(UUID ownerUserId, MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面文件不能为空");
        }
        if (file.getSize() > processingLimits.getMaxCoverUploadBytes()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面文件不能超过 8MB");
        }
        try {
            try (InputStream raw = file.getInputStream();
                 PushbackInputStream input = new PushbackInputStream(raw, 32)) {
                byte[] header = input.readNBytes(32);
                input.unread(header);
                ImageType imageType = detectImageType(header);
                UUID resourceId = UUID.randomUUID();
                UUID fileId = derivedAssetStorageService.store(
                        ownerUserId,
                        "MUSIC_COVER",
                        resourceId,
                        "COVER",
                        "cover_" + resourceId + imageType.extension(),
                        imageType.mimeType(),
                        input
                );
                log.info("音乐封面已上传: userId={}, fileId={}", ownerUserId, fileId);
                return new MusicCoverUploadDto(fileId);
            }
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "封面文件读取失败");
        }
    }

    /**
     * 校验封面文件属于当前用户且为图片。
     *
     * @param ownerUserId 所属用户标识
     * @param fileId 封面文件标识
     */
    public void validateOwnedCover(UUID ownerUserId, UUID fileId) {
        if (fileId != null) {
            fileQueryService.validateOwnedImage(ownerUserId, fileId);
        }
    }

    private ImageType detectImageType(byte[] bytes) {
        if (isJpeg(bytes)) {
            return new ImageType("image/jpeg", ".jpg");
        }
        if (startsWith(bytes, new byte[]{(byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A})) {
            return new ImageType("image/png", ".png");
        }
        if (startsWith(bytes, "GIF87a".getBytes(StandardCharsets.US_ASCII))
                || startsWith(bytes, "GIF89a".getBytes(StandardCharsets.US_ASCII))) {
            return new ImageType("image/gif", ".gif");
        }
        if (bytes.length >= 12
                && startsWith(bytes, "RIFF".getBytes(StandardCharsets.US_ASCII))
                && matchesAt(bytes, 8, "WEBP".getBytes(StandardCharsets.US_ASCII))) {
            return new ImageType("image/webp", ".webp");
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "仅支持 JPEG、PNG、GIF 或 WebP 封面");
    }

    private boolean isJpeg(byte[] bytes) {
        return bytes.length >= 3
                && bytes[0] == (byte) 0xFF
                && bytes[1] == (byte) 0xD8
                && bytes[2] == (byte) 0xFF;
    }

    private boolean startsWith(byte[] bytes, byte[] prefix) {
        return matchesAt(bytes, 0, prefix);
    }

    private boolean matchesAt(byte[] bytes, int offset, byte[] expected) {
        if (bytes.length < offset + expected.length) {
            return false;
        }
        for (int index = 0; index < expected.length; index++) {
            if (bytes[offset + index] != expected[index]) {
                return false;
            }
        }
        return true;
    }

    private record ImageType(String mimeType, String extension) {
    }
}
