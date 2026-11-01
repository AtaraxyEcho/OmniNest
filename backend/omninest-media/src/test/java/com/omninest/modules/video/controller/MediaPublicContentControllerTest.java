package com.omninest.modules.video.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.service.MediaContentAccessService;
import com.omninest.modules.video.service.MoviePlaybackService;
import com.omninest.modules.video.service.VideoStreamService;
import java.io.OutputStream;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletResponse;

/**
 * 转码流端点的槽位时序测试。
 *
 * <p>写死两条不变量：槽位取不到时必须在响应提交前失败（否则播放器收到标着
 * video/mp4 的损坏流），以及流式输出失败时槽位必须归还（否则实例的流通道会被
 * 逐次泄漏直到全部请求都拿不到槽位）。</p>
 *
 * @author OmniNest
 */
class MediaPublicContentControllerTest {

    private static final UUID VIDEO_ITEM_ID = UUID.fromString("10000000-0000-0000-0000-0000000000a1");
    private static final UUID OWNER_ID = UUID.fromString("20000000-0000-0000-0000-0000000000b2");
    private static final UUID REQUESTER_ID = UUID.fromString("30000000-0000-0000-0000-0000000000c3");
    private static final String TOKEN = "playback-token";

    private final MediaContentAccessService mediaContentAccessService = mock(MediaContentAccessService.class);
    private final MoviePlaybackService moviePlaybackService = mock(MoviePlaybackService.class);
    private final VideoStreamService videoStreamService = mock(VideoStreamService.class);
    private final MediaPublicContentController controller = new MediaPublicContentController(
            mediaContentAccessService, moviePlaybackService, videoStreamService);

    private MediaVideoItem item() {
        MediaVideoItem item = new MediaVideoItem();
        item.setId(VIDEO_ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        return item;
    }

    @Test
    @DisplayName("槽位已满：在固定 media 响应头之前失败，且不释放未占用的槽位")
    void streamFailsBeforeCommittingHeadersWhenSlotUnavailable() {
        when(mediaContentAccessService.requireTokenVideoAccess(TOKEN, VIDEO_ITEM_ID))
                .thenReturn(new MediaContentAccessService.TokenVideoAccess(item(), REQUESTER_ID));
        doThrow(new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "实时转码通道已满"))
                .when(videoStreamService).acquireStreamSlot(VIDEO_ITEM_ID);
        MockHttpServletResponse response = new MockHttpServletResponse();

        assertThatThrownBy(() -> controller.stream(VIDEO_ITEM_ID, TOKEN, 0, "cached", response))
                .isInstanceOf(BusinessException.class);

        assertThat(response.getContentType()).isNull();
        assertThat(response.getHeader("Transfer-Encoding")).isNull();
        verify(videoStreamService, never()).releaseStreamSlotForRequest();
    }

    @Test
    @DisplayName("流式输出失败：槽位仍然归还，不会逐次泄漏")
    void streamReleasesSlotWhenStreamingFails() {
        when(mediaContentAccessService.requireTokenVideoAccess(TOKEN, VIDEO_ITEM_ID))
                .thenReturn(new MediaContentAccessService.TokenVideoAccess(item(), REQUESTER_ID));
        MockHttpServletResponse response = new MockHttpServletResponse();
        IllegalStateException failure = new IllegalStateException("client disconnected");
        doThrow(failure).when(videoStreamService).streamByAudioMode(
                eq(OWNER_ID), eq(VIDEO_ITEM_ID), eq(REQUESTER_ID), anyLong(), any(), any(OutputStream.class), eq(true));

        assertThatThrownBy(() -> controller.stream(VIDEO_ITEM_ID, TOKEN, 0, "cached", response))
                .isSameAs(failure);

        verify(videoStreamService).acquireStreamSlot(VIDEO_ITEM_ID);
        verify(videoStreamService).releaseStreamSlotForRequest();
    }
}
