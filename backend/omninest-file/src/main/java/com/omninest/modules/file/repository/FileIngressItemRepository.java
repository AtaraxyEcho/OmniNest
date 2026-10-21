package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileIngressItem;
import com.omninest.modules.file.domain.FileIngressStatus;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 文件安全入库状态仓储。
 *
 * @author OmniNest
 */
public interface FileIngressItemRepository extends JpaRepository<FileIngressItem, UUID> {

    /**
     * 按上传会话查询入库状态。
     *
     * @param uploadSessionId 上传会话标识
     * @return 入库状态
     */
    Optional<FileIngressItem> findByUploadSessionId(UUID uploadSessionId);

    /**
     * 查询指定状态下、更新时间早于截止时间的入库记录，供保留期回收使用。
     *
     * @param statuses 状态集合
     * @param cutoff 截止时间
     * @return 入库记录列表
     */
    List<FileIngressItem> findByStatusInAndUpdatedAtBefore(List<FileIngressStatus> statuses, Instant cutoff);

    /**
     * 查询候选对象键中由处于指定状态的入库记录持有的目标键。
     *
     * <p>入库记录在受理扫描时就登记了原件桶的目标键，而对象要等扫描通过后的晋升复制才真正存在，
     * 因此记录行是目标键的意图登记：只要记录还在扫描或待晋升阶段，该键上的字节就仍归入库流程所有，
     * 对象存储孤儿审计必须排除。</p>
     *
     * @param bucketName 存储桶名称
     * @param statuses 视为"在途"的入库状态
     * @param objectKeys 候选对象键
     * @return 被在途入库记录持有的目标对象键
     */
    @Query("""
            select item.targetObjectKey
            from FileIngressItem item
            where item.targetBucket = :bucketName
              and item.status in :statuses
              and item.targetObjectKey in :objectKeys
            """)
    List<String> findInFlightObjectKeys(
            @Param("bucketName") String bucketName,
            @Param("statuses") Collection<FileIngressStatus> statuses,
            @Param("objectKeys") Collection<String> objectKeys
    );
}
