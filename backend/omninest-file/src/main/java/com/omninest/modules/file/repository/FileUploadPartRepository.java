package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileUploadPart;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface FileUploadPartRepository extends JpaRepository<FileUploadPart, UUID> {
    List<FileUploadPart> findByUploadSessionIdOrderByPartNumber(UUID uploadSessionId);

    Optional<FileUploadPart> findByUploadSessionIdAndPartNumber(UUID uploadSessionId, int partNumber);

    /**
     * 原子确认单个分片；已确认的分片不会被重复计数。
     *
     * <p>分片上传有 3 路并发确认，旧实现每次都对会话行 {@code FOR UPDATE} 并全量读取
     * 所有分片，1,000 分片时累计上百万行读取。单行条件更新把锁范围缩到当前分片。</p>
     *
     * @param uploadSessionId 上传会话 ID
     * @param partNumber 分片序号
     * @param eTag 分片 ETag
     * @param completedStatus 完成状态值
     * @return 更新行数，0 表示分片已是完成态
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update FileUploadPart part
               set part.status = :completedStatus,
                   part.eTag = :eTag
             where part.uploadSessionId = :uploadSessionId
               and part.partNumber = :partNumber
               and part.status <> :completedStatus
            """)
    int markPartCompleted(
            @Param("uploadSessionId") UUID uploadSessionId,
            @Param("partNumber") int partNumber,
            @Param("eTag") String eTag,
            @Param("completedStatus") String completedStatus);

    void deleteByUploadSessionId(UUID uploadSessionId);
}
