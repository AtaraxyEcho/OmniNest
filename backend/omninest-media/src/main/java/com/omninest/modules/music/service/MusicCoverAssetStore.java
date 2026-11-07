package com.omninest.modules.music.service;

import com.omninest.common.processing.TempStagingPort;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import java.util.Locale;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 把音频内嵌封面（data URL）落成派生资产。
 *
 * <p>内联 data URL 会随曲目列表与播放队列快照整段进出（单条几百 KB），是曲库首屏
 * 与重启恢复的主要载荷来源；资产化后列表只剩稳定 API 路径。存储调用走
 * {@code REQUIRES_NEW}，因此必须由事务外的预取阶段调用，不能放进曲目落库事务。</p>
 *
 * <p>独立成类而不是留在 {@link MusicAdminService}：封面解析、体积上限与临时文件
 * 生命周期是一块完整职责，混在扫描服务里会同时撑大扫描逻辑与文件行数。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicCoverAssetStore {

    /** 派生封面存储的资源类型与资产类型，与手动上传共用同一前缀。 */
    private static final String COVER_RESOURCE_TYPE = "MUSIC_COVER";
    private static final String COVER_ASSET_TYPE = "COVER";

    private final MusicTrackRepository trackRepository;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final MediaProcessingLimitsProperties processingLimits;
    private final TempStagingPort tempStagingPort;

    /**
     * 事务外把内嵌封面落成派生资产。
     *
     * <p>存储键以音频文件节点为资源标识，重复扫描命中同一 normalizedPath 复用节点，
     * 不新增对象。已有封面或已人工精修的曲目不会被覆写，这里先跳过可省的解析与上传。</p>
     *
     * @param ownerUserId 曲目归属用户
     * @param sourceFile 音频文件节点
     * @param coverDataUrl 内嵌封面 data URL
     * @return 派生封面文件节点 ID；无需或无法资产化时返回 {@code null}
     */
    public UUID storeEmbeddedCoverAsset(UUID ownerUserId, FileDescriptor sourceFile, String coverDataUrl) {
        if (coverDataUrl == null || coverDataUrl.isBlank()) {
            return null;
        }
        MusicTrack existing = trackRepository.findByFileNodeId(sourceFile.id()).orElse(null);
        if (existing != null && (existing.getCoverFileId() != null
                || MetadataStatus.MANUAL.getValue().equals(existing.getMetadataStatus()))) {
            return null;
        }
        EmbeddedCover cover = parseEmbeddedCover(coverDataUrl);
        if (cover == null) {
            return null;
        }
        Path staged = null;
        try {
            staged = tempStagingPort.createTempFile(
                    "music-cover", "omninest-music-cover-", "." + cover.extension());
            Files.write(staged, cover.bytes());
            return derivedAssetStorageService.store(
                    ownerUserId,
                    COVER_RESOURCE_TYPE,
                    sourceFile.id(),
                    COVER_ASSET_TYPE,
                    "cover." + cover.extension(),
                    cover.mimeType(),
                    staged
            );
        } catch (IOException | RuntimeException ex) {
            log.warn("音乐内嵌封面资产化失败，保留内联地址: fileNodeId={}, errorType={}",
                    sourceFile.id(), ex.getClass().getSimpleName());
            return null;
        } finally {
            deleteQuietly(staged);
        }
    }

    private EmbeddedCover parseEmbeddedCover(String coverDataUrl) {
        int comma = coverDataUrl.indexOf(',');
        if (comma <= 0) {
            return null;
        }
        String header = coverDataUrl.substring(0, comma).toLowerCase(Locale.ROOT);
        if (!header.startsWith("data:image/") || !header.endsWith(";base64")) {
            return null;
        }
        String mimeType = header.substring("data:".length(), header.length() - ";base64".length());
        String extension = coverExtension(mimeType);
        if (extension == null) {
            return null;
        }
        String payload = coverDataUrl.substring(comma + 1);
        long maxBytes = processingLimits.getMaxEmbeddedCoverBytes();
        long maxEncodedChars = (maxBytes / 3L + 1L) * 4L;
        if (payload.isEmpty() || payload.length() > maxEncodedChars) {
            return null;
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(payload);
        } catch (IllegalArgumentException ex) {
            log.warn("音乐内嵌封面 base64 解码失败: errorType={}", ex.getClass().getSimpleName());
            return null;
        }
        if (bytes.length == 0 || bytes.length > maxBytes) {
            return null;
        }
        return new EmbeddedCover(mimeType, extension, bytes);
    }

    private String coverExtension(String mimeType) {
        return switch (mimeType) {
            case "image/jpeg" -> "jpg";
            case "image/png" -> "png";
            case "image/gif" -> "gif";
            case "image/webp" -> "webp";
            default -> null;
        };
    }

    private void deleteQuietly(Path file) {
        tempStagingPort.deleteQuietly(file);
    }

    /**
     * 解码后的内嵌封面：MIME、派生文件名后缀与原始字节。
     */
    private record EmbeddedCover(String mimeType, String extension, byte[] bytes) {
    }
}
