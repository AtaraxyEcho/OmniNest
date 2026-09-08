package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.LocalMediaScanEntry;
import com.omninest.modules.file.service.LocalMediaIndexService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaScanCandidate;
import com.omninest.modules.video.domain.MediaScanRun;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.event.LocalVideoLibraryApplyRequestedEvent;
import com.omninest.modules.video.repository.MediaScanBatchRepository;
import com.omninest.modules.video.repository.MediaScanCandidateRepository;
import com.omninest.modules.video.repository.MediaScanRunRepository;
import com.omninest.modules.video.repository.VideoLibrarySourceRepository;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;

/**
 * 本地媒体按需入库执行器回归测试。
 *
 * <p>覆盖候选实体在同一流程内连续保存时版本字段保持正确的行为，防止 Hibernate merge
 * 因传入过期版本抛出乐观锁异常导致整个入库任务反复失败。</p>
 */
@ExtendWith(MockitoExtension.class)
class MediaLibraryApplyExecutorTest {

    private static final UUID TASK_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID RUN_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID LOCATION_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");

    @Mock
    private MediaScanRunRepository runRepository;
    @Mock
    private MediaScanCandidateRepository candidateRepository;
    @Mock
    private MediaScanBatchRepository batchRepository;
    @Mock
    private VideoLibrarySourceRepository sourceRepository;
    @Mock
    private LocalMediaIndexService localMediaIndexService;
    @Mock
    private LocalMediaLibraryClassifier classifier;
    @Mock
    private AdaptiveChunkPolicy chunkPolicy;
    @Mock
    private TaskRecordService taskRecordService;
    @Mock
    private ReadThroughCache readThroughCache;
    @Mock
    private MediaSyncEventService syncEventService;
    @Mock
    private PlatformTransactionManager transactionManager;

    private MediaLibraryApplyExecutor executor;
    private List<MediaScanCandidate> savedCandidates;

    @BeforeEach
    void setUp() {
        executor = new MediaLibraryApplyExecutor(
                runRepository,
                candidateRepository,
                batchRepository,
                sourceRepository,
                localMediaIndexService,
                classifier,
                chunkPolicy,
                taskRecordService,
                readThroughCache,
                syncEventService,
                transactionManager
        );
        savedCandidates = new ArrayList<>();
    }

    @Test
    void appliesSelectedCandidateWithoutStaleVersionConflict() {
        TransactionStatus status = mock(TransactionStatus.class);
        when(transactionManager.getTransaction(any())).thenReturn(status);
        doNothing().when(transactionManager).commit(any());

        when(taskRecordService.claimForExecution(TASK_ID, "APPLYING")).thenReturn(true);
        when(taskRecordService.isCancelled(TASK_ID)).thenReturn(false);

        MediaScanRun run = new MediaScanRun();
        run.setId(RUN_ID);
        run.setOwnerUserId(OWNER_ID);
        run.setLibrarySourceId(SOURCE_ID);
        run.setStatus("QUEUED");
        run.setPhase("APPLY");
        when(runRepository.findByIdAndOwnerUserId(RUN_ID, OWNER_ID)).thenReturn(Optional.of(run));

        VideoLibrarySource source = new VideoLibrarySource();
        source.setId(SOURCE_ID);
        source.setOwnerUserId(OWNER_ID);
        source.setStorageLocationId(LOCATION_ID);
        source.setRelativeRoot(".");
        source.setLibraryType("MOVIE");
        source.setScanStatus("QUEUED");
        when(sourceRepository.findByIdAndOwnerUserId(SOURCE_ID, OWNER_ID)).thenReturn(Optional.of(source));
        when(sourceRepository.save(any(VideoLibrarySource.class))).thenAnswer(invocation -> invocation.getArgument(0));

        when(candidateRepository.resetInterruptedCandidates(OWNER_ID, RUN_ID)).thenReturn(0);

        MediaScanCandidate candidate = new MediaScanCandidate();
        candidate.setId(UUID.fromString("70000000-0000-0000-0000-000000000001"));
        candidate.setOwnerUserId(OWNER_ID);
        candidate.setScanRunId(RUN_ID);
        candidate.setLibrarySourceId(SOURCE_ID);
        candidate.setRelativePath("千与千寻.mkv");
        candidate.setFileName("千与千寻.mkv");
        candidate.setMatchStatus("NEW");
        candidate.setSelected(true);
        candidate.setApplyStatus("PENDING");

        // 模拟 Hibernate merge 语义：save 返回携带递增版本的新实例，原 detached 实例版本不变。
        // 同时记录每次 save 传入参数的快照，用于断言后续保存携带了新版本。
        when(candidateRepository.save(any(MediaScanCandidate.class))).thenAnswer(invocation -> {
            MediaScanCandidate incoming = invocation.getArgument(0);
            savedCandidates.add(copyCandidate(incoming, incoming.getVersion()));
            return copyCandidate(incoming, incoming.getVersion() + 1);
        });

        when(candidateRepository.countByOwnerUserIdAndScanRunIdAndSelectedTrue(OWNER_ID, RUN_ID)).thenReturn(1L);
        when(batchRepository.findFirstByOwnerUserIdAndScanRunIdAndPhaseOrderByBatchNoDesc(OWNER_ID, RUN_ID, "APPLY"))
                .thenReturn(Optional.empty());
        when(chunkPolicy.initialSize(BatchWorkloadProfile.APPLY, 1)).thenReturn(8);

        Page<MediaScanCandidate> firstPage = new PageImpl<>(List.of(candidate));
        Page<MediaScanCandidate> emptyPage = new PageImpl<>(List.of());
        when(candidateRepository.findByOwnerUserIdAndScanRunIdAndSelectedTrueAndApplyStatusOrderByRelativePathAsc(
                eq(OWNER_ID),
                eq(RUN_ID),
                eq("PENDING"),
                any(PageRequest.class)
        )).thenReturn(firstPage, emptyPage);

        when(localMediaIndexService.registerSelected(OWNER_ID, LOCATION_ID, "千与千寻.mkv"))
                .thenReturn(new LocalMediaScanEntry(FILE_NODE_ID, "千与千寻.mkv", "千与千寻.mkv"));
        when(classifier.classify(any(UUID.class), any(VideoLibrarySource.class), any(LocalMediaScanEntry.class)))
                .thenReturn(LocalMediaLibraryClassifier.ClassificationOutcome.CREATED);

        when(candidateRepository.countByOwnerUserIdAndScanRunIdAndApplyStatus(OWNER_ID, RUN_ID, "APPLIED"))
                .thenReturn(1L);
        when(candidateRepository.countByOwnerUserIdAndScanRunIdAndApplyStatus(OWNER_ID, RUN_ID, "FAILED"))
                .thenReturn(0L);
        when(chunkPolicy.nextSize(any(), anyLong(), anyInt(), any(), any())).thenReturn(8);

        LocalVideoLibraryApplyRequestedEvent event =
                new LocalVideoLibraryApplyRequestedEvent(TASK_ID, OWNER_ID, SOURCE_ID, RUN_ID);
        executor.execute(event);

        assertThat(savedCandidates).hasSize(2);
        assertThat(savedCandidates.get(0).getApplyStatus()).isEqualTo("APPLYING");
        assertThat(savedCandidates.get(1).getApplyStatus()).isEqualTo("APPLIED");
        // 第二次保存必须携带第一次保存返回的新版本，否则真实 Hibernate merge 会抛乐观锁异常。
        assertThat(savedCandidates.get(1).getVersion())
                .isEqualTo(savedCandidates.get(0).getVersion() + 1L);
        verify(candidateRepository, times(2)).save(any(MediaScanCandidate.class));
        verify(taskRecordService).markCompleted(eq(TASK_ID), any());
    }

    private MediaScanCandidate copyCandidate(MediaScanCandidate source, long version) {
        MediaScanCandidate target = new MediaScanCandidate();
        target.setId(source.getId());
        target.setOwnerUserId(source.getOwnerUserId());
        target.setScanRunId(source.getScanRunId());
        target.setLibrarySourceId(source.getLibrarySourceId());
        target.setRelativePath(source.getRelativePath());
        target.setFileName(source.getFileName());
        target.setSizeBytes(source.getSizeBytes());
        target.setCandidateType(source.getCandidateType());
        target.setGroupId(source.getGroupId());
        target.setGroupTitle(source.getGroupTitle());
        target.setSeasonNumber(source.getSeasonNumber());
        target.setEpisodeNumber(source.getEpisodeNumber());
        target.setMatchStatus(source.getMatchStatus());
        target.setSelected(source.isSelected());
        target.setApplyStatus(source.getApplyStatus());
        target.setExistingFileNodeId(source.getExistingFileNodeId());
        target.setAppliedFileNodeId(source.getAppliedFileNodeId());
        target.setReasonCode(source.getReasonCode());
        target.setErrorSummary(source.getErrorSummary());
        target.setVersion(version);
        return target;
    }
}
