package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.dto.FileProcessInput;
import com.omninest.modules.file.service.FileQueryService;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 本机 ffmpeg 输入解析测试。
 *
 * @author OmniNest
 */
class VideoSourceInputResolverTest {

    private static final UUID OWNER = UUID.randomUUID();
    private static final UUID NODE = UUID.randomUUID();

    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final VideoSourceInputResolver resolver = new VideoSourceInputResolver(fileQueryService);

    @Test
    @DisplayName("LOCAL_FILESYSTEM 使用本机进程路径，而不是 ffmpeg 容器路径")
    void localFilesystemUsesProcessPath() {
        when(fileQueryService.createOwnedContainerProcessInput(OWNER, NODE))
                .thenReturn(new FileProcessInput(NODE, "LOCAL_FILESYSTEM", "/host/media/movie.mkv"));

        assertThat(resolver.resolveLocalInput(OWNER, NODE)).isEqualTo("/host/media/movie.mkv");
        // 容器视角输入对本地来源本身就返回进程路径，不能再多查一次库、多签一次 URL。
        verify(fileQueryService, never()).createOwnedProcessInput(OWNER, NODE);
    }

    @Test
    @DisplayName("对象存储仍使用容器网络端点，且只解析一次")
    void objectStorageUsesContainerEndpoint() {
        when(fileQueryService.createOwnedContainerProcessInput(OWNER, NODE))
                .thenReturn(new FileProcessInput(NODE, "MINIO", "http://minio:9000/signed"));

        assertThat(resolver.resolveLocalInput(OWNER, NODE)).isEqualTo("http://minio:9000/signed");
        verify(fileQueryService, never()).createOwnedProcessInput(OWNER, NODE);
    }
}
