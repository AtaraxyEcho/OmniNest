package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

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
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mockito;

/**
 * 动态视频提取服务单元测试：偏移定位、尾部回扫、失败标记与幂等路径。
 *
 * @author OmniNest
 */
class PhotoMotionVideoServiceTest {

    private static final byte[] MP4_HEAD = new byte[] {
        0x00, 0x00, 0x00, 0x20,
        'f', 't', 'y', 'p',
        'm', 'p', '4', '2',
    };

    private static final byte[] MP4_BODY = "moov-mdat-payload".getBytes(StandardCharsets.US_ASCII);

    /** 视频起点距文件末尾的字节数（MP4 头 + 体）。 */
    private static final long MP4_LENGTH = MP4_HEAD.length + MP4_BODY.length;

    @TempDir
    Path tempDir;

    private PhotoItemRepository photoItemRepository;
    private DerivedAssetStorageService derivedAssetStorageService;
    private FileLifecycleGuard fileLifecycleGuard;
    private MediaSyncEventService syncEventService;
    private PhotoMotionVideoService service;

    @BeforeEach
    void setUp() {
        photoItemRepository = Mockito.mock(PhotoItemRepository.class);
        derivedAssetStorageService = Mockito.mock(DerivedAssetStorageService.class);
        fileLifecycleGuard = Mockito.mock(FileLifecycleGuard.class);
        syncEventService = Mockito.mock(MediaSyncEventService.class);
        service = new PhotoMotionVideoService(
                photoItemRepository,
                derivedAssetStorageService,
                fileLifecycleGuard,
                syncEventService,
                new PhotoExifExtractor()
        );
        lenient().when(fileLifecycleGuard.isOwnedProcessable(any(), any())).thenReturn(true);
    }

    @Test
    void extractsVideoUsingLegacyOffset() throws IOException {
        UUID ownerId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        UUID videoNodeId = UUID.randomUUID();
        int padding = 4096;
        Path source = tempDir.resolve("motion.jpg");
        Files.write(source, concat(jpegBody(), new byte[padding], MP4_HEAD, MP4_BODY));
        PhotoItem photo = photo(ownerId, fileNodeId, "MICRO_VIDEO", MP4_LENGTH);
        when(photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerId, fileNodeId))
                .thenReturn(Optional.of(photo));
        when(derivedAssetStorageService.store(
                eq(ownerId), anyString(), eq(fileNodeId), anyString(), anyString(), anyString(), any(Path.class)))
                .thenReturn(videoNodeId);

        UUID result = service.extractAndStore(ownerId, fileNodeId, source);

        assertThat(result).isEqualTo(videoNodeId);
        assertThat(photo.getMotionState()).isEqualTo(PhotoMotionVideoService.STATE_READY);
        assertThat(photo.getMotionVideoFileNodeId()).isEqualTo(videoNodeId);
        assertThat(motion(photo).get("videoSizeBytes")).isEqualTo(MP4_LENGTH);
        verify(syncEventService).invalidate(eq(ownerId), eq(SyncScope.PHOTOS), eq("PHOTO_LIBRARY"), any());
    }

    @Test
    void fallsBackToBackwardsScanWhenOffsetMissing() throws IOException {
        UUID ownerId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        UUID videoNodeId = UUID.randomUUID();
        Path source = tempDir.resolve("modern.jpg");
        Files.write(source, concat(jpegBody(), MP4_HEAD, MP4_BODY));
        PhotoItem photo = photo(ownerId, fileNodeId, "MOTION_PHOTO", null);
        when(photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerId, fileNodeId))
                .thenReturn(Optional.of(photo));
        // 临时文件在服务返回前会被清理，须在存储调用时读取内容。
        byte[][] storedBytes = {null};
        when(derivedAssetStorageService.store(
                eq(ownerId), anyString(), eq(fileNodeId), anyString(), anyString(), anyString(), any(Path.class)))
                .thenAnswer(invocation -> {
                    storedBytes[0] = Files.readAllBytes(invocation.getArgument(6));
                    return videoNodeId;
                });

        UUID result = service.extractAndStore(ownerId, fileNodeId, source);

        assertThat(result).isEqualTo(videoNodeId);
        assertThat(new String(storedBytes[0], 4, 4, StandardCharsets.US_ASCII)).isEqualTo("ftyp");
    }

    @Test
    void marksFailedWhenNoVideoSegmentFound() throws IOException {
        UUID ownerId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        Path source = tempDir.resolve("plain.jpg");
        Files.write(source, jpegBody());
        PhotoItem photo = photo(ownerId, fileNodeId, "SEF_TRAILER", null);
        when(photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerId, fileNodeId))
                .thenReturn(Optional.of(photo));

        assertThatThrownBy(() -> service.extractAndStore(ownerId, fileNodeId, source))
                .isInstanceOf(BusinessException.class)
                .extracting(e -> ((BusinessException) e).errorCode())
                .isEqualTo(ErrorCode.NOT_FOUND);

        assertThat(photo.getMotionState()).isEqualTo(PhotoMotionVideoService.STATE_FAILED);
        assertThat(motion(photo).get("failReason")).isEqualTo("VIDEO_SEGMENT_NOT_FOUND");
        verify(derivedAssetStorageService, never()).store(any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
    }

    @Test
    void isIdempotentWhenAlreadyReady() throws IOException {
        UUID ownerId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        UUID existingVideoNodeId = UUID.randomUUID();
        Path source = tempDir.resolve("ready.jpg");
        Files.write(source, concat(jpegBody(), MP4_HEAD, MP4_BODY));
        PhotoItem photo = photo(ownerId, fileNodeId, "MICRO_VIDEO", 1L);
        photo.setMotionState(PhotoMotionVideoService.STATE_READY);
        photo.setMotionVideoFileNodeId(existingVideoNodeId);
        when(photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerId, fileNodeId))
                .thenReturn(Optional.of(photo));

        UUID result = service.extractAndStore(ownerId, fileNodeId, source);

        assertThat(result).isEqualTo(existingVideoNodeId);
        verify(derivedAssetStorageService, never()).store(any(), anyString(), any(), anyString(), anyString(), anyString(), any(Path.class));
    }

    @Test
    void detectAndMarkFlagsModernMotionPhoto() throws IOException {
        UUID ownerId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        Path source = tempDir.resolve("detect.jpg");
        String xmp = """
                <x:xmpmeta xmlns:x="adobe:ns:meta/">
                 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                  <rdf:Description rdf:about="" xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
                   GCamera:MotionPhoto="1"/>
                 </rdf:RDF>
                </x:xmpmeta>""";
        Files.write(source, minimalJpegWithXmp(xmp));
        PhotoItem photo = photo(ownerId, fileNodeId, null, null);
        when(photoItemRepository.findByOwnerUserIdAndFileNodeId(ownerId, fileNodeId))
                .thenReturn(Optional.of(photo));

        boolean detected = service.detectAndMark(ownerId, fileNodeId, source);

        assertThat(detected).isTrue();
        assertThat(photo.getMotionState()).isEqualTo(PhotoMotionVideoService.STATE_DETECTED);
        assertThat(motion(photo).get("kind")).isEqualTo("MOTION_PHOTO");
    }

    private PhotoItem photo(UUID ownerId, UUID fileNodeId, String kind, Long offset) {
        PhotoItem photo = new PhotoItem();
        photo.setId(UUID.randomUUID());
        photo.setOwnerUserId(ownerId);
        photo.setFileNodeId(fileNodeId);
        photo.setTitle("Motion");
        photo.setFormat("jpg");
        photo.setFileSize(1024);
        photo.setMetadataStatus("READY");
        Map<String, Object> motion = new HashMap<>();
        if (kind != null) {
            motion.put("kind", kind);
        }
        if (offset != null) {
            motion.put("offsetBytes", offset);
        }
        photo.getProviderMetadata().put("motion", motion);
        return photo;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> motion(PhotoItem photo) {
        return (Map<String, Object>) photo.getProviderMetadata().get("motion");
    }

    private byte[] jpegBody() {
        return "jpeg-image-bytes".getBytes(StandardCharsets.US_ASCII);
    }

    private byte[] minimalJpegWithXmp(String xmp) throws IOException {
        byte[] xmpBytes = xmp.getBytes(StandardCharsets.UTF_8);
        byte[] header = "http://ns.adobe.com/xap/1.0/\0".getBytes(StandardCharsets.US_ASCII);
        byte[] out = new byte[4 + 2 + header.length + xmpBytes.length + 2];
        int i = 0;
        out[i++] = (byte) 0xFF;
        out[i++] = (byte) 0xD8;
        int segmentLength = header.length + xmpBytes.length + 2;
        out[i++] = (byte) 0xFF;
        out[i++] = (byte) 0xE1;
        out[i++] = (byte) ((segmentLength >> 8) & 0xFF);
        out[i++] = (byte) (segmentLength & 0xFF);
        System.arraycopy(header, 0, out, i, header.length);
        i += header.length;
        System.arraycopy(xmpBytes, 0, out, i, xmpBytes.length);
        i += xmpBytes.length;
        out[i++] = (byte) 0xFF;
        out[i] = (byte) 0xD9;
        return out;
    }

    private byte[] concat(byte[]... parts) {
        int total = 0;
        for (byte[] part : parts) {
            total += part.length;
        }
        byte[] result = new byte[total];
        int offset = 0;
        for (byte[] part : parts) {
            System.arraycopy(part, 0, result, offset, part.length);
            offset += part.length;
        }
        return result;
    }

}
