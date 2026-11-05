package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.FileIngressItem;
import com.omninest.modules.file.domain.FileIngressStatus;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

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
     * 分页查询指定状态下、更新时间早于截止时间的入库记录，供保留期回收使用。
     *
     * <p>必须分页：滞留记录可能一次积累数千条，全量载入再逐条删隔离对象会让
     * 调度线程长时间占用大对象堆。状态条件在执行删除时还会再校验一次。</p>
     *
     * @param statuses 状态集合
     * @param cutoff 截止时间
     * @param pageable 分页参数
     * @return 入库记录分页
     */
    Page<FileIngressItem> findByStatusInAndUpdatedAtBefore(
            Collection<FileIngressStatus> statuses,
            Instant cutoff,
            Pageable pageable);

    /**
     * 仅当记录仍处于可回收状态时删除，返回受影响行数。
     *
     * <p>查询与删除之间 Worker 可能已完成扫描晋升为 {@code AVAILABLE}；
     * 无状态条件的删除会抹掉已发布文件的结果节点引用。</p>
     *
     * @param id 入库记录标识
     * @param statuses 可回收状态集合
     * @return 删除行数
     */
    @Transactional
    @Modifying
    @Query("delete from FileIngressItem item where item.id = :id and item.status in :statuses")
    int deleteByIdAndStatusIn(
            @Param("id") UUID id,
            @Param("statuses") Collection<FileIngressStatus> statuses);

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
    /**
     * 统计某个导入任务已成功晋升为文件节点的字节数。
     *
     * <p>任务进度列里的 transferredBytes 包含临时下载与失败文件，不能用于配额结算；
     * 只统计 result_file_node_id 非空的入库记录才是真实占用空间。</p>
     *
     * @param sourceTaskId 导入任务标识
     * @return 已入库字节数
     */
    @Query("""
            select coalesce(sum(item.sizeBytes), 0)
            from FileIngressItem item
            where item.sourceTaskId = :sourceTaskId
              and item.resultFileNodeId is not null
            """)
    long sumImportedBytesByTaskId(@Param("sourceTaskId") UUID sourceTaskId);

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
