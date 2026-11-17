package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.SystemInstance;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 系统实例仓储。
 *
 * @author OmniNest
 */
public interface SystemInstanceRepository extends JpaRepository<SystemInstance, UUID> {

    /**
     * 以写锁读取系统实例，用于串行化首次安装事务。
     *
     * @param id 系统实例标识
     * @return 系统实例
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select systemInstance from SystemInstance systemInstance where systemInstance.id = :id")
    Optional<SystemInstance> findByIdForUpdate(@Param("id") UUID id);
}
