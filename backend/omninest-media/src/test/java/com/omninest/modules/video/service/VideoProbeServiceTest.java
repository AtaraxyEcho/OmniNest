package com.omninest.modules.video.service;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaSubtitleTrack;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.event.VideoSubtitleExtractEvent;
import com.omninest.modules.video.repository.MediaSubtitleTrackRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;

/**
 * 视频探测服务边界行为测试。
 *
 * @author OmniNest
 */
class VideoProbeServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final MediaVideoItemRepository videoItemRepository = mock(MediaVideoItemRepository.class);
    private final MediaSubtitleTrackRepository subtitleTrackRepository = mock(MediaSubtitleTrackRepository.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final MovieTaskService movieTaskService = mock(MovieTaskService.class);
    private final MediaRuntimeConfigService mediaRuntimeConfigService = mock(MediaRuntimeConfigService.class);
    private final VideoTranscodeService videoTranscodeService = mock(VideoTranscodeService.class);
    private final VideoProcessExecutor processExecutor = mock(VideoProcessExecutor.class);
    private final DerivedAssetStorageService derivedAssetStorageService = mock(DerivedAssetStorageService.class);
    private final PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
    private final ApplicationEventPublisher applicationEventPublisher = mock(ApplicationEventPublisher.class);
    private final VideoProbeService service = new VideoProbeService(
            fileQueryService,
            videoItemRepository,
            subtitleTrackRepository,
            taskRecordService,
            movieTaskService,
            mediaRuntimeConfigService,
            videoTranscodeService,
            processExecutor,
            derivedAssetStorageService,
            transactionManager,
            applicationEventPublisher,
            mock(MediaLibraryAccessService.class)
    );

    /** 模拟字幕轨道表存储内容，供多次探测间断言行 id 稳定。 */
    private final List<MediaSubtitleTrack> trackStore = new ArrayList<>();

    @BeforeEach
    void setUpRepositoryStubs() {
        when(subtitleTrackRepository.findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(OWNER_ID, ITEM_ID))
                .thenAnswer(invocation -> List.copyOf(trackStore));
        when(subtitleTrackRepository.saveAll(any())).thenAnswer(invocation -> {
            List<MediaSubtitleTrack> incoming = invocation.getArgument(0);
            for (MediaSubtitleTrack track : incoming) {
                trackStore.removeIf(existing -> existing.getId().equals(track.getId()));
                trackStore.add(track);
            }
            return incoming;
        });
        doAnswer(invocation -> {
            List<UUID> ids = invocation.getArgument(1);
            trackStore.removeIf(existing -> ids.contains(existing.getId()));
            return null;
        }).when(subtitleTrackRepository).deleteAllByIdIn(eq(OWNER_ID), any());
        when(transactionManager.getTransaction(any())).thenReturn(mock(TransactionStatus.class));
        when(videoItemRepository.save(any(MediaVideoItem.class))).thenAnswer(invocation -> invocation.getArgument(0));
    }

    @Test
    void shouldStopCopyingAtConfiguredByteLimit() throws Exception {
        byte[] source = new byte[32];
        Arrays.fill(source, (byte) 7);
        ByteArrayOutputStream output = new ByteArrayOutputStream();

        long copied = VideoProbeService.copyAtMost(
                new ByteArrayInputStream(source),
                output,
                12
        );

        assertEquals(12, copied);
        assertArrayEquals(Arrays.copyOf(source, 12), output.toByteArray());
    }

    @Test
    void reprobeWithSameStreamsKeepsSubtitleRowIdsWithoutExtraRows() throws Exception {
        enableLocalProbe();
        stubProbeOutput(SINGLE_SUBTITLE_PROBE_JSON, SINGLE_SUBTITLE_PROBE_JSON);
        stubContentReadable();
        MediaVideoItem item = videoItem();
        when(videoItemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));

        service.probe(item);
        assertEquals(1, trackStore.size());
        UUID firstId = trackStore.get(0).getId();

        service.probe(item);

        // 修复前每次重探测都插入全新行，字幕列表按探测次数翻倍并触发全量重提取。
        assertEquals(1, trackStore.size());
        assertEquals(firstId, trackStore.get(0).getId());
        verify(subtitleTrackRepository, never()).deleteAllByIdIn(any(), any());
    }

    @Test
    void reprobeWithDisappearedStreamBulkDeletesStaleRow() throws Exception {
        enableLocalProbe();
        stubProbeOutput(TWO_SUBTITLE_PROBE_JSON, SINGLE_SUBTITLE_PROBE_JSON);
        stubContentReadable();
        MediaVideoItem item = videoItem();

        service.probe(item);
        assertEquals(2, trackStore.size());

        service.probe(item);

        assertEquals(1, trackStore.size());
        verify(subtitleTrackRepository).deleteAllByIdIn(eq(OWNER_ID), argThat(ids -> ids.size() == 1));
    }

    @Test
    void probeByVideoItemIdDelegatesSubtitleExtractionToAsyncPath() throws Exception {
        MediaVideoItem item = videoItem();
        when(videoItemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        // 探测片段读取失败时 probe 内部降级返回，不影响提取事件发布断言。
        when(fileQueryService.openOwnedFileContent(OWNER_ID, FILE_NODE_ID))
                .thenThrow(new IllegalStateException("内容不可读"));

        service.probeByVideoItemId(OWNER_ID, ITEM_ID);

        // 修复前在请求线程内同步逐轨提取（每轨一路 ffmpeg 容器，上限 180 分钟）。
        verify(videoTranscodeService, never()).extractSubtitleToWebVtt(any(), any(), any(), anyInt());
        ArgumentCaptor<Object> eventCaptor = ArgumentCaptor.forClass(Object.class);
        verify(applicationEventPublisher).publishEvent(eventCaptor.capture());
        assertEquals(VideoSubtitleExtractEvent.class, eventCaptor.getValue().getClass());

        // 异步监听器本体仍完成提取：直接调用方法体验证，绕过 @Async 代理。
        trackStore.add(embeddedTrack(3, 1));
        when(videoTranscodeService.extractSubtitleToWebVtt(OWNER_ID, FILE_NODE_ID, ITEM_ID, 3))
                .thenThrow(new IllegalStateException("容器不可用"));
        service.onSubtitleExtractRequest(new VideoSubtitleExtractEvent(item));
        verify(videoTranscodeService).extractSubtitleToWebVtt(OWNER_ID, FILE_NODE_ID, ITEM_ID, 3);
    }

    private void enableLocalProbe() throws Exception {
        when(processExecutor.execute(eq(List.of("ffprobe", "-version")), any()))
                .thenReturn(new VideoProcessExecutor.Result(0, "", false, false));
        service.checkFfprobe();
    }

    private void stubProbeOutput(String firstJson, String secondJson) throws Exception {
        when(processExecutor.execute(
                argThat(command -> command != null && command.contains("-show_streams")),
                any()
        )).thenReturn(
                new VideoProcessExecutor.Result(0, firstJson, false, false),
                new VideoProcessExecutor.Result(0, secondJson, false, false)
        );
    }

    private void stubContentReadable() {
        when(fileQueryService.openOwnedFileContent(OWNER_ID, FILE_NODE_ID)).thenReturn(
                new FileContentStream(
                        new ByteArrayInputStream("video-bytes".getBytes()),
                        "movie.mkv",
                        11,
                        "video/x-matroska"
                )
        );
    }

    private MediaVideoItem videoItem() {
        MediaVideoItem item = new MediaVideoItem();
        item.setId(ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(FILE_NODE_ID);
        return item;
    }

    private MediaSubtitleTrack embeddedTrack(int streamIndex, int sortOrder) {
        MediaSubtitleTrack track = new MediaSubtitleTrack();
        track.setId(UUID.randomUUID());
        track.setOwnerUserId(OWNER_ID);
        track.setVideoItemId(ITEM_ID);
        track.setTrackKind("SUBTITLE");
        track.setStreamIndex(streamIndex);
        track.setSortOrder(sortOrder);
        track.setLanguage("chi");
        track.setLabel("中文");
        return track;
    }

    private static final String SINGLE_SUBTITLE_PROBE_JSON = """
            {"streams":[
              {"codec_type":"video","codec_name":"h264","width":1920,"height":1080},
              {"codec_type":"audio","codec_name":"aac"},
              {"codec_type":"subtitle","codec_name":"srt","tags":{"language":"chi","title":"简体中文"}}
            ],"format":{"format_name":"matroska","duration":"100.0"}}
            """;

    private static final String TWO_SUBTITLE_PROBE_JSON = """
            {"streams":[
              {"codec_type":"video","codec_name":"h264","width":1920,"height":1080},
              {"codec_type":"subtitle","codec_name":"srt","tags":{"language":"chi","title":"简体中文"}},
              {"codec_type":"subtitle","codec_name":"ass","tags":{"language":"eng","title":"English"}}
            ],"format":{"format_name":"matroska","duration":"100.0"}}
            """;
}
