package com.omninest.modules.photos.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.photos.domain.PhotoItem;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PushbackInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 照片导入的事务外预计算。
 *
 * <p>对象存储下载、EXIF 解析、RAW 预览生成与逆地理编码都是网络或重 CPU 动作，
 * 放进事务会整段占住数据库连接；RAW 预览内部还会用 {@code REQUIRES_NEW} 再要一条，
 * 扫描并发下直接触发连接池饥饿。这里只负责算，落库仍由调用方在短事务内完成。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class PhotoImportPreparer {

    /** 动态照片检测的流式读取块大小。 */
    private static final int READ_CHUNK_BYTES = 8192;

    /** 内容魔数探测的头部字节数，与 PhotoInputGuard 的魔数表保持一致。 */
    private static final int CONTENT_PEEK_BYTES = 16;

    private final PhotoFileDetector fileDetector;
    private final PhotoInputGuard inputGuard;
    private final PhotoSourceFileService sourceFileService;
    private final PhotoExifExtractor exifExtractor;
    private final PhotoRawPreviewService rawPreviewService;
    private final FileQueryService fileQueryService;
    private final PhotoGeoService photoGeoService;
    private final PhotosRuntimeConfigService photosRuntimeConfigService;

    /**
     * 预计算一次导入：原图暂存、EXIF、RAW 预览与逆地理编码。
     *
     * @param ownerUserId 当前用户 ID
     * @param file 文件节点
     * @return 待落库实体与后续投递所需信息
     */
    public PreparedPhotoImport prepare(UUID ownerUserId, FileDescriptor file) {
        PhotoItem photo = new PhotoItem();
        photo.setId(UUID.randomUUID());
        photo.setOwnerUserId(ownerUserId);
        photo.setFileNodeId(file.id());
        photo.setTitle(PhotoAdminSupport.titleFromFileName(file.name()));
        photo.setFormat(fileDetector.extension(file.name()));
        // RAW 预览需要真实文件，保留暂存路径；常规图片流式读取，
        // EXIF 提取与内容哈希共用一次下载，封面交给缩略图任务异步生成回填。
        boolean raw = fileDetector.isRaw(file.name());
        String contentHash;
        String motionKind = null;
        PhotoExifExtractor.ExifData exif;
        if (raw) {
            try (PhotoSourceFileService.StagedPhotoFile source = sourceFileService.stageReadable(
                    ownerUserId,
                    file.id()
            )) {
                photo.setFileSize(source.sizeBytes());
                try (InputStream input = Files.newInputStream(source.path())) {
                    exif = exifExtractor.extract(input);
                }
                inputGuard.validateDimensions(exif.width(), exif.height());
                applyExif(photo, exif);
                applyLocation(photo);
                if (!fileDetector.isDecodable(file.name())) {
                    photo.setCoverFileId(rawPreviewService.createPreview(
                            ownerUserId, photo.getId(), source.path()));
                }
                contentHash = computeSha256(source.path());
            } catch (IOException exception) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "照片源文件处理失败");
            }
        } else {
            try (FileContentStream content = fileQueryService.openReadableFileContent(ownerUserId, file.id());
                 DigestInputStream digestInput = new DigestInputStream(content.inputStream(), sha256Digest())) {
                photo.setFileSize(file.sizeBytes());
                // 先取头部魔数归一化 format：入口按声明 MIME 收件，扩展名
                // 可能与真实内容不符，后续处理与展示都以魔数为准。
                // pushback 仅是摘录流的包装，不拥有底层流生命周期：
                // 关闭它会连带关闭 digestInput，破坏后续尾部扫描与哈希。
                byte[] head = digestInput.readNBytes(CONTENT_PEEK_BYTES);
                String detectedFormat = inputGuard.detectContentFormat(head);
                if (detectedFormat != null) {
                    photo.setFormat(detectedFormat);
                }
                PushbackInputStream pushback = new PushbackInputStream(
                        digestInput, CONTENT_PEEK_BYTES);
                pushback.unread(head, 0, head.length);
                exif = exifExtractor.extract(pushback);
                inputGuard.validateDimensions(exif.width(), exif.height());
                applyExif(photo, exif);
                applyLocation(photo);
                // 流式哈希同时维护 4KB 尾部环形缓冲，供三星 SEF trailer 扫描，零额外 IO。
                byte[] tail = new byte[PhotoMotionTrailerScanner.TAIL_WINDOW_BYTES];
                byte[] chunk = new byte[READ_CHUNK_BYTES];
                int tailFilled = 0;
                int read;
                while ((read = digestInput.read(chunk)) != -1) {
                    tailFilled = appendTail(tail, tailFilled, chunk, read);
                }
                contentHash = HexFormat.of().formatHex(digestInput.getMessageDigest().digest());
                motionKind = resolveMotionKind(file.name(), exif.motion(), tail, tailFilled);
                if (motionKind != null) {
                    Map<String, Object> motion = new HashMap<>();
                    motion.put("kind", motionKind);
                    if (exif.motion().microVideoOffset() != null) {
                        motion.put("offsetBytes", exif.motion().microVideoOffset());
                    }
                    photo.getProviderMetadata().put("motion", motion);
                    photo.setMotionState(PhotoMotionVideoService.STATE_DETECTED);
                }
            } catch (IOException exception) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "照片源文件处理失败");
            }
        }
        photo.setMetadataStatus(exif.hasAnyValue()
                ? MetadataStatus.MATCHED.getValue()
                : MetadataStatus.PENDING.getValue());
        photo.getProviderMetadata().put("contentHash", contentHash);
        return new PreparedPhotoImport(
                photo,
                motionKind,
                !raw && file.currentObjectId() != null,
                photosRuntimeConfigService.isAiEnabled()
        );
    }

    private void applyLocation(PhotoItem photo) {
        if (photo.getGpsLatitude() == null || photo.getGpsLongitude() == null) {
            return;
        }
        Map<String, Object> geoInfo = photoGeoService.reverseGeocode(
                photo.getGpsLatitude(),
                photo.getGpsLongitude()
        );
        if (!geoInfo.isEmpty()) {
            photo.setGpsLocation(geoInfo);
        }
    }

    /** 新建 SHA-256 摘要器。 */
    private MessageDigest sha256Digest() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 算法不可用", exception);
        }
    }

    /**
     * 把本次读取的字节追加进尾部环形缓冲，保留最近的窗口字节。
     *
     * @param tail 尾部缓冲
     * @param tailFilled 缓冲中的有效字节数
     * @param chunk 本次读取的数据
     * @param length 本次读取的有效长度
     * @return 更新后的有效字节数
     */
    private int appendTail(byte[] tail, int tailFilled, byte[] chunk, int length) {
        if (length >= tail.length) {
            System.arraycopy(chunk, length - tail.length, tail, 0, tail.length);
            return tail.length;
        }
        int overflow = tailFilled + length - tail.length;
        if (overflow > 0) {
            System.arraycopy(tail, overflow, tail, 0, tailFilled - overflow);
            tailFilled -= overflow;
        }
        System.arraycopy(chunk, 0, tail, tailFilled, length);
        return tailFilled + length;
    }

    /**
     * 解析动态照片类型：优先 XMP（GCamera 新旧标准），未命中时扫描三星 SEF trailer。
     * 仅对 JPEG 生效，RAW/HEIC 等格式不做检测。
     */
    private String resolveMotionKind(
            String fileName,
            PhotoExifExtractor.MotionInfo motionInfo,
            byte[] tail,
            int tailFilled
    ) {
        String extension = fileDetector.extension(fileName);
        if (!"jpg".equals(extension) && !"jpeg".equals(extension)) {
            return null;
        }
        if (motionInfo.detected()) {
            return motionInfo.microVideo() ? "MICRO_VIDEO" : "MOTION_PHOTO";
        }
        if (PhotoMotionTrailerScanner.hasSefTrailer(tail, tailFilled)) {
            return "SEF_TRAILER";
        }
        return null;
    }

    private void applyExif(PhotoItem photo, PhotoExifExtractor.ExifData exif) {
        photo.setWidth(exif.width());
        photo.setHeight(exif.height());
        photo.setOrientation(exif.orientation());
        photo.setDateTaken(exif.dateTaken());
        photo.setCameraMake(exif.cameraMake());
        photo.setCameraModel(exif.cameraModel());
        photo.setAperture(exif.aperture());
        photo.setShutterSpeed(exif.shutterSpeed());
        photo.setIso(exif.iso());
        photo.setFocalLength(exif.focalLength());
        photo.setGpsLatitude(exif.gpsLatitude());
        photo.setGpsLongitude(exif.gpsLongitude());
        photo.setFlash(exif.flash());
        photo.setWhiteBalance(exif.whiteBalance());
        photo.setMeteringMode(exif.meteringMode());
        photo.setLensModel(exif.lensModel());
    }

    private String computeSha256(Path file) throws IOException {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream input = Files.newInputStream(file);
                 DigestInputStream digestInput = new DigestInputStream(input, digest)) {
                digestInput.transferTo(OutputStream.nullOutputStream());
            }
            return HexFormat.of().formatHex(digest.digest());
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 算法不可用", exception);
        }
    }

    /**
     * 事务外预计算的导入结果。
     *
     * @param photo 尚未落库的照片实体
     * @param motionKind 动态照片类型，非动态照片为 {@code null}
     * @param enqueuePostProcessing 是否补投缩略图/运动视频任务
     * @param aiAnalysisEnabled 是否提交 AI 分析任务
     */
    public record PreparedPhotoImport(
            PhotoItem photo,
            String motionKind,
            boolean enqueuePostProcessing,
            boolean aiAnalysisEnabled
    ) {
    }
}
