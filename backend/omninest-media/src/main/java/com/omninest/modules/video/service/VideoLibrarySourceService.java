package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.service.StorageLocationService;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaImportPolicy;
import com.omninest.modules.video.domain.MediaLibraryType;
import com.omninest.modules.video.domain.MediaLibraryVisibility;
import com.omninest.modules.video.domain.MediaScanRun;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.dto.MovieDtos.ScrapeTaskDto;
import com.omninest.modules.video.dto.VideoLibrarySourceDtos.CreateVideoLibrarySourceRequest;
import com.omninest.modules.video.dto.VideoLibrarySourceDtos.UpdateVideoLibrarySourceRequest;
import com.omninest.modules.video.dto.VideoLibrarySourceDtos.VideoLibrarySourceDto;
import com.omninest.modules.video.event.LocalVideoLibraryScanRequestedEvent;
import com.omninest.modules.video.repository.MediaScanRunRepository;
import com.omninest.modules.video.repository.MediaScanBatchRepository;
import com.omninest.modules.video.repository.MediaScanCandidateRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.VideoLibrarySourceRepository;
import java.nio.file.InvalidPathException;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 影视库本地来源配置与发现任务编排服务。
 */
@Service
@RequiredArgsConstructor
public class VideoLibrarySourceService {
    private static final String DISCOVERY_TASK_TYPE = "LOCAL_VIDEO_LIBRARY_DISCOVERY";
    private static final List<String> ACTIVE_RUN_STATUSES = List.of("QUEUED", "DISCOVERING", "APPLYING");

    private final VideoLibrarySourceRepository sourceRepository;
    private final MediaScanRunRepository runRepository;
    private final MediaScanBatchRepository batchRepository;
    private final MediaScanCandidateRepository candidateRepository;
    private final MediaVideoItemRepository videoItemRepository;
    private final StorageLocationService storageLocationService;
    private final TaskRecordService taskRecordService;
    private final TaskDispatchService taskDispatchService;
    private final MediaLibraryDiscoveryExecutor discoveryExecutor;
    private final MediaLibraryAccessService accessService;

    /** 查询用户影视库来源。 */
    @Transactional(readOnly = true)
    public List<VideoLibrarySourceDto> list(UUID operatorUserId) {
        accessService.requireManagePermission(operatorUserId);
        return sourceRepository.findAllByOrderByNameAsc().stream().map(this::toDto).toList();
    }

    /** 创建用户影视库来源。 */
    @Transactional(rollbackFor = Exception.class)
    public VideoLibrarySourceDto create(UUID operatorUserId, CreateVideoLibrarySourceRequest request) {
        accessService.requireManagePermission(operatorUserId);
        UUID storageLocationId = resolveStorageLocationId(operatorUserId, request);
        StorageLocation location = storageLocationService.requireAccessibleLocation(
                operatorUserId,
                storageLocationId
        );
        if (!"SYSTEM".equals(location.getScopeType())) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "共享媒体库只能使用系统级存储位置");
        }
        String relativeRoot = normalizeRelativeRoot(request.relativeRoot());
        requireNoPathConflict(null, location, relativeRoot);
        VideoLibrarySource source = new VideoLibrarySource();
        source.setOwnerUserId(operatorUserId);
        source.setStorageLocationId(storageLocationId);
        source.setName(normalizeName(request.name()));
        source.setRelativeRoot(relativeRoot);
        source.setLibraryType(normalizeLibraryType(request.libraryType()).name());
        source.setImportPolicy(normalizeImportPolicy(request.importPolicy()).name());
        source.setVisibilityType(MediaLibraryVisibility.PRIVATE.name());
        source.setEnabled(request.enabled());
        source.setScanStatus("NEVER_SCANNED");
        source.setHealthStatus(request.enabled() ? "AVAILABLE" : "DISABLED");
        return toDto(sourceRepository.save(source));
    }

    /**
     * 解析来源归属的存储位置：storageLocationId 与 mountKey 二选一。
     * mountKey 分支要求调用者额外持有系统配置管理权限，并在挂载根查找或创建
     * 系统级存储位置；位置记录独立提交，来源创建失败时可能留下可复用的幂等残留。
     */
    private UUID resolveStorageLocationId(UUID operatorUserId, CreateVideoLibrarySourceRequest request) {
        boolean hasLocationId = request.storageLocationId() != null;
        boolean hasMountKey = request.mountKey() != null && !request.mountKey().isBlank();
        if (hasLocationId == hasMountKey) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "storageLocationId 与 mountKey 必须二选一");
        }
        if (hasLocationId) {
            return request.storageLocationId();
        }
        accessService.requireSystemConfigManage(operatorUserId);
        return storageLocationService
                .findOrCreateSystemLocation(operatorUserId, request.mountKey(), ".")
                .getId();
    }

    /**
     * 删除来源配置及其未应用的扫描记录。
     *
     * <p>已经建立媒体实体的来源不能删除，避免留下无法授权或播放的悬空引用；
     * 调用方应先清理相关媒体实体。</p>
     */
    @Transactional(rollbackFor = Exception.class)
    public void delete(UUID operatorUserId, UUID sourceId) {
        VideoLibrarySource source = accessService.requireManage(operatorUserId, sourceId);
        if (ACTIVE_RUN_STATUSES.contains(source.getScanStatus())) {
            throw new BusinessException(ErrorCode.CONFLICT, "媒体发现或入库期间不能删除影视库来源");
        }
        if (videoItemRepository.countByLibrarySourceId(sourceId) > 0) {
            throw new BusinessException(ErrorCode.RESOURCE_IN_USE, "影视库来源仍有已入库媒体，请先清理媒体实体");
        }
        accessService.deleteForSource(sourceId);
        for (MediaScanRun run : runRepository.findAllByLibrarySourceId(sourceId)) {
            candidateRepository.deleteByScanRunId(run.getId());
            batchRepository.deleteByScanRunId(run.getId());
        }
        runRepository.deleteByLibrarySourceId(sourceId);
        sourceRepository.delete(source);
    }

    /** 更新用户影视库来源。 */
    @Transactional(rollbackFor = Exception.class)
    public VideoLibrarySourceDto update(
            UUID operatorUserId,
            UUID sourceId,
            UpdateVideoLibrarySourceRequest request
    ) {
        VideoLibrarySource source = accessService.requireManage(operatorUserId, sourceId);
        if (ACTIVE_RUN_STATUSES.contains(source.getScanStatus())) {
            throw new BusinessException(ErrorCode.CONFLICT, "媒体发现或入库期间不能修改影视库来源");
        }
        StorageLocation location = storageLocationService.requireAccessibleLocation(
                operatorUserId,
                source.getStorageLocationId()
        );
        String relativeRoot = normalizeRelativeRoot(request.relativeRoot());
        requireNoPathConflict(sourceId, location, relativeRoot);
        MediaLibraryType libraryType = request.libraryType() == null
                ? MediaLibraryType.valueOf(source.getLibraryType())
                : request.libraryType();
        if (source.getLastScannedCount() > 0 && !source.getLibraryType().equals(libraryType.name())) {
            throw new BusinessException(ErrorCode.CONFLICT, "已发现的媒体库不能直接更改类型，请新建来源");
        }
        source.setName(normalizeName(request.name()));
        source.setRelativeRoot(relativeRoot);
        source.setLibraryType(libraryType.name());
        source.setImportPolicy(request.importPolicy() == null
                ? source.getImportPolicy()
                : request.importPolicy().name());
        source.setEnabled(request.enabled());
        source.setHealthStatus(request.enabled() ? source.getHealthStatus() : "DISABLED");
        if (request.enabled() && "DISABLED".equals(source.getHealthStatus())) {
            source.setHealthStatus("AVAILABLE");
        }
        return toDto(sourceRepository.save(source));
    }

    /**
     * 创建只发现候选、不立即写入媒体实体的后台任务。
     */
    @Transactional(rollbackFor = Exception.class)
    public ScrapeTaskDto scan(UUID operatorUserId, UUID sourceId) {
        VideoLibrarySource source = accessService.requireManage(operatorUserId, sourceId);
        UUID catalogOwnerId = source.getOwnerUserId();
        if (!source.isEnabled()) {
            throw new BusinessException(ErrorCode.CONFLICT, "影视库来源已停用");
        }
        if (runRepository.existsByLibrarySourceIdAndStatusIn(sourceId, ACTIVE_RUN_STATUSES)) {
            throw new BusinessException(ErrorCode.CONFLICT, "影视库来源已有发现或入库任务正在执行");
        }
        long generation = runRepository
                .findFirstByLibrarySourceIdOrderByCreatedAtDesc(sourceId)
                .map(previous -> previous.getGeneration() + 1)
                .orElse(1L);
        UUID taskId = UUID.randomUUID();
        MediaScanRun run = new MediaScanRun();
        run.setOwnerUserId(catalogOwnerId);
        run.setLibrarySourceId(sourceId);
        run.setDiscoveryTaskId(taskId);
        run.setGeneration(generation);
        run.setStatus("QUEUED");
        run.setPhase("DISCOVERY");
        MediaScanRun savedRun = runRepository.save(run);

        source.setScanStatus("QUEUED");
        source.setLastErrorCode(null);
        sourceRepository.save(source);
        Map<String, Object> payload = Map.of(
                "catalogOwnerId", catalogOwnerId.toString(),
                "operatorUserId", operatorUserId.toString(),
                "sourceId", sourceId.toString(),
                "scanRunId", savedRun.getId().toString()
        );
        taskRecordService.createQueuedTask(
                taskId,
                operatorUserId,
                DISCOVERY_TASK_TYPE,
                QueueNames.LOCAL_VIDEO_LIBRARY_SCAN_ROUTING_KEY,
                "QUEUED",
                "MEDIA_SCAN_RUN",
                savedRun.getId(),
                payload
        );
        LocalVideoLibraryScanRequestedEvent event = new LocalVideoLibraryScanRequestedEvent(
                taskId,
                catalogOwnerId,
                sourceId,
                savedRun.getId()
        );
        taskDispatchService.enqueue(
                taskId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.LOCAL_VIDEO_LIBRARY_SCAN_ROUTING_KEY,
                event
        );
        return new ScrapeTaskDto(taskId, TaskStatus.QUEUED.getValue(), "媒体发现任务已进入队列");
    }

    /** Worker 执行媒体发现。 */
    public void executeScan(LocalVideoLibraryScanRequestedEvent event) {
        discoveryExecutor.execute(event);
    }

    private MediaLibraryType normalizeLibraryType(MediaLibraryType value) {
        return value == null ? MediaLibraryType.MOVIE : value;
    }

    private MediaImportPolicy normalizeImportPolicy(MediaImportPolicy value) {
        return value == null ? MediaImportPolicy.MANUAL_REVIEW : value;
    }

    private String normalizeName(String value) {
        String name = value == null ? "" : value.trim();
        if (name.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "影视库来源名称不能为空");
        }
        return name;
    }

    private String normalizeRelativeRoot(String value) {
        String raw = value == null || value.isBlank() ? "." : value.trim();
        if (raw.chars().anyMatch(character -> character < 0x20 || character == 0x7f)
                || (raw.length() >= 2 && Character.isLetter(raw.charAt(0)) && raw.charAt(1) == ':')) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "影视库来源必须是安全的相对路径");
        }
        try {
            Path path = Path.of(raw).normalize();
            if (path.isAbsolute() || path.startsWith("..")) {
                throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "影视库来源必须是安全的相对路径");
            }
            String normalized = path.toString().replace('\\', '/');
            return normalized.isBlank() ? "." : normalized;
        } catch (InvalidPathException exception) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "影视库来源路径格式无效");
        }
    }

    /**
     * 校验目标目录不与同挂载下任何既有库源物理重叠。
     *
     * <p>同一挂载可能同时存在挂载根位置和子目录位置（向导登记与挂载直达并存），
     * 仅比较同一位置内的相对根会放行跨位置的物理重叠，导致同一目录重复扫描入库，
     * 因此按"位置相对根 + 库源相对根"拼接后的物理根参与比较。</p>
     */
    private void requireNoPathConflict(UUID sourceId, StorageLocation targetLocation, String relativeRoot) {
        String targetRoot = composePhysicalRoot(targetLocation.getRelativeRoot(), relativeRoot);
        for (StorageLocation location : storageLocationService.listByMountKeyForBusiness(targetLocation.getMountKey())) {
            for (VideoLibrarySource candidate : sourceRepository.findByStorageLocationId(location.getId())) {
                if (sourceId != null && candidate.getId().equals(sourceId)) {
                    continue;
                }
                String candidateRoot = composePhysicalRoot(location.getRelativeRoot(), candidate.getRelativeRoot());
                if (pathsOverlap(candidateRoot, targetRoot)) {
                    throw new BusinessException(ErrorCode.CONFLICT, "该目录与现有媒体库目录重复或重叠");
                }
            }
        }
    }

    private String composePhysicalRoot(String locationRoot, String sourceRoot) {
        String left = isBlankRoot(locationRoot) ? "" : locationRoot;
        String right = isBlankRoot(sourceRoot) ? "" : sourceRoot;
        if (left.isEmpty()) {
            return right;
        }
        return right.isEmpty() ? left : left + "/" + right;
    }

    private boolean isBlankRoot(String value) {
        return value == null || value.isBlank() || ".".equals(value);
    }

    private boolean pathsOverlap(String left, String right) {
        Path leftPath = Path.of(left.toLowerCase(Locale.ROOT)).normalize();
        Path rightPath = Path.of(right.toLowerCase(Locale.ROOT)).normalize();
        return leftPath.equals(rightPath) || leftPath.startsWith(rightPath) || rightPath.startsWith(leftPath);
    }

    private VideoLibrarySourceDto toDto(VideoLibrarySource source) {
        return new VideoLibrarySourceDto(
                source.getId(),
                source.getName(),
                source.getStorageLocationId(),
                source.getRelativeRoot(),
                MediaLibraryType.valueOf(source.getLibraryType()),
                MediaImportPolicy.valueOf(source.getImportPolicy()),
                MediaLibraryVisibility.from(source.getVisibilityType()),
                source.isEnabled(),
                source.getScanStatus(),
                source.getHealthStatus(),
                source.getLastScannedAt(),
                source.getLastSuccessfulScanAt(),
                source.getLastErrorCode(),
                source.getLastScannedCount(),
                source.getLastCreatedCount(),
                source.getLastCandidateCount(),
                source.getLastMissingCount(),
                source.getCreatedAt(),
                source.getUpdatedAt(),
                source.getVersion()
        );
    }
}
