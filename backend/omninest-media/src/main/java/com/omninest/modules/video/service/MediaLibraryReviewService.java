package com.omninest.modules.video.service;

import com.omninest.common.api.PageResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaLibraryType;
import com.omninest.modules.video.domain.MediaScanCandidate;
import com.omninest.modules.video.domain.MediaScanRun;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.dto.MediaScanDtos.ApplySelectionRequest;
import com.omninest.modules.video.dto.MediaScanDtos.MediaScanRunDto;
import com.omninest.modules.video.dto.MediaScanDtos.MediaScanTreeNodeDto;
import com.omninest.modules.video.dto.MediaScanDtos.SelectionSummaryDto;
import com.omninest.modules.video.dto.MediaScanDtos.UpdateSelectionRequest;
import com.omninest.modules.video.dto.MediaScanDtos.UnavailableMediaDto;
import com.omninest.modules.video.dto.MovieDtos.ScrapeTaskDto;
import com.omninest.modules.video.event.LocalVideoLibraryApplyRequestedEvent;
import com.omninest.modules.video.repository.MediaScanCandidateRepository;
import com.omninest.modules.video.repository.MediaScanCandidateRepository.GroupSummary;
import com.omninest.modules.video.repository.MediaScanCandidateRepository.SeasonSummary;
import com.omninest.modules.video.repository.MediaScanRunRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.VideoLibrarySourceRepository;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 媒体候选树、三态选择和按需入库应用服务。
 */
@Service
@RequiredArgsConstructor
public class MediaLibraryReviewService {
    private static final String APPLY_TASK_TYPE = "LOCAL_VIDEO_LIBRARY_APPLY";

    private final MediaScanRunRepository runRepository;
    private final MediaScanCandidateRepository candidateRepository;
    private final VideoLibrarySourceRepository sourceRepository;
    private final MediaVideoItemRepository videoItemRepository;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final MediaLibraryAccessService accessService;

    /** 查询来源最近一次发现运行。 */
    @Transactional(readOnly = true)
    public MediaScanRunDto latestRun(UUID operatorUserId, UUID sourceId) {
        requireSource(operatorUserId, sourceId);
        return runRepository.findFirstByLibrarySourceIdOrderByCreatedAtDesc(sourceId)
                .map(this::toDto)
                .orElse(null);
    }

    /** 查询运行详情。 */
    @Transactional(readOnly = true)
    public MediaScanRunDto getRun(UUID ownerUserId, UUID runId) {
        return toDto(requireRun(ownerUserId, runId));
    }

    /** 分页查询已经入库但当前无法读取的本地媒体。 */
    @Transactional(readOnly = true)
    public PageResponse<UnavailableMediaDto> unavailable(UUID operatorUserId, int page, int size) {
        accessService.requireManagePermission(operatorUserId);
        int safePage = Math.max(0, page);
        int safeSize = com.omninest.common.api.PageClamps.safeSize(size);
        List<UUID> sourceIds = sourceRepository.findAllByOrderByNameAsc().stream()
                .map(VideoLibrarySource::getId)
                .toList();
        if (sourceIds.isEmpty()) {
            return PageResponse.of(List.of(), safePage, safeSize, 0);
        }
        var result = videoItemRepository.findUnavailableLocalMediaByLibrarySourceIds(
                sourceIds,
                PageRequest.of(safePage, safeSize)
        );
        List<UnavailableMediaDto> items = result.getContent().stream().map(item -> new UnavailableMediaDto(
                item.getVideoItemId(),
                item.getFileNodeId(),
                item.getLibrarySourceId(),
                item.getTitle(),
                item.getAvailabilityStatus(),
                item.getMissingSince(),
                item.getMissingConfirmations()
        )).toList();
        return PageResponse.of(items, safePage, safeSize, result.getTotalElements());
    }

    /** 懒加载候选媒体语义树的直接子节点。 */
    @Transactional(readOnly = true)
    public PageResponse<MediaScanTreeNodeDto> tree(
            UUID ownerUserId,
            UUID runId,
            String parentNodeId,
            int page,
            int size
    ) {
        MediaScanRun run = requireRun(ownerUserId, runId);
        UUID catalogOwnerId = run.getOwnerUserId();
        VideoLibrarySource source = requireSource(ownerUserId, run.getLibrarySourceId());
        int safePage = Math.max(0, page);
        int safeSize = com.omninest.common.api.PageClamps.safeSize(size);
        String parent = parentNodeId == null || parentNodeId.isBlank() ? "ROOT" : parentNodeId;
        if ("ROOT".equals(parent)) {
            return rootNodes(catalogOwnerId, runId, source, safePage, safeSize);
        }
        if (parent.startsWith("SERIES:")) {
            return seasonNodes(catalogOwnerId, runId, parseSeriesId(parent), safePage, safeSize);
        }
        if (parent.startsWith("SEASON:")) {
            SeasonNodeKey key = parseSeason(parent);
            return candidateNodes(catalogOwnerId, runId, key.groupId(), key.seasonNumber(), safePage, safeSize);
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "候选树父节点无效");
    }

    /** 原子更新服务端选择范围并推进 revision。 */
    @Transactional(rollbackFor = Exception.class)
    public SelectionSummaryDto updateSelection(
            UUID ownerUserId,
            UUID runId,
            UpdateSelectionRequest request
    ) {
        MediaScanRun run = requireRun(ownerUserId, runId);
        UUID catalogOwnerId = run.getOwnerUserId();
        if (!List.of("READY", "PAUSED", "PARTIAL").contains(run.getStatus())) {
            throw new BusinessException(ErrorCode.CONFLICT, "当前发现运行不能修改选择");
        }
        if (run.getSelectionRevision() != request.expectedRevision()) {
            throw new BusinessException(ErrorCode.CONFLICT, "候选选择已更新，请刷新后重试");
        }
        int updated = updateSelectionScope(catalogOwnerId, runId, request.nodeId(), request.selected());
        if (updated == 0) {
            throw new BusinessException(ErrorCode.NOT_FOUND, "候选选择范围不存在");
        }
        run.setSelectionRevision(run.getSelectionRevision() + 1);
        run.setSelectedCount(Math.toIntExact(
                candidateRepository.countByOwnerUserIdAndScanRunIdAndSelectedTrue(catalogOwnerId, runId)
        ));
        runRepository.save(run);
        return summary(ownerUserId, runId);
    }

    /** 查询当前选择汇总。 */
    @Transactional(readOnly = true)
    public SelectionSummaryDto summary(UUID ownerUserId, UUID runId) {
        MediaScanRun run = requireRun(ownerUserId, runId);
        UUID catalogOwnerId = run.getOwnerUserId();
        return new SelectionSummaryDto(
                runId,
                run.getSelectionRevision(),
                candidateRepository.countByOwnerUserIdAndScanRunId(catalogOwnerId, runId),
                candidateRepository.countByOwnerUserIdAndScanRunIdAndSelectedTrue(catalogOwnerId, runId),
                candidateRepository.countByOwnerUserIdAndScanRunIdAndMatchStatus(catalogOwnerId, runId, "EXISTING"),
                candidateRepository.countByOwnerUserIdAndScanRunIdAndMatchStatus(catalogOwnerId, runId, "UNMATCHED"),
                candidateRepository.countByOwnerUserIdAndScanRunIdAndApplyStatus(catalogOwnerId, runId, "FAILED")
        );
    }

    /** 创建用户确认后的分批入库任务。 */
    @Transactional(rollbackFor = Exception.class)
    public ScrapeTaskDto apply(
            UUID ownerUserId,
            UUID runId,
            ApplySelectionRequest request
    ) {
        MediaScanRun run = requireRun(ownerUserId, runId);
        UUID catalogOwnerId = run.getOwnerUserId();
        if (!List.of("READY", "PAUSED", "PARTIAL").contains(run.getStatus())) {
            throw new BusinessException(ErrorCode.CONFLICT, "当前发现运行不能开始入库");
        }
        if (run.getSelectionRevision() != request.expectedRevision()) {
            throw new BusinessException(ErrorCode.CONFLICT, "候选选择已更新，请刷新后重试");
        }
        long selected = candidateRepository.countByOwnerUserIdAndScanRunIdAndSelectedTrue(catalogOwnerId, runId);
        if (selected == 0) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "请至少选择一个可入库候选项");
        }
        VideoLibrarySource source = requireSource(ownerUserId, run.getLibrarySourceId());
        UUID taskId = UUID.randomUUID();
        run.setApplyTaskId(taskId);
        run.setStatus("QUEUED");
        run.setPhase("APPLY");
        runRepository.save(run);
        source.setScanStatus("QUEUED");
        sourceRepository.save(source);
        Map<String, Object> payload = Map.of(
                "catalogOwnerId", catalogOwnerId.toString(),
                "operatorUserId", ownerUserId.toString(),
                "sourceId", source.getId().toString(),
                "scanRunId", runId.toString(),
                "selectionRevision", request.expectedRevision()
        );
        taskRecordService.createQueuedTask(
                taskId,
                ownerUserId,
                APPLY_TASK_TYPE,
                QueueNames.LOCAL_VIDEO_LIBRARY_APPLY_ROUTING_KEY,
                "QUEUED",
                "MEDIA_SCAN_RUN",
                runId,
                payload
        );
        LocalVideoLibraryApplyRequestedEvent event = new LocalVideoLibraryApplyRequestedEvent(
                taskId,
                catalogOwnerId,
                source.getId(),
                runId
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.LOCAL_VIDEO_LIBRARY_APPLY_ROUTING_KEY,
                event
        );
        return new ScrapeTaskDto(taskId, TaskStatus.QUEUED.getValue(), "所选媒体已进入分批入库队列");
    }

    /** 暂停正在执行的入库运行，Worker 会在当前短批次后停止。 */
    @Transactional(rollbackFor = Exception.class)
    public MediaScanRunDto pause(UUID ownerUserId, UUID runId) {
        MediaScanRun run = requireRun(ownerUserId, runId);
        if (!"APPLYING".equals(run.getStatus())) {
            throw new BusinessException(ErrorCode.CONFLICT, "只有正在入库的运行可以暂停");
        }
        run.setStatus("PAUSED");
        return toDto(runRepository.save(run));
    }

    /** 取消当前运行，已提交的短批次不会回滚。 */
    @Transactional(rollbackFor = Exception.class)
    public MediaScanRunDto cancel(UUID ownerUserId, UUID runId) {
        MediaScanRun run = requireRun(ownerUserId, runId);
        if (List.of("COMPLETED", "CANCELLED").contains(run.getStatus())) {
            return toDto(run);
        }
        run.setStatus("CANCELLED");
        run.setFinishedAt(Instant.now());
        if (run.getDiscoveryTaskId() != null) {
            taskRecordService.markCancelled(run.getDiscoveryTaskId());
        }
        if (run.getApplyTaskId() != null) {
            taskRecordService.markCancelled(run.getApplyTaskId());
        }
        VideoLibrarySource source = requireSource(ownerUserId, run.getLibrarySourceId());
        source.setScanStatus("CANCELLED");
        sourceRepository.save(source);
        return toDto(runRepository.save(run));
    }

    private PageResponse<MediaScanTreeNodeDto> rootNodes(
            UUID ownerUserId,
            UUID runId,
            VideoLibrarySource source,
            int page,
            int size
    ) {
        if (MediaLibraryType.valueOf(source.getLibraryType()) == MediaLibraryType.MOVIE) {
            Page<MediaScanCandidate> candidates = candidateRepository
                    .findByOwnerUserIdAndScanRunIdOrderByGroupTitleAscSeasonNumberAscEpisodeNumberAsc(
                            ownerUserId,
                            runId,
                            PageRequest.of(page, size)
                    );
            return PageResponse.of(candidates.getContent().stream().map(this::candidateNode).toList(),
                    page, size, candidates.getTotalElements());
        }
        Page<GroupSummary> groups = candidateRepository.summarizeGroups(
                ownerUserId,
                runId,
                PageRequest.of(page, size)
        );
        List<MediaScanTreeNodeDto> items = groups.getContent().stream().map(group -> new MediaScanTreeNodeDto(
                "SERIES:" + group.getGroupId(),
                "SERIES",
                group.getGroupTitle(),
                group.getCandidateCount() + " 集",
                true,
                group.getCandidateCount(),
                group.getCandidateCount(),
                group.getSelectedCount(),
                group.getIssueCount(),
                selectionState(group.getSelectedCount(), group.getCandidateCount()),
                null,
                null,
                null,
                null,
                null
        )).toList();
        return PageResponse.of(items, page, size, groups.getTotalElements());
    }

    private PageResponse<MediaScanTreeNodeDto> seasonNodes(
            UUID ownerUserId,
            UUID runId,
            UUID groupId,
            int page,
            int size
    ) {
        List<SeasonSummary> seasons = candidateRepository.summarizeSeasons(ownerUserId, runId, groupId);
        int from = Math.min(seasons.size(), page * size);
        int to = Math.min(seasons.size(), from + size);
        List<MediaScanTreeNodeDto> items = seasons.subList(from, to).stream().map(season -> {
            int seasonNumber = season.getSeasonNumber() == null ? 1 : season.getSeasonNumber();
            String title = seasonNumber == 0 ? "特别篇" : "第 " + seasonNumber + " 季";
            return new MediaScanTreeNodeDto(
                    "SEASON:" + groupId + ":" + seasonNumber,
                    "SEASON",
                    title,
                    season.getCandidateCount() + " 集",
                    true,
                    season.getCandidateCount(),
                    season.getCandidateCount(),
                    season.getSelectedCount(),
                    season.getIssueCount(),
                    selectionState(season.getSelectedCount(), season.getCandidateCount()),
                    null,
                    null,
                    null,
                    null,
                    null
            );
        }).toList();
        return PageResponse.of(items, page, size, seasons.size());
    }

    private PageResponse<MediaScanTreeNodeDto> candidateNodes(
            UUID ownerUserId,
            UUID runId,
            UUID groupId,
            int seasonNumber,
            int page,
            int size
    ) {
        Page<MediaScanCandidate> candidates = candidateRepository
                .findByOwnerUserIdAndScanRunIdAndGroupIdAndSeasonNumberOrderByEpisodeNumberAsc(
                        ownerUserId,
                        runId,
                        groupId,
                        seasonNumber,
                        PageRequest.of(page, size)
                );
        return PageResponse.of(candidates.getContent().stream().map(this::candidateNode).toList(),
                page, size, candidates.getTotalElements());
    }

    private MediaScanTreeNodeDto candidateNode(MediaScanCandidate candidate) {
        String title = "EPISODE".equals(candidate.getCandidateType()) && candidate.getEpisodeNumber() != null
                ? "第 " + candidate.getEpisodeNumber() + " 集 · " + candidate.getFileName()
                : candidate.getGroupTitle();
        return new MediaScanTreeNodeDto(
                "CANDIDATE:" + candidate.getId(),
                candidate.getCandidateType(),
                title,
                candidate.getRelativePath(),
                false,
                0,
                1,
                candidate.isSelected() ? 1 : 0,
                List.of("AMBIGUOUS", "UNMATCHED").contains(candidate.getMatchStatus()) ? 1 : 0,
                candidate.isSelected() ? "ALL" : "NONE",
                candidate.getMatchStatus(),
                candidate.getApplyStatus(),
                candidate.getReasonCode(),
                candidate.getId(),
                candidate.getSizeBytes()
        );
    }

    private int updateSelectionScope(UUID ownerUserId, UUID runId, String nodeId, boolean selected) {
        if ("ROOT".equals(nodeId)) {
            return candidateRepository.updateSelectionForRun(ownerUserId, runId, selected);
        }
        if (nodeId.startsWith("SERIES:")) {
            return candidateRepository.updateSelectionForGroup(ownerUserId, runId, parseSeriesId(nodeId), selected);
        }
        if (nodeId.startsWith("SEASON:")) {
            SeasonNodeKey key = parseSeason(nodeId);
            return candidateRepository.updateSelectionForSeason(
                    ownerUserId,
                    runId,
                    key.groupId(),
                    key.seasonNumber(),
                    selected
            );
        }
        if (nodeId.startsWith("CANDIDATE:")) {
            UUID candidateId = parseUuid(nodeId.substring("CANDIDATE:".length()));
            return candidateRepository.updateSelectionForCandidate(ownerUserId, runId, candidateId, selected);
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "候选选择节点无效");
    }

    private UUID parseSeriesId(String nodeId) {
        return parseUuid(nodeId.substring("SERIES:".length()));
    }

    private SeasonNodeKey parseSeason(String nodeId) {
        String[] parts = nodeId.split(":", 3);
        if (parts.length != 3) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "季度节点无效");
        }
        try {
            return new SeasonNodeKey(parseUuid(parts[1]), Integer.parseInt(parts[2]));
        } catch (NumberFormatException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "季度节点无效");
        }
    }

    private UUID parseUuid(String value) {
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "候选树节点无效");
        }
    }

    private String selectionState(long selected, long total) {
        if (selected <= 0) {
            return "NONE";
        }
        return selected >= total ? "ALL" : "PARTIAL";
    }

    private MediaScanRun requireRun(UUID operatorUserId, UUID runId) {
        MediaScanRun run = runRepository.findById(runId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "媒体发现运行不存在"));
        VideoLibrarySource source = accessService.requireManage(operatorUserId, run.getLibrarySourceId());
        if (!source.getId().equals(run.getLibrarySourceId())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "媒体发现运行不属于该媒体库");
        }
        return run;
    }

    private VideoLibrarySource requireSource(UUID operatorUserId, UUID sourceId) {
        return accessService.requireManage(operatorUserId, sourceId);
    }

    private MediaScanRunDto toDto(MediaScanRun run) {
        return new MediaScanRunDto(
                run.getId(),
                run.getLibrarySourceId(),
                run.getDiscoveryTaskId(),
                run.getApplyTaskId(),
                run.getGeneration(),
                run.getSelectionRevision(),
                run.getStatus(),
                run.getPhase(),
                run.getDiscoveredCount(),
                run.getCandidateCount(),
                run.getExistingCount(),
                run.getConflictCount(),
                run.getUnmatchedCount(),
                run.getMissingCount(),
                run.getSelectedCount(),
                run.getAppliedCount(),
                run.getFailedCount(),
                run.getStartedAt(),
                run.getFinishedAt(),
                run.getCreatedAt(),
                run.getUpdatedAt()
        );
    }

    private record SeasonNodeKey(UUID groupId, int seasonNumber) {
    }
}
