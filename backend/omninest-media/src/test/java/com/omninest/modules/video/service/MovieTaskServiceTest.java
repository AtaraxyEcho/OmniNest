package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.dto.MovieDtos.MovieScanRequest;
import com.omninest.modules.video.repository.MediaTaskRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 影视任务编排服务测试。
 *
 * @author OmniNest
 */
class MovieTaskServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final MediaTaskRepository mediaTaskRepository = mock(MediaTaskRepository.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final MediaVideoItemRepository videoItemRepository = mock(MediaVideoItemRepository.class);
    private final MediaContentAccessService mediaContentAccessService = mock(MediaContentAccessService.class);
    private final FileMetadataQueryService fileMetadataQueryService = mock(FileMetadataQueryService.class);
    private final SimpleFileNameParser fileNameParser = mock(SimpleFileNameParser.class);
    private final MovieScrapeService scrapeService = mock(MovieScrapeService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final MovieTaskService service = new MovieTaskService(
            mediaTaskRepository,
            taskRecordService,
            videoItemRepository,
            mediaContentAccessService,
            fileMetadataQueryService,
            fileNameParser,
            scrapeService,
            taskDispatchService
    );

    /**
     * 验证媒体扫描只登记视频条目，不创建外部元数据刮削任务。
     */
    @Test
    void scanLibraryCreatesTaskForVideoDescriptor() {
        FileDescriptor video = new FileDescriptor(
                FILE_ID, OWNER_ID, null, "FILE", "movie.mkv", "/movie.mkv",
                "video/x-matroska", 4096, null, "LOCAL", false, false,
                SpaceType.PERSONAL, OWNER_ID, null, null);
        when(fileMetadataQueryService.listOwnedActive(OWNER_ID)).thenReturn(List.of(video));
        when(fileNameParser.isVideoFile(video.name(), video.mimeType())).thenReturn(true);
        when(videoItemRepository.findByOwnerUserIdAndFileNodeIdIn(eq(OWNER_ID), any()))
                .thenReturn(List.of());

        var result = service.scanLibrary(OWNER_ID, new MovieScanRequest(null, true));

        assertThat(result.message()).contains("发现 1 个视频");
        verify(scrapeService).registerPendingVideo(OWNER_ID, FILE_ID);
    }
}
