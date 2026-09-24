package com.omninest.app.music;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.omninest.common.security.CurrentUserContext;
import com.omninest.modules.music.controller.MusicController;
import com.omninest.modules.music.service.LrclibLyricsService;
import com.omninest.modules.music.service.MusicAdminService;
import com.omninest.modules.music.service.MusicCoverService.CoverStreamDescriptor;
import com.omninest.modules.music.service.MusicCoverService.ThumbnailFreshness;
import com.omninest.modules.music.service.MusicCoverService.ThumbnailStream;
import com.omninest.modules.music.service.MusicLibraryService;
import com.omninest.modules.music.service.MusicOnlineDispatcher;
import com.omninest.modules.music.service.MusicPlatformAccountService;
import com.omninest.modules.music.service.MusicPlatformService;
import com.omninest.modules.music.service.MusicPlaybackQueueService;
import com.omninest.modules.music.service.MusicPlaybackService;
import com.omninest.modules.music.service.MusicPlaylistService;
import com.omninest.modules.music.service.MusicScrapeService;
import com.omninest.modules.music.service.MusicStreamGatewayService;
import com.omninest.modules.music.service.MusicCoverService;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Supplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.security.web.header.HeaderWriterFilter;
import org.springframework.security.web.header.writers.CacheControlHeadersWriter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/**
 * 封面响应缓存头的契约测试。
 *
 * <p>Spring Security 的默认写头会在异步派发返回时补上 {@code no-cache, no-store}，
 * 业务侧随后追加的 Cache-Control 因此排在第二个值上；客户端按第一个取值判断有效期，
 * 稳定缩略图路径会退化成"每次重绘都重下"，同一份缓存文件被反复截断重写，封面无法显示。
 * 缩略图接口必须先把 Cache-Control 占住，再在派生完成后覆盖为真实新鲜度。</p>
 */
class MusicCoverCacheHeaderContractTest {

    private static final UUID OWNER = UUID.randomUUID();
    private static final UUID COVER_FILE_ID = UUID.randomUUID();
    private static final String IMMUTABLE = "private, max-age=2592000, immutable";
    private static final String SECURITY_DEFAULTS = "no-cache, no-store, max-age=0, must-revalidate";

    private final CurrentUserContext currentUserContext = mock(CurrentUserContext.class);
    private final MusicOnlineDispatcher onlineDispatcher = mock(MusicOnlineDispatcher.class);
    private final MusicCoverService musicCoverService = mock(MusicCoverService.class);

    /** 捕获待执行的派生任务，并延后到初始派发返回之后再产出响应。 */
    private final AtomicReference<Supplier<?>> pendingCall = new AtomicReference<>();
    private final CompletableFuture<Object> pendingResult = new CompletableFuture<>();

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        when(currentUserContext.requireCurrentUserId()).thenReturn(OWNER);
        doAnswer(invocation -> {
            pendingCall.set(invocation.getArgument(0));
            return pendingResult;
        })
                .when(onlineDispatcher)
                .supply(any());
        MusicController controller = new MusicController(
                currentUserContext,
                onlineDispatcher,
                mock(MusicLibraryService.class),
                mock(MusicPlaylistService.class),
                mock(MusicAdminService.class),
                musicCoverService,
                mock(MusicScrapeService.class),
                mock(MusicPlaybackService.class),
                mock(MusicPlaybackQueueService.class),
                mock(LrclibLyricsService.class),
                mock(MusicPlatformService.class),
                mock(MusicPlatformAccountService.class),
                mock(MusicStreamGatewayService.class)
        );
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
                .addFilters(new HeaderWriterFilter(List.of(new CacheControlHeadersWriter())))
                .build();
    }

    @Test
    void derivedThumbnailKeepsSingleImmutableCacheControl() throws Exception {
        stubThumbnail(ThumbnailFreshness.DERIVED);

        List<String> values = thumbnailCacheControl();

        assertThat(values).containsExactly(IMMUTABLE);
    }

    @Test
    void retryableThumbnailKeepsSingleShortCacheControl() throws Exception {
        stubThumbnail(ThumbnailFreshness.RETRY_SOON);

        List<String> values = thumbnailCacheControl();

        assertThat(values).containsExactly("private, max-age=60");
    }

    @Test
    void thumbnailResponseDoesNotInheritSecurityNoStoreDefaults() throws Exception {
        stubThumbnail(ThumbnailFreshness.DERIVED);

        MvcResult result = dispatchThumbnail();

        assertThat(result.getResponse().getHeader(HttpHeaders.PRAGMA)).isNull();
        assertThat(result.getResponse().getHeader(HttpHeaders.EXPIRES)).isNull();
    }

    @Test
    void synchronousCoverDownloadKeepsSingleImmutableCacheControl() throws Exception {
        when(musicCoverService.prepareCoverStream(OWNER, COVER_FILE_ID))
                .thenReturn(new CoverStreamDescriptor(OWNER, COVER_FILE_ID, "image/jpeg", 128L));

        MvcResult result = mockMvc.perform(get("/api/v1/music/covers/{fileId}", COVER_FILE_ID))
                .andExpect(status().isOk())
                .andReturn();

        assertThat(result.getResponse().getHeaders(HttpHeaders.CACHE_CONTROL)).containsExactly(IMMUTABLE);
    }

    @Test
    void asyncResponseWithoutPlaceholderIsPrefixedBySecurityDefaults() throws Exception {
        MockMvc probe = MockMvcBuilders.standaloneSetup(new AsyncProbeController())
                .addFilters(new HeaderWriterFilter(List.of(new CacheControlHeadersWriter())))
                .build();

        MvcResult started = probe.perform(get("/probe/async-cover")).andReturn();
        assertThat(started.getRequest().isAsyncStarted()).isTrue();
        MvcResult result = probe.perform(asyncDispatch(started)).andReturn();

        // 不占位时业务头只能追加在 Security 的 no-cache 之后，这正是缩略图缓存失效的成因。
        assertThat(result.getResponse().getHeaders(HttpHeaders.CACHE_CONTROL))
                .containsExactly(SECURITY_DEFAULTS, IMMUTABLE);
    }

    private void stubThumbnail(ThumbnailFreshness freshness) {
        when(musicCoverService.prepareThumbnailStream(OWNER, COVER_FILE_ID)).thenReturn(new ThumbnailStream(
                new CoverStreamDescriptor(OWNER, COVER_FILE_ID, "image/jpeg", 128L),
                freshness
        ));
    }

    private List<String> thumbnailCacheControl() throws Exception {
        MvcResult result = dispatchThumbnail();
        return result.getResponse().getHeaders(HttpHeaders.CACHE_CONTROL);
    }

    private MvcResult dispatchThumbnail() throws Exception {
        MvcResult started = mockMvc.perform(
                get("/api/v1/music/covers/{fileId}/thumbnail", COVER_FILE_ID)
        ).andReturn();
        assertThat(started.getRequest().isAsyncStarted()).isTrue();
        // 初始派发已经返回，Security 的写头此刻已经执行完；业务线程这时才产出响应。
        pendingResult.complete(pendingCall.get().get());
        return mockMvc.perform(asyncDispatch(started))
                .andExpect(status().isOk())
                .andReturn();
    }

    @RestController
    static class AsyncProbeController {

        @GetMapping("/probe/async-cover")
        CompletableFuture<ResponseEntity<StreamingResponseBody>> cover() {
            return CompletableFuture.completedFuture(ResponseEntity.ok()
                    .contentLength(0L)
                    .header(HttpHeaders.CACHE_CONTROL, IMMUTABLE)
                    .body(outputStream -> {
                    }));
        }
    }
}
