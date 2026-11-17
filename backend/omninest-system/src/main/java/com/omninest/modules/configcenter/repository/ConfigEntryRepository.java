package com.omninest.modules.configcenter.repository;

import com.omninest.modules.configcenter.domain.ConfigEntry;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ConfigEntryRepository extends JpaRepository<ConfigEntry, UUID> {
    boolean existsByConfigKey(String configKey);

    Optional<ConfigEntry> findByConfigKey(String configKey);

    /**
     * 以悲观锁读取目录锚点，串行化多 API 实例的启动迁移。
     *
     * @param configKey 配置键
     * @return 锚点配置
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select entry from ConfigEntry entry where entry.configKey = :configKey")
    Optional<ConfigEntry> findByConfigKeyForUpdate(@Param("configKey") String configKey);
}
