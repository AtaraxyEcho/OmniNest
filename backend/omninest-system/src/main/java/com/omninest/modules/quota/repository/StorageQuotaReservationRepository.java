package com.omninest.modules.quota.repository;

import com.omninest.modules.quota.domain.StorageQuotaReservation;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 存储配额预留仓储。
 *
 * @author OmniNest
 */
public interface StorageQuotaReservationRepository extends JpaRepository<StorageQuotaReservation, UUID> {
    Optional<StorageQuotaReservation> findBySourceTypeAndSourceId(String sourceType, UUID sourceId);

    List<StorageQuotaReservation> findByStatusAndExpiresAtBeforeOrderByExpiresAtAsc(
            String status,
            Instant expiresAt,
            Pageable pageable
    );

    /**
     * 删除用户全部配额预留记录，供管理端物理删除空账户使用。
     *
     * @param userId 用户标识
     * @return 删除数量
     */
    @Modifying
    @Query("delete from StorageQuotaReservation reservation where reservation.ownerUserId = :userId")
    int deleteByOwnerUserId(@Param("userId") UUID userId);
}
