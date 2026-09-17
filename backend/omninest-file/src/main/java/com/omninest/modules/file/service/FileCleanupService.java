package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.UploadStatus;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * 在 Scheduler 角色中清理过期文件和上传会话。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(prefix = "omninest.runtime", name = "role", havingValue = "scheduler")
public class FileCleanupService {

    private static final int BATCH_SIZE = 500;
    private static final int MAX_BATCHES_PER_RUN = 20;
    private static final UUID CURSOR_START = new UUID(0L, 0L);

    private final FileNodeRepository fileNodeRepository;
    private final FileUploadSessionRepository uploadSessionRepository;
    private final FileDeletionService fileDeletionService;
    private final FileUploadSessionService fileUploadSessionService;

    @Scheduled(cron = "0 0 4 * * *")
    public void purgeExpiredRecycleBin() {
        Instant cutoff = Instant.now().minus(30, ChronoUnit.DAYS);
        int purged = 0;
        int batches = 0;
        UUID cursor = CURSOR_START;
        while (batches < MAX_BATCHES_PER_RUN) {
            List<FileNode> expired = fileNodeRepository.findExpiredDeletedNodesAfter(
                    cutoff, cursor, PageRequest.of(0, BATCH_SIZE));
            if (expired.isEmpty()) {
                break;
            }
            Map<UUID, List<FileNode>> byOwner = expired.stream()
                    .collect(Collectors.groupingBy(FileNode::getOwnerUserId));
            for (var entry : byOwner.entrySet()) {
                UUID ownerUserId = entry.getKey();
                for (FileNode node : entry.getValue()) {
                    try {
                        fileDeletionService.deletePermanently(ownerUserId, node.getId());
                        purged++;
                    } catch (Exception e) {
                        log.warn("回收站自动清理失败: nodeId={}", node.getId(), e);
                    }
                }
            }
            cursor = expired.getLast().getId();
            batches++;
            if (expired.size() < BATCH_SIZE) {
                break;
            }
        }
        log.info("回收站自动清理: purged={}, batches={}", purged, batches);
    }

    @Scheduled(cron = "0 30 4 * * *")
    public void cleanupExpiredUploadSessions() {
        Instant cutoff = Instant.now().minus(7, ChronoUnit.DAYS);
        List<String> statuses = List.of(
                UploadStatus.CREATED.getValue(),
                UploadStatus.UPLOADING.getValue(),
                UploadStatus.FINALIZING.getValue(),
                UploadStatus.SCANNING.getValue(),
                UploadStatus.REJECTED.getValue(),
                UploadStatus.EXPIRED.getValue()
        );
        int cleaned = 0;
        int batches = 0;
        UUID cursor = CURSOR_START;
        while (batches < MAX_BATCHES_PER_RUN) {
            List<FileUploadSession> expired = uploadSessionRepository.findExpiredAfter(
                    statuses, cutoff, cursor, PageRequest.of(0, BATCH_SIZE));
            if (expired.isEmpty()) {
                break;
            }
            for (FileUploadSession session : expired) {
                try {
                    fileUploadSessionService.cancelSession(session.getOwnerUserId(), session.getUploadId());
                    cleaned++;
                } catch (Exception e) {
                    log.warn("过期上传会话清理失败: uploadId={}", session.getUploadId(), e);
                }
            }
            cursor = expired.getLast().getId();
            batches++;
            if (expired.size() < BATCH_SIZE) {
                break;
            }
        }
        log.info("过期上传会话清理: cleaned={}, batches={}", cleaned, batches);
    }
}
