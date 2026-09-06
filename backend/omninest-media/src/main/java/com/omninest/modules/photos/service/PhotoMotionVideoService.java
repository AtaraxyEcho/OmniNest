package com.omninest.modules.photos.service;

import com.drew.imaging.ImageMetadataReader;
import com.drew.metadata.Metadata;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 动态照片运动视频提取服务。
 *
 * <p>导入时仅识别动态照片并置 DETECTED；本服务在 Worker 中重开源文件，
 * 按旧标准 XMP 偏移或向尾部扫描 "ftyp" 定位内嵌 MP4 起点，字节区间拷贝为
 * MOTION_VIDEO 派生资产并置 READY。派生资产随源文件永久删除自动清理。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoMotionVideoService {

    /** 动态照片状态。 */
    public static final String STATE_DETECTED = "DETECTED";
    public static final String STATE_READY = "READY";
    public static final String STATE_FAILED = "FAILED";

    public static final String RESOURCE_TYPE = "PHOTO_ITEM";
    public static final String ASSET_TYPE = "MOTION_VIDEO";
    public static final String FILE_NAME = "motion.mp4";
    public static final String MIME_TYPE = "video/mp4";

    private static final byte[] FTYP_MAGIC = "ftyp".getBytes(StandardCharsets.US_ASCII);
    /** 尾部回扫窗口上限；运动视频段通常在数 MB 量级。 */
    private static final long MAX_SCAN_WINDOW_BYTES = 64L * 1024 * 1024;
    private static final int SCAN_CHUNK_BYTES = 1024 * 1024;

    private final PhotoItemRepository photoItemRepository;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final MediaSyncEventService syncEventService;
    private final PhotoExifExtractor exifExtractor;

    /**
     * 提取动态照片内嵌运动视频并存储为派生资产。
     *
     * <p>幂等：READY 状态或资产已存在时直接返回；定位失败置 FAILED 并抛出
     * 不可重试业务异常使任务进入死信，瞬时 IO 异常向上传播走任务重试。</p>
     *
     * @param ownerUserId 照片所有者
     * @param fileNodeId 源照片文件节点
     * @param sourceFile 已暂存的本地源文件
     * @return 运动视频派生文件节点；已就绪时返回既有值
     */
    public UUID extractAndStore(UUID ownerUserId, UUID fileNodeId, Path sourceFile) {
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "照片不存在"));
        if (STATE_READY.equals(photo.getMotionState()) && photo.getMotionVideoFileNodeId() != null) {
            return photo.getMotionVideoFileNodeId();
        }
        if (!fileLifecycleGuard.isOwnedProcessable(ownerUserId, fileNodeId)) {
            log.info("源文件已删除或正在永久删除，跳过动态视频提取: fileNodeId={}", fileNodeId);
            throw new BusinessException(ErrorCode.FILE_LIFECYCLE_CONFLICT, "源文件不可处理");
        }
        long fileSize;
        try {
            fileSize = Files.size(sourceFile);
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "动态照片源文件不可读");
        }
        long videoStart = locateVideoStart(sourceFile, fileSize, resolveOffset(photo));
        if (videoStart < 0) {
            markFailed(photo, "VIDEO_SEGMENT_NOT_FOUND");
            throw new BusinessException(ErrorCode.NOT_FOUND, "未在文件中定位到动态视频段");
        }
        Path tempFile = null;
        try {
            tempFile = Files.createTempFile("omninest-photo-motion-", ".mp4");
            copyRange(sourceFile, videoStart, tempFile);
            UUID videoFileNodeId = derivedAssetStorageService.store(
                    ownerUserId,
                    RESOURCE_TYPE,
                    fileNodeId,
                    ASSET_TYPE,
                    FILE_NAME,
                    MIME_TYPE,
                    tempFile
            );
            long videoSize = Files.size(tempFile);
            Map<String, Object> motion = motionMap(photo);
            motion.put("videoSizeBytes", videoSize);
            motion.remove("failReason");
            photo.setMotionState(STATE_READY);
            photo.setMotionVideoFileNodeId(videoFileNodeId);
            photoItemRepository.save(photo);
            syncEventService.invalidate(
                    ownerUserId,
                    SyncScope.PHOTOS,
                    "PHOTO_LIBRARY",
                    Map.of("source", "MOTION", "fileNodeId", fileNodeId.toString())
            );
            log.info("动态视频提取完成: fileNodeId={}, videoFileNodeId={}, videoSize={}",
                    fileNodeId, videoFileNodeId, videoSize);
            return videoFileNodeId;
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "动态视频段写入失败");
        } finally {
            if (tempFile != null) {
                try {
                    Files.deleteIfExists(tempFile);
                } catch (IOException ex) {
                    log.warn("动态视频临时文件清理失败: {}", ex.getMessage());
                }
            }
        }
    }

    /**
     * 对尚未识别动态照片的照片执行检测并置 DETECTED，供存量回扫使用。
     *
     * @param ownerUserId 照片所有者
     * @param fileNodeId 源照片文件节点
     * @param sourceFile 已暂存的本地源文件
     * @return 命中动态照片返回 true
     */
    public boolean detectAndMark(UUID ownerUserId, UUID fileNodeId, Path sourceFile) {
        PhotoItem photo = photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerUserId, fileNodeId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "照片不存在"));
        if (photo.getMotionState() != null) {
            return false;
        }
        PhotoExifExtractor.MotionInfo info = extractMotionInfo(sourceFile);
        if (!info.detected() && !PhotoMotionTrailerScanner.scanTail(sourceFile)) {
            return false;
        }
        String kind = info.microVideo() ? "MICRO_VIDEO" : info.motionPhoto() ? "MOTION_PHOTO" : "SEF_TRAILER";
        Map<String, Object> motion = motionMap(photo);
        motion.put("kind", kind);
        if (info.microVideoOffset() != null) {
            motion.put("offsetBytes", info.microVideoOffset());
        }
        photo.setMotionState(STATE_DETECTED);
        photoItemRepository.save(photo);
        return true;
    }

    private PhotoExifExtractor.MotionInfo extractMotionInfo(Path sourceFile) {
        try (var input = Files.newInputStream(sourceFile)) {
            Metadata metadata = ImageMetadataReader.readMetadata(input);
            return exifExtractor.extractMotionInfo(metadata);
        } catch (Exception ex) {
            log.debug("回扫 XMP 解析失败: {}", ex.getMessage());
            return new PhotoExifExtractor.MotionInfo(false, false, null);
        }
    }

    /**
     * 定位内嵌 MP4 起点；优先使用旧标准偏移，失败时向尾部回扫 "ftyp"。
     *
     * @return 起点字节下标；未找到返回 -1
     */
    long locateVideoStart(Path sourceFile, long fileSize, Long offsetBytes) {
        if (offsetBytes != null && offsetBytes > 0 && offsetBytes < fileSize) {
            long candidate = fileSize - offsetBytes;
            if (matchesFtypAt(sourceFile, candidate)) {
                return candidate;
            }
        }
        return scanBackwardsForFtyp(sourceFile, fileSize);
    }

    private Long resolveOffset(PhotoItem photo) {
        Object offset = motionMap(photo).get("offsetBytes");
        if (offset instanceof Number number) {
            return number.longValue();
        }
        return null;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> motionMap(PhotoItem photo) {
        Object current = photo.getProviderMetadata().get("motion");
        if (current instanceof Map) {
            return (Map<String, Object>) current;
        }
        Map<String, Object> motion = new HashMap<>();
        photo.getProviderMetadata().put("motion", motion);
        return motion;
    }

    private void markFailed(PhotoItem photo, String reason) {
        Map<String, Object> motion = motionMap(photo);
        motion.put("failReason", reason);
        photo.setMotionState(STATE_FAILED);
        photoItemRepository.save(photo);
    }

    private boolean matchesFtypAt(Path sourceFile, long position) {
        try (RandomAccessFile file = new RandomAccessFile(sourceFile.toFile(), "r")) {
            if (position < 0 || position + 8 > file.length()) {
                return false;
            }
            file.seek(position + 4);
            byte[] magic = new byte[4];
            file.readFully(magic);
            return equalsFtyp(magic);
        } catch (IOException ex) {
            log.warn("动态视频起点校验失败: {}", ex.getMessage());
            return false;
        }
    }

    /**
     * 在尾部窗口内向前单遍扫描，记录最后一次出现的 "ftyp" 下标。
     *
     * <p>MP4 起始 4 字节是 box size，紧随其后才是 "ftyp"，故命中下标需回退 4 字节。
     * 逐块顺序读取并在块间保留 4 字节重叠，避免魔数跨界漏检。</p>
     */
    private long scanBackwardsForFtyp(Path sourceFile, long fileSize) {
        long window = Math.min(MAX_SCAN_WINDOW_BYTES, fileSize);
        long scanStart = fileSize - window;
        long lastMatch = -1;
        try (FileChannel channel = FileChannel.open(sourceFile, StandardOpenOption.READ)) {
            long position = scanStart;
            byte[] overlap = new byte[FTYP_MAGIC.length - 1];
            int overlapLength = 0;
            ByteBuffer buffer = ByteBuffer.allocate(SCAN_CHUNK_BYTES + overlap.length);
            while (position < fileSize) {
                buffer.clear();
                if (overlapLength > 0) {
                    buffer.put(overlap, 0, overlapLength);
                }
                long readable = fileSize - position;
                int chunk = (int) Math.min(SCAN_CHUNK_BYTES, readable);
                channel.position(position);
                buffer.limit(overlapLength + chunk);
                channel.read(buffer);
                int filled = buffer.position();
                byte[] data = buffer.array();
                for (int i = filled - FTYP_MAGIC.length; i >= 0; i--) {
                    if (equalsFtyp(data, i)) {
                        lastMatch = position - overlapLength + i;
                        break;
                    }
                }
                if (lastMatch >= 0) {
                    break;
                }
                int carry = Math.min(overlap.length, filled);
                System.arraycopy(data, filled - carry, overlap, 0, carry);
                overlapLength = carry;
                position += chunk;
            }
            // 命中下标是 "ftyp" 魔数本身，视频起点在其前 4 字节的 box size 处。
            return lastMatch >= FTYP_MAGIC.length ? lastMatch - FTYP_MAGIC.length : -1;
        } catch (IOException ex) {
            log.warn("动态视频尾部扫描失败: {}", ex.getMessage());
            return -1;
        }
    }

    private void copyRange(Path sourceFile, long start, Path target) throws IOException {
        try (FileChannel source = FileChannel.open(sourceFile, StandardOpenOption.READ);
             FileChannel destination = FileChannel.open(
                     target,
                     StandardOpenOption.WRITE,
                     StandardOpenOption.TRUNCATE_EXISTING,
                     StandardOpenOption.CREATE
             )) {
            long size = Files.size(sourceFile) - start;
            long transferred = 0;
            while (transferred < size) {
                long moved = source.transferTo(start + transferred, size - transferred, destination);
                if (moved <= 0) {
                    break;
                }
                transferred += moved;
            }
        }
    }

    private boolean equalsFtyp(byte[] data, int offset) {
        for (int i = 0; i < FTYP_MAGIC.length; i++) {
            if (data[offset + i] != FTYP_MAGIC[i]) {
                return false;
            }
        }
        return true;
    }

    private boolean equalsFtyp(byte[] data) {
        return data.length == FTYP_MAGIC.length && equalsFtyp(data, 0);
    }
}
