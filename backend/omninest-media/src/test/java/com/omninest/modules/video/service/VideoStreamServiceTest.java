package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.video.config.VideoStreamProperties;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.io.ByteArrayOutputStream;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * VideoStreamService 单元测试。
 *
 * @author OmniNest
 */
class VideoStreamServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID VIDEO_ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final MediaVideoItemRepository videoItemRepository =
            mock(MediaVideoItemRepository.class);
    private final VideoSourceInputResolver sourceInputResolver = mock(VideoSourceInputResolver.class);
    private final MediaContentAccessService mediaContentAccessService = mock(MediaContentAccessService.class);
    private final VideoFfmpegRuntime ffmpegRuntime = mock(VideoFfmpegRuntime.class);
    private final VideoProcessExecutor processExecutor = mock(VideoProcessExecutor.class);

    private final VideoStreamService service = new VideoStreamService(
            videoItemRepository,
            sourceInputResolver,
            mediaContentAccessService,
            new VideoStreamProperties(),
            ffmpegRuntime,
            processExecutor
    );

    @Test
    void needsTranscode_returnsTrueForUnsupportedCodec() {
        // ac3 编码在 WEB_UNSUPPORTED_AUDIO 列表中
        MediaVideoItem item = new MediaVideoItem();
        item.setId(VIDEO_ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setAudioCodec("ac3");

        when(mediaContentAccessService.findReadableVideo(OWNER_ID, VIDEO_ITEM_ID))
                .thenReturn(Optional.of(item));

        boolean result = service.needsTranscode(OWNER_ID, VIDEO_ITEM_ID);

        assertThat(result).isTrue();
    }

    @Test
    void needsTranscode_returnsFalseForSupportedCodec() {
        // aac 编码不在 WEB_UNSUPPORTED_AUDIO 列表中
        MediaVideoItem item = new MediaVideoItem();
        item.setId(VIDEO_ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setAudioCodec("aac");

        when(mediaContentAccessService.findReadableVideo(OWNER_ID, VIDEO_ITEM_ID))
                .thenReturn(Optional.of(item));

        boolean result = service.needsTranscode(OWNER_ID, VIDEO_ITEM_ID);

        assertThat(result).isFalse();
    }

    @Test
    void needsTranscode_returnsFalseWhenItemNotFound() {
        // 视频条目不存在时返回 false
        when(mediaContentAccessService.findReadableVideo(OWNER_ID, VIDEO_ITEM_ID))
                .thenReturn(Optional.empty());

        boolean result = service.needsTranscode(OWNER_ID, VIDEO_ITEM_ID);

        assertThat(result).isFalse();
    }

    @Test
    void streamByAudioMode_usesCachedAudioWhenAvailable() {
        UUID audioFileNodeId = UUID.randomUUID();
        MediaVideoItem item = new MediaVideoItem();
        item.setId(VIDEO_ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        when(mediaContentAccessService.requireReadableVideo(OWNER_ID, VIDEO_ITEM_ID)).thenReturn(item);
        MediaVideoItem cachedAudio = new MediaVideoItem();
        cachedAudio.setFileNodeId(audioFileNodeId);
        when(videoItemRepository.findByOwnerUserIdAndSourceVideoItemIdAndVersionLabel(
                OWNER_ID,
                VIDEO_ITEM_ID,
                "AUDIO_ONLY"
        )).thenReturn(Optional.of(cachedAudio));
        VideoStreamService spyService = spy(service);
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        doNothing().when(spyService).streamWithCachedAudio(
                OWNER_ID,
                VIDEO_ITEM_ID,
                audioFileNodeId,
                12L,
                output
        );

        spyService.streamByAudioMode(OWNER_ID, VIDEO_ITEM_ID, 12L, "cached", output);

        verify(spyService).streamWithCachedAudio(
                OWNER_ID,
                VIDEO_ITEM_ID,
                audioFileNodeId,
                12L,
                output
        );
    }

    @Test
    void streamByAudioModeResolvesCachedAudioUnderCatalogOwnerForSharedLibrary() {
        UUID requester = UUID.randomUUID();
        UUID catalogOwner = UUID.randomUUID();
        UUID audioFileNodeId = UUID.randomUUID();
        MediaVideoItem item = new MediaVideoItem();
        item.setId(VIDEO_ITEM_ID);
        item.setOwnerUserId(catalogOwner);
        item.setLibrarySourceId(UUID.randomUUID());
        when(mediaContentAccessService.requireReadableVideo(requester, VIDEO_ITEM_ID)).thenReturn(item);
        MediaVideoItem cachedAudio = new MediaVideoItem();
        cachedAudio.setFileNodeId(audioFileNodeId);
        when(videoItemRepository.findByOwnerUserIdAndSourceVideoItemIdAndVersionLabel(
                catalogOwner,
                VIDEO_ITEM_ID,
                "AUDIO_ONLY"
        )).thenReturn(Optional.of(cachedAudio));
        VideoStreamService spyService = spy(service);
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        doNothing().when(spyService).streamWithCachedAudio(
                catalogOwner,
                VIDEO_ITEM_ID,
                audioFileNodeId,
                0L,
                output
        );

        spyService.streamByAudioMode(requester, VIDEO_ITEM_ID, 0L, "cached", output);

        // 播放计划按源条目所有者宣告缓存，流端点必须用同一把钥匙查
        verify(spyService).streamWithCachedAudio(
                catalogOwner,
                VIDEO_ITEM_ID,
                audioFileNodeId,
                0L,
                output
        );
    }

    @Test
    void streamAudioTranscodedRejectsPlaylistContainerBeforeStartingFfmpeg() {
        MediaVideoItem item = new MediaVideoItem();
        item.setId(VIDEO_ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setContainerFormat("hls");
        when(mediaContentAccessService.requireReadableVideo(OWNER_ID, VIDEO_ITEM_ID)).thenReturn(item);

        assertThatThrownBy(() -> service.streamAudioTranscoded(
                OWNER_ID, VIDEO_ITEM_ID, 0L, new ByteArrayOutputStream()))
                .isInstanceOfSatisfying(BusinessException.class,
                        exception -> assertThat(exception.errorCode()).isEqualTo(ErrorCode.MEDIA_FORMAT_UNSUPPORTED));
    }

    @Test
    void transcodeArgsForceDemuxerBeforeInput() {
        List<String> args = service.buildTranscodeArgs("mov", "http://minio/movie.mp4", 12L);

        assertThat(args).containsSubsequence("-ss", "12", "-f", "mov", "-i", "http://minio/movie.mp4");
    }

    @Test
    void cachedAudioArgsForceAacDemuxerForDerivedAudio() {
        List<String> args = service.buildCachedAudioArgs(
                "matroska", "http://minio/movie.mkv", "http://minio/audio.aac", 0L);

        assertThat(args).containsSubsequence(
                "-f", "matroska", "-i", "http://minio/movie.mkv",
                "-f", "aac", "-i", "http://minio/audio.aac");
    }

    @Test
    void streamCommandAppliesProtocolWhitelistInDockerMode() {
        when(ffmpegRuntime.isDisabled()).thenReturn(false);
        when(ffmpegRuntime.isDocker()).thenReturn(true);
        when(ffmpegRuntime.newMarker()).thenReturn("marker");
        when(ffmpegRuntime.dockerStreamCommand(anyString(), anyList()))
                .thenReturn(List.of("docker", "exec", "omninest-ffmpeg", "ffmpeg"));

        service.buildStreamCommand(
                List.of("-i", "http://minio/movie.mp4"),
                List.of("http://minio/movie.mp4")
        );

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<String>> argsCaptor = ArgumentCaptor.forClass(List.class);
        verify(ffmpegRuntime).dockerStreamCommand(anyString(), argsCaptor.capture());
        assertThat(argsCaptor.getValue()).containsSubsequence(
                "-protocol_whitelist", "http,https,tcp,tls", "-i", "http://minio/movie.mp4");
    }
}
