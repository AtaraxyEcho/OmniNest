package com.omninest.modules.file.service;

import com.omninest.common.api.PageClamps;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.dto.FileUploadQueueItemDto;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
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
     * 分页查询当前用户的上传队列。
     *
     * <p>分页必须下沉到数据库：历史实现先取全部会话再在 JVM 内切片，
     * 长时间使用后队列会随行数线性占用内存。</p>
     *
     * @param ownerUserId 用户 ID
     * @param page 页码（从 0 开始）
     * @param size 每页条数
     * @return 上传队列分页
     */
    @Transactional(readOnly = true)
    public Page<FileUploadQueueItemDto> listUploadQueue(UUID ownerUserId, int page, int size) {
        return uploadSessionRepository
                .findByOwnerUserId(
                        ownerUserId,
                        PageRequest.of(
                                PageClamps.safePage(page),
                                PageClamps.safeSize(size),
                                Sort.by(Sort.Direction.DESC, "updatedAt")))
                .map(this::toUploadQueueItemDto);
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
