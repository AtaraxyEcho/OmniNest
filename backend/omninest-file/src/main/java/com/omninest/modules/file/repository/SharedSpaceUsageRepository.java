package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.SharedSpaceUsage;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface SharedSpaceUsageRepository extends JpaRepository<SharedSpaceUsage, UUID> {
    Optional<SharedSpaceUsage> findFirstBy();

    /**
     * 原子增加共享空间用量，容量上限作为更新守卫同条 SQL 判定。
     *
     * <p>共享空间是单行账本，多个成员并发上传必然撞同一行的乐观锁版本。原先在同一个
     * Spring 事务里重试 {@code save} 不生效：版本校验推迟到事务提交才触发，捕获到异常时
     * 事务已标记 rollbackOnly。改成条件更新后，超量与冲突都表现为 0 行受影响。</p>
     *
     * @param id 用量记录 ID
     * @param deltaBytes 新增字节数
     * @param deltaFiles 新增文件数
     * @param maxBytes 容量上限，不限时传足够大的值
     * @param now 更新时间
     * @return 更新行数，0 表示超出容量上限
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update SharedSpaceUsage usage
            set usage.usedBytes = usage.usedBytes + :deltaBytes,
                usage.fileCount = usage.fileCount + :deltaFiles,
                usage.updatedAt = :now,
                usage.version = usage.version + 1
            where usage.id = :id
              and usage.usedBytes + :deltaBytes <= :maxBytes
            """)
    int tryIncreaseUsage(
            @Param("id") UUID id,
            @Param("deltaBytes") long deltaBytes,
            @Param("deltaFiles") long deltaFiles,
            @Param("maxBytes") long maxBytes,
            @Param("now") Instant now
    );

    /**
     * 原子扣减共享空间用量，字节与文件数各自夹到零，不把账本扣成负数。
     *
     * @param id 用量记录 ID
     * @param deltaBytes 释放字节数
     * @param deltaFiles 释放文件数
     * @param now 更新时间
     * @return 更新行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update SharedSpaceUsage usage
            set usage.usedBytes = case when usage.usedBytes > :deltaBytes
                                       then usage.usedBytes - :deltaBytes else 0 end,
                usage.fileCount = case when usage.fileCount > :deltaFiles
                                       then usage.fileCount - :deltaFiles else 0 end,
                usage.updatedAt = :now,
                usage.version = usage.version + 1
            where usage.id = :id
            """)
    int decreaseUsage(
            @Param("id") UUID id,
            @Param("deltaBytes") long deltaBytes,
            @Param("deltaFiles") long deltaFiles,
            @Param("now") Instant now
    );
}
