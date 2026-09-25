package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderSourceStatus;
import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 漫画解析任务用例服务单元测试，验证解析状态机与任务状态回写。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ComicParseTaskServiceTest {

    private static final UUID TASK_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");

    @Mock
    private ReaderComicManifestService comicManifestService;

    @Mock
    private ReaderItemSourceRepository sourceRepository;

    @Mock
    private TaskRecordService taskRecordService;

    @Mock
    private FileLifecycleGuard fileLifecycleGuard;

    @InjectMocks
    private ComicParseTaskService taskService;

    @BeforeEach
    void allowFileProcessing() {
        Mockito.lenient()
                .when(taskRecordService.claimForExecution(TASK_ID, "PARSING_SOURCE"))
                .thenReturn(true);
        Mockito.lenient()
                .when(fileLifecycleGuard.isOwnedProcessable(OWNER_ID, FILE_NODE_ID))
                .thenReturn(true);
    }

    @Test
    void processCancelsTaskWhenSourceFileIsPurging() {
        Mockito.when(fileLifecycleGuard.isOwnedProcessable(OWNER_ID, FILE_NODE_ID)).thenReturn(false);

        taskService.process(event());

        Mockito.verify(taskRecordService).markCancelled(TASK_ID);
        Mockito.verifyNoInteractions(sourceRepository, comicManifestService);
    }

    @Test
    void processMarksTaskFailedWhenSourceIsMissing() {
        Mockito.when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.empty());

        taskService.process(event());

        Mockito.verify(taskRecordService).claimForExecution(TASK_ID, "PARSING_SOURCE");
        Mockito.verify(taskRecordService).markFailed(TASK_ID, "漫画来源不存在", null);
        Mockito.verifyNoInteractions(comicManifestService);
    }

    @Test
    void processSkipsReadySourceAndCompletesTask() {
        ReaderItemSource source = sourceWithStatus(ReaderSourceStatus.READY);
        Mockito.when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));

        taskService.process(event());

        Mockito.verify(comicManifestService).refreshItemImportStatus(ITEM_ID);
        Mockito.verify(comicManifestService, Mockito.never())
                .parseExistingSource(Mockito.eq(ITEM_ID), Mockito.eq(SOURCE_ID), Mockito.any());
        Mockito.verify(taskRecordService).markCompleted(Mockito.eq(TASK_ID), Mockito.any(Map.class));
    }

    @Test
    void processParsesExistingSourceAndCompletesTask() {
        ReaderItemSource source = sourceWithStatus(ReaderSourceStatus.PENDING);
        Mockito.when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));

        taskService.process(event());

        Mockito.verify(comicManifestService)
                .parseExistingSource(Mockito.eq(ITEM_ID), Mockito.eq(SOURCE_ID), Mockito.any());
        Mockito.verify(taskRecordService).markCompleted(Mockito.eq(TASK_ID), Mockito.any(Map.class));
    }

    @Test
    void processPersistsBusinessFailureAndCompletesFailureHandling() {
        ReaderItemSource source = sourceWithStatus(ReaderSourceStatus.PARSING);
        Mockito.when(sourceRepository.findById(SOURCE_ID))
                .thenReturn(Optional.of(source), Optional.of(source));
        Mockito.doThrow(new BusinessException(ErrorCode.PARAM_ERROR, "parse failed"))
                .when(comicManifestService)
                .parseExistingSource(Mockito.eq(ITEM_ID), Mockito.eq(SOURCE_ID), Mockito.any());

        taskService.process(event());

        Assertions.assertThat(source.getStatus()).isEqualTo(ReaderSourceStatus.FAILED);
        Assertions.assertThat(source.getErrorCode()).isEqualTo("PARSE_ERROR");
        Assertions.assertThat(source.getErrorMessage()).isEqualTo("parse failed");
        Mockito.verify(sourceRepository).save(source);
        Mockito.verify(comicManifestService).refreshItemImportStatus(ITEM_ID);
        Mockito.verify(taskRecordService).markFailed(
                Mockito.eq(TASK_ID), Mockito.eq("parse failed"), Mockito.anyString());
    }

    @Test
    void processPropagatesInfrastructureFailure() {
        ReaderItemSource source = sourceWithStatus(ReaderSourceStatus.PARSING);
        Mockito.when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        Mockito.doThrow(new IllegalStateException("database unavailable"))
                .when(comicManifestService)
                .parseExistingSource(Mockito.eq(ITEM_ID), Mockito.eq(SOURCE_ID), Mockito.any());

        Assertions.assertThatThrownBy(() -> taskService.process(event()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("database unavailable");
        Mockito.verify(sourceRepository, Mockito.never()).save(Mockito.any());
        Mockito.verify(taskRecordService, Mockito.never()).markFailed(
                Mockito.eq(TASK_ID), Mockito.any(), Mockito.any());
    }

    @Test
    void processPropagatesBusinessFailureWhenStatusPersistenceFails() {
        ReaderItemSource source = sourceWithStatus(ReaderSourceStatus.PARSING);
        Mockito.when(sourceRepository.findById(SOURCE_ID))
                .thenReturn(Optional.of(source), Optional.of(source));
        Mockito.doThrow(new BusinessException(ErrorCode.PARAM_ERROR, "parse failed"))
                .when(comicManifestService)
                .parseExistingSource(Mockito.eq(ITEM_ID), Mockito.eq(SOURCE_ID), Mockito.any());
        Mockito.doThrow(new IllegalStateException("database unavailable"))
                .when(sourceRepository)
                .save(source);

        Assertions.assertThatThrownBy(() -> taskService.process(event()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("database unavailable");
    }

    @Test
    void processAcceptsHistoricalMessageWithoutTaskRecord() {
        ReaderItemSource source = sourceWithStatus(ReaderSourceStatus.READY);
        Mockito.when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        Mockito.when(taskRecordService.claimForExecution(TASK_ID, "PARSING_SOURCE"))
                .thenThrow(new BusinessException(ErrorCode.TASK_NOT_FOUND, "task not found"));
        Mockito.doThrow(new BusinessException(ErrorCode.TASK_NOT_FOUND, "task not found"))
                .when(taskRecordService)
                .markCompleted(Mockito.eq(TASK_ID), Mockito.any(Map.class));

        taskService.process(event());

        Mockito.verify(comicManifestService).refreshItemImportStatus(ITEM_ID);
    }

    @Test
    void processSkipsDuplicateMessageWhenTaskCannotBeClaimed() {
        Mockito.when(taskRecordService.claimForExecution(TASK_ID, "PARSING_SOURCE")).thenReturn(false);

        taskService.process(event());

        Mockito.verifyNoInteractions(sourceRepository, comicManifestService);
        Mockito.verify(fileLifecycleGuard, Mockito.never())
                .isOwnedProcessable(OWNER_ID, FILE_NODE_ID);
    }

    private ReaderItemSource sourceWithStatus(ReaderSourceStatus status) {
        ReaderItemSource source = new ReaderItemSource();
        source.setId(SOURCE_ID);
        source.setReaderItemId(ITEM_ID);
        source.setStatus(status);
        return source;
    }

    private ComicParseTaskEvent event() {
        return new ComicParseTaskEvent(
                TASK_ID,
                OWNER_ID,
                ITEM_ID,
                SOURCE_ID,
                FILE_NODE_ID,
                "CBZ",
                "hash",
                false);
    }
}
