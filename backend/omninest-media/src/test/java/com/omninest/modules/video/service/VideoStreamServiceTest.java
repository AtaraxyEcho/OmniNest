package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.io.ByteArrayOutputStream;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

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

    private final VideoStreamService service = new VideoStreamService(
            videoItemRepository, sourceInputResolver, mediaContentAccessService
    );

    @Test
    void needsTranscode_returnsTrueForUnsupportedCodec() {
        // ac3 编码在 WEB_UNSUPPORTED_AUDIO 列表中
        MediaVideoItem item = new MediaVideoItem();
        item.setId(VIDEO_ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setAudioCodec("ac3");

        when(videoItemRepository.findByIdAndOwnerUserId(VIDEO_ITEM_ID, OWNER_ID))
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

        when(videoItemRepository.findByIdAndOwnerUserId(VIDEO_ITEM_ID, OWNER_ID))
                .thenReturn(Optional.of(item));

        boolean result = service.needsTranscode(OWNER_ID, VIDEO_ITEM_ID);

        assertThat(result).isFalse();
    }

    @Test
    void needsTranscode_returnsFalseWhenItemNotFound() {
        // 视频条目不存在时返回 false
        when(videoItemRepository.findByIdAndOwnerUserId(VIDEO_ITEM_ID, OWNER_ID))
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
}
