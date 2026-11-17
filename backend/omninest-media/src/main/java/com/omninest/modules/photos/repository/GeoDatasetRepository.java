package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.GeoDataset;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * GeoNames 数据集版本仓储。
 *
 * @author OmniNest
 */
public interface GeoDatasetRepository extends JpaRepository<GeoDataset, UUID> {

    /** @return 按版本号查询数据集 */
    Optional<GeoDataset> findByDatasetVersion(String datasetVersion);

    /** @return 当前已发布数据集（正常任意时刻至多一个，按发布时间取最新保证确定性） */
    Optional<GeoDataset> findFirstByStatusOrderByPublishedAtDesc(String status);

    /** @return 同一 dump 日期前缀下已有数据集数量，用于版本号排序 */
    long countByDatasetVersionStartingWith(String prefix);

    /**
     * 发布原子交换时锁定当前已发布数据集行，避免并发发布互相覆盖。
     *
     * @param status 数据集状态
     * @return 锁定的数据集
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select d from GeoDataset d where d.status = :status order by d.publishedAt desc")
    Optional<GeoDataset> findFirstByStatusForUpdate(@Param("status") String status);
}
