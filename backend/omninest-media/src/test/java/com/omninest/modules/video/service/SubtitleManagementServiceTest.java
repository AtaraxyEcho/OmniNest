package com.omninest.modules.video.service;

import org.mockito.ArgumentCaptor;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.video.domain.MediaSubtitleTrack;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.SubtitleTrackDto;
import com.omninest.modules.video.dto.MovieDtos.SubtitleUploadRequest;
import com.omninest.modules.video.repository.MediaSubtitleTrackRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;

/**
 * SubtitleManagementService 单元测试。
 * 覆盖字幕列表查询和字幕上传功能。
 */
class SubtitleManagementServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID VIDEO_ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SUBTITLE_TRACK_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private MediaSubtitleTrackRepository subtitleTrackRepository;
    private MediaVideoItemRepository videoItemRepository;
    private FileLifecycleGuard fileLifecycleGuard;
    private FileQueryService fileQueryService;
    private MediaContentAccessService mediaContentAccessService;
    private MediaPlaybackTokenService mediaPlaybackTokenService;
    private MediaSyncEventService syncEventService;

    private SubtitleManagementService service;

    @BeforeEach
    void setUp() {
        subtitleTrackRepository = mock(MediaSubtitleTrackRepository.class);
        videoItemRepository = mock(MediaVideoItemRepository.class);
        fileLifecycleGuard = mock(FileLifecycleGuard.class);
        fileQueryService = mock(FileQueryService.class);
        mediaContentAccessService = mock(MediaContentAccessService.class);
        mediaPlaybackTokenService = mock(MediaPlaybackTokenService.class);
        syncEventService = mock(MediaSyncEventService.class);

        service = new SubtitleManagementService(
                subtitleTrackRepository,
                videoItemRepository,
                fileLifecycleGuard,
                fileQueryService,
                mediaContentAccessService,
                mediaPlaybackTokenService,
                syncEventService
        );
        when(fileLifecycleGuard.requireOwnedWritable(OWNER_ID, FILE_NODE_ID))
                .thenReturn(subtitleFile("subtitle.srt", "application/x-subrip", 1024));
        when(fileQueryService.createDownloadUrl(OWNER_ID, FILE_NODE_ID))
                .thenReturn(new FileDownloadUrlDto(
                        FILE_NODE_ID,
                        "subtitle.srt",
                        "https://storage.example/subtitle.srt",
                        Instant.now().plusSeconds(900)
                ));
    }

    @Test
    void listSubtitles_returnsTracksForItem() {
        // 验证 list 方法返回指定视频条目的所有字幕轨道
        MediaVideoItem videoItem = videoItem();
        MediaSubtitleTrack track = subtitleTrack(SUBTITLE_TRACK_ID, "zh", "中文字幕", 1);

        when(mediaContentAccessService.requireReadableVideo(OWNER_ID, VIDEO_ITEM_ID)).thenReturn(videoItem);
        when(mediaPlaybackTokenService.issue(OWNER_ID, VIDEO_ITEM_ID)).thenReturn(
                new MediaPlaybackTokenService.IssuedMediaToken("media-token", Instant.now().plusSeconds(900))
        );
        when(subtitleTrackRepository.findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(OWNER_ID, VIDEO_ITEM_ID))
                .thenReturn(List.of(track));
        List<SubtitleTrackDto> result = service.list(OWNER_ID, VIDEO_ITEM_ID);

        // 验证返回一条字幕轨道
        assertThat(result).hasSize(1);
        SubtitleTrackDto dto = result.getFirst();
        assertThat(dto.id()).isEqualTo(SUBTITLE_TRACK_ID);
        assertThat(dto.language()).isEqualTo("zh");
        assertThat(dto.label()).isEqualTo("中文字幕");
        assertThat(dto.kind()).isEqualTo("SUBTITLE");
        assertThat(dto.embedded()).isFalse();
        assertThat(dto.url()).isEqualTo(
                "/api/v1/public/video/items/" + VIDEO_ITEM_ID + "/subtitles/" + SUBTITLE_TRACK_ID
                        + "?token=media-token"
        );
    }

    @Test
    void uploadSubtitle_createsNewTrack() {
        // 验证上传字幕后创建新的字幕轨道，排序号递增
        MediaVideoItem videoItem = videoItem();
        MediaSubtitleTrack existingTrack = subtitleTrack(UUID.randomUUID(), "en", "English", 1);

        when(videoItemRepository.findByIdAndOwnerUserId(VIDEO_ITEM_ID, OWNER_ID))
                .thenReturn(Optional.of(videoItem));
        when(subtitleTrackRepository.findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(OWNER_ID, VIDEO_ITEM_ID))
                .thenReturn(List.of(existingTrack));
        when(subtitleTrackRepository.save(any())).thenAnswer(invocation -> {
            MediaSubtitleTrack track = invocation.getArgument(0);
            track.setId(UUID.randomUUID());
            return track;
        });

        SubtitleUploadRequest request = new SubtitleUploadRequest(
                FILE_NODE_ID,
                "ja",
                "日本語字幕",
                "SUBTITLE"
        );

        SubtitleTrackDto result = service.upload(OWNER_ID, VIDEO_ITEM_ID, request);

        // 验证返回的 DTO 属性
        assertThat(result.language()).isEqualTo("ja");
        assertThat(result.label()).isEqualTo("日本語字幕");
        assertThat(result.kind()).isEqualTo("SUBTITLE");

        // 验证保存的实体属性
        ArgumentCaptor<MediaSubtitleTrack> captor =
                ArgumentCaptor.forClass(MediaSubtitleTrack.class);
        verify(subtitleTrackRepository).save(captor.capture());
        MediaSubtitleTrack saved = captor.getValue();
        assertThat(saved.getOwnerUserId()).isEqualTo(OWNER_ID);
        assertThat(saved.getVideoItemId()).isEqualTo(VIDEO_ITEM_ID);
        assertThat(saved.getFileNodeId()).isEqualTo(FILE_NODE_ID);
        assertThat(saved.getLanguage()).isEqualTo("ja");
        assertThat(saved.getLabel()).isEqualTo("日本語字幕");
        assertThat(saved.getSortOrder()).isEqualTo(2);

        // 上传成功后按所属影片发出 VIDEO 作用域失效事件。
        verify(syncEventService).record(
                eq(OWNER_ID),
                eq(SyncScope.VIDEO),
                eq("VIDEO_ITEM"),
                eq(VIDEO_ITEM_ID.toString()),
                eq(SyncAction.UPDATED),
                isNull(),
                anyMap()
        );
    }

    @Test
    void deleteSubtitle_emitsVideoItemEventWithVideoItemId() {
        MediaSubtitleTrack track = subtitleTrack(SUBTITLE_TRACK_ID, "zh", "中文字幕", 1);
        when(subtitleTrackRepository.findById(SUBTITLE_TRACK_ID)).thenReturn(Optional.of(track));

        service.delete(OWNER_ID, SUBTITLE_TRACK_ID);

        verify(subtitleTrackRepository).delete(track);
        verify(syncEventService).record(
                eq(OWNER_ID),
                eq(SyncScope.VIDEO),
                eq("VIDEO_ITEM"),
                eq(VIDEO_ITEM_ID.toString()),
                eq(SyncAction.UPDATED),
                isNull(),
                anyMap()
        );
    }

    @Test
    void listSubtitles_throwsWhenVideoItemNotFound() {
        // 验证视频条目不存在时抛出异常
        when(mediaContentAccessService.requireReadableVideo(OWNER_ID, VIDEO_ITEM_ID))
                .thenThrow(new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在"));

        assertThatThrownBy(() -> service.list(OWNER_ID, VIDEO_ITEM_ID))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("媒体资源不存在");
    }

    @Test
    void uploadSubtitle_usesDefaultValuesWhenFieldsNull() {
        // 验证上传时未指定语言和标签使用默认值
        MediaVideoItem videoItem = videoItem();

        when(videoItemRepository.findByIdAndOwnerUserId(VIDEO_ITEM_ID, OWNER_ID))
                .thenReturn(Optional.of(videoItem));
        when(subtitleTrackRepository.findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(OWNER_ID, VIDEO_ITEM_ID))
                .thenReturn(List.of());
        when(subtitleTrackRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        SubtitleUploadRequest request = new SubtitleUploadRequest(FILE_NODE_ID, null, null, null);

        SubtitleTrackDto result = service.upload(OWNER_ID, VIDEO_ITEM_ID, request);

        // 验证默认值
        assertThat(result.language()).isEqualTo("und");
        assertThat(result.label()).isEqualTo("字幕");
        assertThat(result.kind()).isEqualTo("SUBTITLE");
    }

    @Test
    void uploadSubtitle_rejectsFileNotOwnedByCurrentUser() {
        when(videoItemRepository.findByIdAndOwnerUserId(VIDEO_ITEM_ID, OWNER_ID))
                .thenReturn(Optional.of(videoItem()));
        when(fileLifecycleGuard.requireOwnedWritable(OWNER_ID, FILE_NODE_ID))
                .thenThrow(new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));

        SubtitleUploadRequest request = new SubtitleUploadRequest(FILE_NODE_ID, "zh", "字幕", "SUBTITLE");

        assertThatThrownBy(() -> service.upload(OWNER_ID, VIDEO_ITEM_ID, request))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("文件不存在");
    }

    @Test
    void uploadSubtitle_rejectsUnsupportedFileType() {
        when(videoItemRepository.findByIdAndOwnerUserId(VIDEO_ITEM_ID, OWNER_ID))
                .thenReturn(Optional.of(videoItem()));
        when(fileLifecycleGuard.requireOwnedWritable(OWNER_ID, FILE_NODE_ID))
                .thenReturn(subtitleFile("payload.exe", "application/octet-stream", 1024));

        SubtitleUploadRequest request = new SubtitleUploadRequest(FILE_NODE_ID, "zh", "字幕", "SUBTITLE");

        assertThatThrownBy(() -> service.upload(OWNER_ID, VIDEO_ITEM_ID, request))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("格式不受支持");
    }

    // ── 辅助方法 ──

    private MediaVideoItem videoItem() {
        MediaVideoItem item = new MediaVideoItem();
        item.setId(VIDEO_ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(UUID.fromString("30000000-0000-0000-0000-000000000010"));
        item.setMediaType("MOVIE");
        item.setMetadataStatus("MATCHED");
        item.setCreatedAt(Instant.parse("2026-01-01T00:00:00Z"));
        item.setUpdatedAt(Instant.parse("2026-05-01T00:00:00Z"));
        return item;
    }

    private MediaSubtitleTrack subtitleTrack(UUID id, String language, String label, int sortOrder) {
        MediaSubtitleTrack track = new MediaSubtitleTrack();
        track.setId(id);
        track.setOwnerUserId(OWNER_ID);
        track.setVideoItemId(VIDEO_ITEM_ID);
        track.setFileNodeId(FILE_NODE_ID);
        track.setLanguage(language);
        track.setLabel(label);
        track.setTrackKind("SUBTITLE");
        track.setSortOrder(sortOrder);
        track.setCreatedAt(Instant.parse("2026-01-01T00:00:00Z"));
        return track;
    }

    private FileDescriptor subtitleFile(String fileName, String mimeType, long sizeBytes) {
        return new FileDescriptor(
                FILE_NODE_ID,
                OWNER_ID,
                null,
                "FILE",
                fileName,
                "/" + fileName,
                mimeType,
                sizeBytes,
                UUID.randomUUID(),
                "UPLOAD",
                false,
                false,
                SpaceType.PERSONAL,
                OWNER_ID,
                Instant.now(),
                Instant.now()
        );
    }
}
