package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileUploadSession;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FileUploadSessionRepository extends JpaRepository<FileUploadSession, UUID> {
    Optional<FileUploadSession> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    Optional<FileUploadSession> findByUploadIdAndOwnerUserId(String uploadId, UUID ownerUserId);

    /**
     * 查询并锁定上传会话，串行化所有会改变会话状态的操作。
     *
     * @param uploadId 对象存储上传标识
     * @param ownerUserId 所有者用户 ID
     * @return 被锁定的上传会话
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            SELECT session
            FROM FileUploadSession session
            WHERE session.uploadId = :uploadId
              AND session.ownerUserId = :ownerUserId
            """)
    Optional<FileUploadSession> findForUpdateByUploadIdAndOwnerUserId(
            @Param("uploadId") String uploadId,
            @Param("ownerUserId") UUID ownerUserId);

    List<FileUploadSession> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);

    List<FileUploadSession> findByStatusAndUpdatedAtBefore(String status, Instant updatedAt);

    Optional<FileUploadSession> findFirstByOwnerUserIdAndResultObjectId(
            UUID ownerUserId,
            UUID resultObjectId
    );

    Optional<FileUploadSession> findFirstByOwnerUserIdAndResultObjectIdAndStatus(
            UUID ownerUserId,
            UUID resultObjectId,
            String status
    );

    List<FileUploadSession> findByStatusInAndUpdatedAtBefore(List<String> statuses, Instant updatedAt);

    @Query("""
            select s from FileUploadSession s
            where s.status in :statuses and s.updatedAt < :updatedAt
              and s.id > :afterId
            order by s.id
            """)
    List<FileUploadSession> findExpiredAfter(
            @Param("statuses") List<String> statuses,
            @Param("updatedAt") Instant updatedAt,
            @Param("afterId") UUID afterId,
            Pageable pageable);

    Optional<FileUploadSession> findByIngressItemId(UUID ingressItemId);

}
