package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoBatchTask;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 照片批量任务仓储接口
 */
public interface PhotoBatchTaskRepository extends JpaRepository<PhotoBatchTask, UUID> {

    /**
     * 按ID和用户查询批量任务
     */
    Optional<PhotoBatchTask> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    /**
     * 按用户查询批量任务列表，按创建时间倒序
     */
    List<PhotoBatchTask> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId);

    /**
     * 查询超过保留期且已进入终态的批量任务，用于清理打包结果。
     *
     * @param statuses 终态集合
     * @param cutoff 最后更新时间上限
     * @param pageable 批次大小
     * @return 过期任务，按更新时间升序
     */
    @Query("""
            SELECT task FROM PhotoBatchTask task
            WHERE task.status IN :statuses
              AND task.updatedAt < :cutoff
            ORDER BY task.updatedAt ASC
            """)
    List<PhotoBatchTask> findTerminalBefore(
            @Param("statuses") Collection<String> statuses,
            @Param("cutoff") Instant cutoff,
            Pageable pageable);
}
