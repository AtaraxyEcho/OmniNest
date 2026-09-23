package com.omninest.modules.music.service;

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
    private static final long MAX_COVER_SIZE_BYTES = 8L * 1024 * 1024;

    /**
     * 流式读取防御上限。仅作恶意/异常资源护栏：刮削下载与派生存储
     * 不经过上传入口的 8MB 校验，正常封面远小于此值。
     */
    private static final long MAX_STREAM_COVER_SIZE_BYTES = 32L * 1024 * 1024;

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
                || node.sizeBytes() > MAX_STREAM_COVER_SIZE_BYTES) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "封面文件不存在");
        }
        String contentType = node.mimeType();
        if (contentType == null || contentType.isBlank()) {
            contentType = "image/jpeg";
        }
        return new CoverStreamDescriptor(ownerUserId, fileId, contentType, node.sizeBytes());
    }

    /**
     * 缩略图流式读取结果。
     *
     * @param descriptor 实际写出的内容描述
     * @param derived 内容是否为派生缩略图；回退原图时为 false
     */
    public record ThumbnailStream(CoverStreamDescriptor descriptor, boolean derived) {
    }

    /**
     * 校验封面缩略图可被当前用户读取并返回流式描述。
     *
     * <p>缩略图缺失时按需派生；原图不受理、派生并发达到上限或生成失败时回退原图描述，
     * 因此该入口始终能渲染出图像，只是尺寸可能未缩小。调用方须按 {@code derived}
     * 区分缓存策略，避免回退的原图把稳定缩略图路径长期占住。</p>
     *
     * @param ownerUserId 所属用户标识
     * @param fileId 封面原图文件标识
     * @return 缩略图或回退原图的流式读取结果
     */
    public ThumbnailStream prepareThumbnailStream(UUID ownerUserId, UUID fileId) {
        CoverStreamDescriptor source = prepareCoverStream(ownerUserId, fileId);
        UUID thumbnailFileId = coverThumbnailService.ensureThumbnail(
                ownerUserId,
                fileId,
                source.sizeBytes()
        ).orElse(null);
        if (thumbnailFileId == null || thumbnailFileId.equals(fileId)) {
            return new ThumbnailStream(source, false);
        }
        return new ThumbnailStream(prepareCoverStream(ownerUserId, thumbnailFileId), true);
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
        if (file.getSize() > MAX_COVER_SIZE_BYTES) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面文件不能超过 8MB");
        }
        try {
            byte[] bytes = file.getBytes();
            ImageType imageType = detectImageType(bytes);
            UUID resourceId = UUID.randomUUID();
            try (InputStream input = new ByteArrayInputStream(bytes)) {
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
