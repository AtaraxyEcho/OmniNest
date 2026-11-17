package com.omninest.modules.sync.repository;

import com.omninest.modules.sync.domain.SyncEventCheckpoint;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 同步事件检查点仓储。
 *
 * @author OmniNest
 */
public interface SyncEventCheckpointRepository extends JpaRepository<SyncEventCheckpoint, UUID> {

    /**
     * 按检查点键查询记录。
     *
     * @param checkpointKey 检查点键
     * @return 检查点记录
     */
    Optional<SyncEventCheckpoint> findByCheckpointKey(String checkpointKey);

    /**
     * 使用数据库悲观锁读取待更新检查点。
     *
     * @param checkpointKey 检查点键
     * @return 检查点记录
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select checkpoint from SyncEventCheckpoint checkpoint where checkpoint.checkpointKey = :checkpointKey")
    Optional<SyncEventCheckpoint> findForUpdateByCheckpointKey(
            @Param("checkpointKey") String checkpointKey
    );
}
