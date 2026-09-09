package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.messaging.QueueNames;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FilePermissionService;
import com.omninest.modules.task.domain.TaskRecord;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.event.MediaScrapeRequestedEvent;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 影视刮削服务测试。
 *
 * @author OmniNest
 */
class MovieScrapeServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID SERIES_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID TASK_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");

    private final FileMetadataQueryService fileMetadataQueryService = Mockito.mock(FileMetadataQueryService.class);
    private final TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
    private final MediaVideoItemRepository videoItemRepository = Mockito.mock(MediaVideoItemRepository.class);
    private final MediaTvSeriesRepository tvSeriesRepository = Mockito.mock(MediaTvSeriesRepository.class);
    private final MediaTvSeasonRepository tvSeasonRepository = Mockito.mock(MediaTvSeasonRepository.class);
    private final SimpleFileNameParser fileNameParser = new SimpleFileNameParser();
    private final TaskDispatchService taskDispatchService = Mockito.mock(TaskDispatchService.class);
    private final FilePermissionService filePermissionService =
            Mockito.mock(FilePermissionService.class);
    private final ReadThroughCache readThroughCache = Mockito.mock(ReadThroughCache.class);
    private final MovieScrapeService scrapeService =
            new MovieScrapeService(fileMetadataQueryService, taskRecordService, videoItemRepository,
                    tvSeriesRepository, tvSeasonRepository, fileNameParser, List.of(),
                    taskDispatchService, filePermissionService, readThroughCache);

    @Test
    void createsScrapeTaskForVideoFile() {
        when(fileMetadataQueryService.findOwnedActive(OWNER_ID, FILE_ID))
                .thenReturn(Optional.of(file("Inception.2010.1080p.mkv", "video/x-matroska")));
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID))
                .thenReturn(Optional.empty());
        when(videoItemRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        var result = scrapeService.createScrapeTask(OWNER_ID, FILE_ID, false);

        assertThat(result.taskId()).isNotNull();
        assertThat(result.status()).isEqualTo("QUEUED");
        verify(taskRecordService).createQueuedTask(
                eq(result.taskId()),
                eq(OWNER_ID),
                eq("MEDIA_SCRAPE"),
                eq(QueueNames.MEDIA_SCRAPE_ROUTING_KEY),
                eq("QUEUED"),
                eq("FILE_NODE"),
                eq(FILE_ID),
                any()
        );
        verify(taskDispatchService).enqueue(
                eq(result.taskId()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.MEDIA_SCRAPE_ROUTING_KEY),
                any(MediaScrapeRequestedEvent.class)
        );
    }

    @Test
    void rejectsNonVideoFile() {
        when(fileMetadataQueryService.findOwnedActive(OWNER_ID, FILE_ID))
                .thenReturn(Optional.of(file("notes.txt", "text/plain")));

        assertThatThrownBy(() -> scrapeService.createScrapeTask(OWNER_ID, FILE_ID, false))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不是视频文件");
    }

    @Test
    void reusesActiveSeriesScrapeTaskForAnotherEpisode() {
        MediaVideoItem episode = new MediaVideoItem();
        episode.setOwnerUserId(OWNER_ID);
        episode.setFileNodeId(FILE_ID);
        episode.setMediaType(MediaType.EPISODE.getValue());
        episode.setSeriesId(SERIES_ID);
        episode.setSeasonNumber(1);
        episode.setEpisodeNumber(2);
        MediaTvSeries series = new MediaTvSeries();
        series.setId(SERIES_ID);
        series.setOwnerUserId(OWNER_ID);
        series.setTitle("Foundation");
        TaskRecord activeTask = new TaskRecord();
        activeTask.setId(TASK_ID);
        activeTask.setStatus("RUNNING");
        when(fileMetadataQueryService.findOwnedActive(OWNER_ID, FILE_ID))
                .thenReturn(Optional.of(file("Foundation.S01E02.mkv", "video/x-matroska")));
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID))
                .thenReturn(Optional.of(episode));
        when(tvSeriesRepository.findById(SERIES_ID)).thenReturn(Optional.of(series));
        when(taskRecordService.findActiveResourceTask(
                eq(OWNER_ID), eq("MEDIA_SCRAPE"), eq("MEDIA_SERIES"), eq(SERIES_ID), any()))
                .thenReturn(Optional.of(activeTask));

        var result = scrapeService.createScrapeTask(OWNER_ID, FILE_ID, false);

        assertThat(result.taskId()).isEqualTo(TASK_ID);
        assertThat(result.status()).isEqualTo("RUNNING");
        verify(taskRecordService, never()).createQueuedTask(
                any(), any(), any(), any(), any(), any(), any(), any());
    }

    @Test
    void reusesActiveFileNodeTaskOnRepeatedScrape() {
        MediaVideoItem item = new MediaVideoItem();
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(FILE_ID);
        item.setMediaType(MediaType.MOVIE.getValue());
        TaskRecord activeTask = new TaskRecord();
        activeTask.setId(TASK_ID);
        activeTask.setStatus("QUEUED");
        when(fileMetadataQueryService.findOwnedActive(OWNER_ID, FILE_ID))
                .thenReturn(Optional.of(file("Inception.2010.1080p.mkv", "video/x-matroska")));
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID))
                .thenReturn(Optional.of(item));
        when(taskRecordService.findActiveResourceTask(
                eq(OWNER_ID), eq("MEDIA_SCRAPE"), eq("FILE_NODE"), eq(FILE_ID), any()))
                .thenReturn(Optional.of(activeTask));

        var result = scrapeService.createScrapeTask(OWNER_ID, FILE_ID, false);

        assertThat(result.taskId()).isEqualTo(TASK_ID);
        assertThat(result.status()).isEqualTo("QUEUED");
        assertThat(result.message()).contains("已有刮削任务正在执行");
        verify(taskRecordService, never()).createQueuedTask(
                any(), any(), any(), any(), any(), any(), any(), any());
        Mockito.verifyNoInteractions(taskDispatchService);
    }

    @Test
    void deduplicatesByMovieResourceAfterScraped() {
        UUID movieId = UUID.fromString("60000000-0000-0000-0000-000000000001");
        MediaVideoItem item = new MediaVideoItem();
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(FILE_ID);
        item.setMediaType(MediaType.MOVIE.getValue());
        item.setMovieId(movieId);
        TaskRecord activeTask = new TaskRecord();
        activeTask.setId(TASK_ID);
        activeTask.setStatus("RUNNING");
        when(fileMetadataQueryService.findOwnedActive(OWNER_ID, FILE_ID))
                .thenReturn(Optional.of(file("Inception.2010.1080p.mkv", "video/x-matroska")));
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID))
                .thenReturn(Optional.of(item));
        when(taskRecordService.findActiveResourceTask(
                eq(OWNER_ID), eq("MEDIA_SCRAPE"), eq("MEDIA_MOVIE"), eq(movieId), any()))
                .thenReturn(Optional.of(activeTask));

        var result = scrapeService.createScrapeTask(OWNER_ID, FILE_ID, false);

        assertThat(result.taskId()).isEqualTo(TASK_ID);
        verify(taskRecordService, never()).createQueuedTask(
                any(), any(), any(), any(), any(), any(), any(), any());
    }

    @Test
    void outboxFailureAbortsTaskCreationAtomically() {
        when(fileMetadataQueryService.findOwnedActive(OWNER_ID, FILE_ID))
                .thenReturn(Optional.of(file("Inception.2010.1080p.mkv", "video/x-matroska")));
        when(videoItemRepository.findByOwnerUserIdAndFileNodeId(OWNER_ID, FILE_ID))
                .thenReturn(Optional.empty());
        when(videoItemRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        Mockito.doThrow(new IllegalStateException("broker down"))
                .when(taskDispatchService)
                .enqueue(any(), anyString(), anyString(), any());

        // enqueue 在同一事务内执行：异常上抛使任务记录与投递行一并回滚，不产生僵尸 QUEUED。
        assertThatThrownBy(() -> scrapeService.createScrapeTask(OWNER_ID, FILE_ID, false))
                .isInstanceOf(IllegalStateException.class);
    }

    private FileDescriptor file(String name, String mimeType) {
        return new FileDescriptor(
                FILE_ID, OWNER_ID, null, "FILE", name, "/Movies/" + name,
                mimeType, 1024, null, "LOCAL", false, false,
                SpaceType.PERSONAL, OWNER_ID, null, null);
    }
}
