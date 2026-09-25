package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.dto.FileUploadQueueItemDto;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 上传队列查询服务。
 * 负责展示当前用户的上传会话队列。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileUploadQueueService {
    private final FileUploadSessionRepository uploadSessionRepository;

    /**
     * 查询当前用户的上传队列。
     *
     * @param ownerUserId 用户 ID
     * @return 上传队列条目列表
     */
    @Transactional(readOnly = true)
    public List<FileUploadQueueItemDto> listUploadQueue(UUID ownerUserId) {
        return uploadSessionRepository.findByOwnerUserIdOrderByUpdatedAtDesc(ownerUserId)
                .stream()
                .map(this::toUploadQueueItemDto)
                .toList();
    }

    private FileUploadQueueItemDto toUploadQueueItemDto(FileUploadSession session) {
        return new FileUploadQueueItemDto(
                session.getId(),
                session.getUploadId(),
                session.getTargetParentId(),
                session.getFileName(),
                session.getTotalSizeBytes(),
                session.getPartSizeBytes(),
                session.getTotalParts(),
                session.getUploadedParts(),
                session.getStatus(),
                session.getExpiresAt(),
                session.getUpdatedAt()
        );
    }
}
