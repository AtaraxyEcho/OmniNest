package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileUploadSession;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FileUploadSessionRepository extends JpaRepository<FileUploadSession, UUID> {

    /**
     * 统计用户处于指定状态且尚未过期（expiresAt 晚于给定时刻）的上传会话数量，
     * 用于活跃会话并发上限；已被放弃但未被回收任务标记的过期会话不占名额。
     */
    long countByOwnerUserIdAndStatusInAndExpiresAtAfter(
            UUID ownerUserId,
            Collection<String> statuses,
            Instant expiresAfter
    );
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

    /**
     * 原子累加已完成分片数并推进状态，避免分片确认路径对会话行加悲观锁。
     *
     * @param id 会话 ID
     * @param now 更新时间
     * @return 更新行数，0 表示会话已被取消或进入终态
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update FileUploadSession session
               set session.uploadedParts = session.uploadedParts + 1,
                   session.status = case when session.status = 'CREATED'
                                         then 'UPLOADING' else session.status end,
                   session.updatedAt = :now
             where session.id = :id
               and session.status in ('CREATED', 'UPLOADING')
            """)
    int incrementUploadedParts(@Param("id") UUID id, @Param("now") Instant now);

    /**
     * 会话剩余有效期不足阈值时原子延期，避免并发分片确认互相覆盖过期时间。
     *
     * @param id 会话 ID
     * @param threshold 需要延期的截止时间阈值
     * @param newExpiresAt 新过期时间
     * @param now 更新时间
     * @return 更新行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update FileUploadSession session
               set session.expiresAt = :newExpiresAt,
                   session.updatedAt = :now
             where session.id = :id
               and session.expiresAt < :threshold
            """)
    int extendExpiresAtIfNeeded(
            @Param("id") UUID id,
            @Param("threshold") Instant threshold,
            @Param("newExpiresAt") Instant newExpiresAt,
            @Param("now") Instant now);

    List<FileUploadSession> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);

    Page<FileUploadSession> findByOwnerUserId(UUID ownerUserId, Pageable pageable);

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
