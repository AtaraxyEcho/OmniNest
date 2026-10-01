package com.omninest.modules.quota.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.quota.domain.StorageQuotaReservation;
import com.omninest.modules.quota.repository.StorageQuotaReservationRepository;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 维护可恢复的存储配额预留及其最终结算。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StorageQuotaReservationService {
    private static final String RESERVED = "RESERVED";
    private static final String COMMITTED = "COMMITTED";
    private static final String RELEASED = "RELEASED";
    private static final String EXPIRED = "EXPIRED";
    private static final int RECLAIM_BATCH_SIZE = 100;

    private final StorageQuotaReservationRepository reservationRepository;
    private final UserStorageCommand userStorageCommand;
    private final UserAccountQuery userAccountQuery;

    /**
     * 为一个持久业务来源原子预留配额。
     *
     * @param userId 用户 ID
     * @param sourceType 来源类型
     * @param sourceId 来源业务 ID
     * @param bytes 预留字节数
     * @param expiresAt 预留过期时间
     * @return 预留记录 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public UUID reserve(
            UUID userId,
            String sourceType,
            UUID sourceId,
            long bytes,
            Instant expiresAt
    ) {
        if (bytes < 0L) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "配额预留字节数不能小于零");
        }
        String normalizedSourceType = normalizeSourceType(sourceType);
        StorageQuotaReservation existing = reservationRepository
                .findBySourceTypeAndSourceId(normalizedSourceType, sourceId)
                .orElse(null);
        if (existing != null) {
            if (existing.getReservedBytes() != bytes) {
                throw new BusinessException(ErrorCode.CONFLICT, "同一来源的配额预留大小不一致");
            }
            if (RESERVED.equals(existing.getStatus()) || COMMITTED.equals(existing.getStatus())) {
                return existing.getId();
            }
            throw new BusinessException(ErrorCode.CONFLICT, "该来源的配额预留已经结束");
        }

        UserAccountSummary owner = userAccountQuery.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        boolean quotaApplied = !owner.superAdmin();
        if (quotaApplied && !userStorageCommand.tryReserveStorage(userId, bytes)) {
            throw new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "存储配额不足");
        }

        StorageQuotaReservation reservation = new StorageQuotaReservation();
        reservation.setOwnerUserId(userId);
        reservation.setSourceType(normalizedSourceType);
        reservation.setSourceId(sourceId);
        reservation.setReservedBytes(bytes);
        reservation.setCommittedBytes(0L);
        reservation.setQuotaApplied(quotaApplied);
        reservation.setStatus(RESERVED);
        reservation.setExpiresAt(expiresAt == null ? Instant.now().plusSeconds(86_400L) : expiresAt);
        return reservationRepository.save(reservation).getId();
    }

    /**
     * 将来源预留结算为实际落库用量，未使用部分自动释放。
     *
     * @param sourceType 来源类型
     * @param sourceId 来源业务 ID
     * @param committedBytes 实际写入字节数
     */
    @Transactional(rollbackFor = Exception.class)
    public void settle(String sourceType, UUID sourceId, long committedBytes) {
        StorageQuotaReservation reservation = reservationRepository
                .findBySourceTypeAndSourceId(normalizeSourceType(sourceType), sourceId)
                .orElse(null);
        if (reservation == null || COMMITTED.equals(reservation.getStatus())
                || RELEASED.equals(reservation.getStatus()) || EXPIRED.equals(reservation.getStatus())) {
            return;
        }
        long safeCommittedBytes = Math.clamp(committedBytes, 0L, reservation.getReservedBytes());
        boolean updated;
        if (reservation.isQuotaApplied()) {
            updated = userStorageCommand.settleStorageReservation(
                    reservation.getOwnerUserId(),
                    reservation.getReservedBytes(),
                    safeCommittedBytes
            );
        } else {
            if (safeCommittedBytes > 0L) {
                userStorageCommand.incrementUsage(reservation.getOwnerUserId(), safeCommittedBytes);
            }
            updated = true;
        }
        if (!updated) {
            throw new IllegalStateException("存储配额预留结算失败");
        }
        reservation.setCommittedBytes(safeCommittedBytes);
        reservation.setStatus(safeCommittedBytes == 0L ? RELEASED : COMMITTED);
        reservationRepository.save(reservation);
    }

    /**
     * 释放尚未使用的来源预留。
     *
     * @param sourceType 来源类型
     * @param sourceId 来源业务 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void release(String sourceType, UUID sourceId) {
        settle(sourceType, sourceId, 0L);
    }

    /**
     * 延长仍在执行的来源预留有效期。
     *
     * @param sourceType 来源类型
     * @param sourceId 来源业务 ID
     * @param expiresAt 新过期时间
     */
    @Transactional(rollbackFor = Exception.class)
    public void extend(String sourceType, UUID sourceId, Instant expiresAt) {
        reservationRepository.findBySourceTypeAndSourceId(normalizeSourceType(sourceType), sourceId)
                .filter(reservation -> RESERVED.equals(reservation.getStatus()))
                .ifPresent(reservation -> {
                    reservation.setExpiresAt(expiresAt);
                    reservationRepository.save(reservation);
                });
    }

    /**
     * 有界回收过期预留。
     *
     * @return 本次回收数量
     */
    @Transactional(rollbackFor = Exception.class)
    public int reclaimExpired() {
        List<StorageQuotaReservation> expired = reservationRepository
                .findByStatusAndExpiresAtBeforeOrderByExpiresAtAsc(
                        RESERVED,
                        Instant.now(),
                        PageRequest.of(0, RECLAIM_BATCH_SIZE)
                );
        int reclaimedCount = 0;
        for (StorageQuotaReservation reservation : expired) {
            if (reservation.isQuotaApplied()
                    && !userStorageCommand.settleStorageReservation(
                    reservation.getOwnerUserId(),
                    reservation.getReservedBytes(),
                    0L
            )) {
                log.warn("回收过期配额预留失败: reservationId={}", reservation.getId());
                continue;
            }
            reservation.setStatus(EXPIRED);
            reservationRepository.save(reservation);
            reclaimedCount++;
        }
        return reclaimedCount;
    }

    private String normalizeSourceType(String sourceType) {
        if (sourceType == null || sourceType.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "配额预留来源类型不能为空");
        }
        String normalized = sourceType.trim().toUpperCase(Locale.ROOT);
        if (normalized.length() > 32) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "配额预留来源类型过长");
        }
        return normalized;
    }

    /**
     * 管理端账户删除配套：物理清空该用户的全部配额预留记录。
     *
     * @param userId 用户标识
     */
    @Transactional(rollbackFor = Exception.class)
    public void adminPurgeForUser(UUID userId) {
        reservationRepository.deleteByOwnerUserId(userId);
    }
}
