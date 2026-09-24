package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FilePermissionService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.music.domain.MusicAlbum;
import com.omninest.modules.music.domain.MusicArtist;
import com.omninest.modules.music.domain.MusicScanJob;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.event.MusicScanEvent;
import com.omninest.modules.music.repository.MusicAlbumRepository;
import com.omninest.modules.music.repository.MusicArtistRepository;
import com.omninest.modules.music.repository.MusicScanJobRepository;
import com.omninest.modules.music.repository.MusicTrackRepository;
import com.omninest.modules.notification.service.NotificationService;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * 音乐管理服务单元测试。
 *
 * @author OmniNest
 */
class MusicAdminServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID AUDIO_FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SCAN_JOB_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");

    private final MusicScanJobRepository scanJobRepository = mock(MusicScanJobRepository.class);
    private final MusicTrackRepository trackRepository = mock(MusicTrackRepository.class);
    private final MusicAlbumRepository albumRepository = mock(MusicAlbumRepository.class);
    private final MusicArtistRepository artistRepository = mock(MusicArtistRepository.class);
    private final MusicCatalogService catalogService = mock(MusicCatalogService.class);
    private final FileMetadataQueryService fileMetadataQueryService = mock(FileMetadataQueryService.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final MusicLibraryService musicLibraryService = mock(MusicLibraryService.class);
    private final FilePermissionService filePermissionService =
            mock(FilePermissionService.class);
    private final NotificationService notificationService =
            mock(NotificationService.class);
    private final TaskRecordService taskRecordService =
            mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService =
            mock(TaskDispatchService.class);
    private final MediaSyncEventService syncEventService = mock(MediaSyncEventService.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class);
    private final PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
    private final DerivedAssetStorageService derivedAssetStorageService =
            mock(DerivedAssetStorageService.class);
    private final MusicAdminService adminService = new MusicAdminService(
            scanJobRepository,
            trackRepository,
            albumRepository,
            artistRepository,
            catalogService,
            fileMetadataQueryService,
            fileQueryService,
            new MusicMetadataExtractor(),
            musicLibraryService,
            filePermissionService,
            notificationService,
            taskRecordService,
            taskDispatchService,
            syncEventService,
            readThroughCache,
            transactionManager,
            derivedAssetStorageService
    );

    MusicAdminServiceTest() {
        adminService.initTransactionTemplate();
    }

    @BeforeEach
    void setUpTaskClaim() {
        when(taskRecordService.claimForExecution(any(UUID.class), any(String.class))).thenReturn(true);
        when(fileQueryService.openOwnedFileContent(any(UUID.class), any(UUID.class)))
                .thenAnswer(invocation -> content("empty-audio", "application/octet-stream", new byte[0]));
    }

    @Test
    void createScanJobQueuesUnifiedSystemTaskAndPublishesEvent() {
        when(scanJobRepository.save(any(MusicScanJob.class))).thenAnswer(invocation -> invocation.getArgument(0));

        var result = adminService.createScanJob(OWNER_ID);

        assertThat(result.status()).isEqualTo("QUEUED");
        assertThat(result.progress()).isZero();
        verify(taskRecordService).createQueuedTask(
                eq(result.id()),
                eq(OWNER_ID),
                eq("MUSIC_SCAN"),
                eq(QueueNames.MUSIC_SCAN_ROUTING_KEY),
                any(Map.class));
        verify(taskDispatchService).enqueue(
                eq(result.id()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.MUSIC_SCAN_ROUTING_KEY),
                any(MusicScanEvent.class));
    }

    @Test
    void executeScanJobImportsActiveAudioFilesAndIgnoresOtherFiles() {
        FileDescriptor audio = fileNode(AUDIO_FILE_ID, "Night Drive.flac", "audio/flac", 12_000_000L);
        FileDescriptor document = fileNode(
                UUID.fromString("20000000-0000-0000-0000-000000000002"),
                "notes.pdf",
                "application/pdf",
                128L);

        stubScanJob();
        stubMusicPersistence();
        when(fileMetadataQueryService.listOwnedActive(OWNER_ID)).thenReturn(List.of(audio, document));
        when(fileMetadataQueryService.listSharedVisibleToUser(OWNER_ID)).thenReturn(List.of());
        when(trackRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, AUDIO_FILE_ID)).thenReturn(Optional.empty());

        adminService.executeScanJob(SCAN_JOB_ID, OWNER_ID);

        verify(trackRepository).save(any(MusicTrack.class));
        verify(taskRecordService).markCompleted(eq(SCAN_JOB_ID), any(Map.class));
        verify(trackRepository, never()).findByOwnerUserIdAndFileNodeId(OWNER_ID, document.id());
    }

    @Test
    void executeScanJobRefreshesUnknownAlbumAndArtistCounts() {
        FileDescriptor audio = fileNode(AUDIO_FILE_ID, "Night Drive.flac", "audio/flac", 12_000_000L);
        stubScanJob();
        stubMusicPersistence();
        when(fileMetadataQueryService.listOwnedActive(OWNER_ID)).thenReturn(List.of(audio));
        when(fileMetadataQueryService.listSharedVisibleToUser(OWNER_ID)).thenReturn(List.of());
        when(trackRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, AUDIO_FILE_ID)).thenReturn(Optional.empty());

        adminService.executeScanJob(SCAN_JOB_ID, OWNER_ID);

        verify(catalogService).refreshStatisticsBatch(eq(OWNER_ID), any(Set.class), any(Set.class));
    }

    @Test
    void executeScanJobExtractsEmbeddedAudioMetadata() throws Exception {
        UUID objectId = UUID.fromString("30000000-0000-0000-0000-000000000001");
        FileDescriptor audio = fileNode(
                AUDIO_FILE_ID, "fallback.mp3", "audio/mpeg", 12_000_000L, objectId);
        stubScanJob();
        stubMusicPersistence();
        when(fileMetadataQueryService.listOwnedActive(OWNER_ID)).thenReturn(List.of(audio));
        when(fileMetadataQueryService.listSharedVisibleToUser(OWNER_ID)).thenReturn(List.of());
        when(trackRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, AUDIO_FILE_ID)).thenReturn(Optional.empty());
        byte[] audioBytes = id3Tag(
                textFrame("TIT2", "Night Drive"),
                textFrame("TPE1", "Omni Band"),
                textFrame("TALB", "City Lights"),
                unsynchronizedLyricsFrame("eng", "", "[00:01.00]Rolling"),
                attachedPictureFrame("image/png", new byte[] {1, 2, 3, 4})
        );
        when(fileQueryService.openOwnedFileContent(OWNER_ID, AUDIO_FILE_ID))
                .thenReturn(content("fallback.mp3", "audio/mpeg", audioBytes));
        UUID coverFileId = UUID.fromString("40000000-0000-0000-0000-000000000001");
        AtomicReference<byte[]> storedCover = new AtomicReference<>();
        when(derivedAssetStorageService.store(
                eq(OWNER_ID),
                eq("MUSIC_COVER"),
                eq(AUDIO_FILE_ID),
                eq("COVER"),
                eq("cover.png"),
                eq("image/png"),
                any(Path.class)
        )).thenAnswer(invocation -> {
            storedCover.set(Files.readAllBytes(invocation.getArgument(6, Path.class)));
            return coverFileId;
        });

        adminService.executeScanJob(SCAN_JOB_ID, OWNER_ID);

        var trackCaptor = ArgumentCaptor.forClass(MusicTrack.class);
        verify(trackRepository).save(trackCaptor.capture());
        MusicTrack saved = trackCaptor.getValue();
        assertThat(saved.getTitle()).isEqualTo("Night Drive");
        assertThat(saved.getArtistName()).isEqualTo("Omni Band");
        assertThat(saved.getAlbumTitle()).isEqualTo("City Lights");
        assertThat(saved.getLyricsRaw()).isEqualTo("[00:01.00]Rolling");
        // 内嵌封面改为派生资产：列表响应只剩稳定 API 路径，内联字节不再随曲目标进出。
        assertThat(saved.getCoverFileId()).isEqualTo(coverFileId);
        assertThat(saved.getProviderMetadata()).doesNotContainKey("coverDataUrl");
        assertThat(storedCover.get()).containsExactly(1, 2, 3, 4);
        assertThat(saved.getMetadataStatus()).isEqualTo("MATCHED");
    }

    @Test
    void executeScanJobKeepsInlineCoverWhenAssetStorageFails() throws Exception {
        FileDescriptor audio = fileNode(
                AUDIO_FILE_ID, "fallback.mp3", "audio/mpeg", 12_000_000L,
                UUID.fromString("30000000-0000-0000-0000-000000000001"));
        stubScanJob();
        stubMusicPersistence();
        when(fileMetadataQueryService.listOwnedActive(OWNER_ID)).thenReturn(List.of(audio));
        when(fileMetadataQueryService.listSharedVisibleToUser(OWNER_ID)).thenReturn(List.of());
        when(trackRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, AUDIO_FILE_ID)).thenReturn(Optional.empty());
        byte[] audioBytes = id3Tag(
                textFrame("TIT2", "Night Drive"),
                attachedPictureFrame("image/png", new byte[] {1, 2, 3, 4})
        );
        when(fileQueryService.openOwnedFileContent(OWNER_ID, AUDIO_FILE_ID))
                .thenReturn(content("fallback.mp3", "audio/mpeg", audioBytes));
        when(derivedAssetStorageService.store(
                any(), any(), any(), any(), any(), any(), any(Path.class)))
                .thenThrow(new IllegalStateException("对象存储不可用"));

        adminService.executeScanJob(SCAN_JOB_ID, OWNER_ID);

        // 资产化失败必须回落到内联地址，不能让曲目失去封面。
        var trackCaptor = ArgumentCaptor.forClass(MusicTrack.class);
        verify(trackRepository).save(trackCaptor.capture());
        MusicTrack saved = trackCaptor.getValue();
        assertThat(saved.getCoverFileId()).isNull();
        assertThat(saved.getProviderMetadata()).containsEntry("coverDataUrl", "data:image/png;base64,AQIDBA==");
    }

    @Test
    void executeScanJobUsesSidecarLrcWhenAudioHasNoEmbeddedLyrics() {
        UUID audioObjectId = UUID.fromString("30000000-0000-0000-0000-000000000002");
        UUID lyricFileId = UUID.fromString("20000000-0000-0000-0000-000000000003");
        UUID lyricObjectId = UUID.fromString("30000000-0000-0000-0000-000000000003");
        FileDescriptor audio = fileNode(
                AUDIO_FILE_ID, "Night Drive.mp3", "audio/mpeg", 12_000_000L, audioObjectId);
        FileDescriptor lyric = fileNode(
                lyricFileId, "Night Drive.lrc", "text/plain", 128L, lyricObjectId);
        stubScanJob();
        stubMusicPersistence();
        when(fileMetadataQueryService.listOwnedActive(OWNER_ID)).thenReturn(List.of(audio, lyric));
        when(fileMetadataQueryService.listSharedVisibleToUser(OWNER_ID)).thenReturn(List.of());
        when(trackRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, AUDIO_FILE_ID)).thenReturn(Optional.empty());
        when(fileQueryService.openOwnedFileContent(OWNER_ID, AUDIO_FILE_ID))
                .thenReturn(content("Night Drive.mp3", "audio/mpeg", new byte[] {0, 1, 2}));
        when(fileQueryService.openOwnedFileContent(OWNER_ID, lyricFileId))
                .thenReturn(content(
                        "Night Drive.lrc",
                        "text/plain",
                        "[00:02.00]Sidecar lyric".getBytes(StandardCharsets.UTF_8)
                ));

        adminService.executeScanJob(SCAN_JOB_ID, OWNER_ID);

        var trackCaptor = ArgumentCaptor.forClass(MusicTrack.class);
        verify(trackRepository).save(trackCaptor.capture());
        assertThat(trackCaptor.getValue().getLyricsRaw()).isEqualTo("[00:02.00]Sidecar lyric");
    }

    private void stubScanJob() {
        MusicScanJob job = new MusicScanJob();
        job.setId(SCAN_JOB_ID);
        job.setOwnerUserId(OWNER_ID);
        job.setStatus("QUEUED");
        when(scanJobRepository.findById(SCAN_JOB_ID)).thenReturn(Optional.of(job));
        when(scanJobRepository.save(any(MusicScanJob.class))).thenAnswer(invocation -> invocation.getArgument(0));
    }

    private void stubMusicPersistence() {
        when(albumRepository.save(any())).thenAnswer(invocation -> {
            MusicAlbum album = invocation.getArgument(0);
            if (album.getId() == null) {
                album.setId(UUID.fromString("50000000-0000-0000-0000-000000000001"));
            }
            return album;
        });
        when(artistRepository.save(any())).thenAnswer(invocation -> {
            MusicArtist artist = invocation.getArgument(0);
            if (artist.getId() == null) {
                artist.setId(UUID.fromString("60000000-0000-0000-0000-000000000001"));
            }
            return artist;
        });
        when(trackRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
    }

    private FileDescriptor fileNode(UUID id, String name, String mimeType, long sizeBytes) {
        return fileNode(id, name, mimeType, sizeBytes, null);
    }

    private FileDescriptor fileNode(
            UUID id,
            String name,
            String mimeType,
            long sizeBytes,
            UUID currentObjectId) {
        return new FileDescriptor(
                id,
                OWNER_ID,
                null,
                "FILE",
                name,
                "/" + name,
                mimeType,
                sizeBytes,
                currentObjectId,
                "UPLOAD",
                false,
                false,
                SpaceType.PERSONAL,
                OWNER_ID,
                null,
                null
        );
    }

    private FileContentStream content(String fileName, String mimeType, byte[] bytes) {
        return new FileContentStream(
                new ByteArrayInputStream(bytes),
                fileName,
                bytes.length,
                mimeType
        );
    }

    private byte[] id3Tag(byte[]... frames) throws Exception {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        for (byte[] frame : frames) {
            body.write(frame);
        }
        byte[] bodyBytes = body.toByteArray();
        ByteArrayOutputStream tag = new ByteArrayOutputStream();
        tag.write("ID3".getBytes(StandardCharsets.ISO_8859_1));
        tag.write(new byte[] {3, 0, 0});
        tag.write(synchsafe(bodyBytes.length));
        tag.write(bodyBytes);
        return tag.toByteArray();
    }

    private byte[] textFrame(String id, String value) throws Exception {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        body.write(3);
        body.write(value.getBytes(StandardCharsets.UTF_8));
        return frame(id, body.toByteArray());
    }

    private byte[] unsynchronizedLyricsFrame(String language, String description, String text) throws Exception {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        body.write(3);
        body.write(language.getBytes(StandardCharsets.ISO_8859_1));
        body.write(description.getBytes(StandardCharsets.UTF_8));
        body.write(0);
        body.write(text.getBytes(StandardCharsets.UTF_8));
        return frame("USLT", body.toByteArray());
    }

    private byte[] attachedPictureFrame(String mimeType, byte[] imageBytes) throws Exception {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        body.write(3);
        body.write(mimeType.getBytes(StandardCharsets.ISO_8859_1));
        body.write(0);
        body.write(3);
        body.write(0);
        body.write(imageBytes);
        return frame("APIC", body.toByteArray());
    }

    private byte[] frame(String id, byte[] body) throws Exception {
        ByteArrayOutputStream frame = new ByteArrayOutputStream();
        frame.write(id.getBytes(StandardCharsets.ISO_8859_1));
        frame.write(new byte[] {
                (byte) ((body.length >>> 24) & 0xFF),
                (byte) ((body.length >>> 16) & 0xFF),
                (byte) ((body.length >>> 8) & 0xFF),
                (byte) (body.length & 0xFF)
        });
        frame.write(new byte[] {0, 0});
        frame.write(body);
        return frame.toByteArray();
    }

    private byte[] synchsafe(int value) {
        return new byte[] {
                (byte) ((value >>> 21) & 0x7F),
                (byte) ((value >>> 14) & 0x7F),
                (byte) ((value >>> 7) & 0x7F),
                (byte) (value & 0x7F)
        };
    }
}
