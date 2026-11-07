package com.omninest.modules.quota.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.quota.domain.StorageQuotaReservation;
import com.omninest.modules.quota.repository.StorageQuotaReservationRepository;
import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
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
     * <p>同一来源可重入：目录导入中断后重试会再次申报整个任务大小，已结算部分
     * （{@code committedBytes}）不得重复预留，只补差额；若上一轮已完整结算或
     * 预留已过期，则重新激活原行并补齐未记账字节。否则唯一键会让该来源永远
     * 无法再次预留，或重试期间新入库的字节完全漏记。</p>
     *
     * @param userId 用户 ID
     * @param sourceType 来源类型
     * @param sourceId 来源业务 ID
     * @param bytes 本次来源需要覆盖的总字节数
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
        Instant effectiveExpiry = expiresAt == null ? Instant.now().plusSeconds(86_400L) : expiresAt;
        StorageQuotaReservation existing = reservationRepository
                .findBySourceTypeAndSourceId(normalizedSourceType, sourceId)
                .orElse(null);
        if (existing != null) {
            long committedBytes = existing.getCommittedBytes();
            long heldBytes = RESERVED.equals(existing.getStatus()) ? existing.getReservedBytes() : 0L;
            long coveredBytes = committedBytes + heldBytes;
            if (bytes <= coveredBytes) {
                if (RESERVED.equals(existing.getStatus())) {
                    existing.setExpiresAt(effectiveExpiry);
                    reservationRepository.save(existing);
                }
                return existing.getId();
            }
            long additionalBytes = bytes - coveredBytes;
            boolean quotaApplied;
            if (heldBytes > 0L && existing.isQuotaApplied()) {
                // 续用中的预留必须同样占用额度，否则结算时扣减的 reserved_bytes 大于实际占用。
                reserveAgainstAccount(requireAccount(userId), additionalBytes);
                quotaApplied = true;
            } else if (heldBytes > 0L) {
                // 不受配额约束的来源始终按实际用量记账，扩容时保持同一口径。
                quotaApplied = false;
            } else {
                quotaApplied = reserveAgainstAccount(requireAccount(userId), additionalBytes);
            }
            existing.setReservedBytes(heldBytes + additionalBytes);
            existing.setCommittedBytes(committedBytes);
            existing.setQuotaApplied(quotaApplied);
            existing.setStatus(RESERVED);
            existing.setExpiresAt(effectiveExpiry);
            return reservationRepository.save(existing).getId();
        }

        UserAccountSummary owner = requireAccount(userId);
        boolean quotaApplied = reserveAgainstAccount(owner, bytes);

        StorageQuotaReservation reservation = new StorageQuotaReservation();
        reservation.setOwnerUserId(userId);
        reservation.setSourceType(normalizedSourceType);
        reservation.setSourceId(sourceId);
        reservation.setReservedBytes(bytes);
        reservation.setCommittedBytes(0L);
        reservation.setQuotaApplied(quotaApplied);
        reservation.setStatus(RESERVED);
        reservation.setExpiresAt(effectiveExpiry);
        return reservationRepository.save(reservation).getId();
    }

    /**
     * 查询来源预留最终结算进用量的字节数。
     *
     * <p>删除素材等退还要按真实加计量处理，不能按申报大小：扫描失败的预留从未转入
     * used_bytes，按文件大小扣减会凭空减少用户已用配额。</p>
     *
     * @param sourceType 来源类型
     * @param sourceId 来源业务 ID
     * @return 已结算字节数，无预留记录时返回 0
     */
    @Transactional(readOnly = true)
    public long settledBytes(String sourceType, UUID sourceId) {
        return reservationRepository
                .findBySourceTypeAndSourceId(normalizeSourceType(sourceType), sourceId)
                .map(StorageQuotaReservation::getCommittedBytes)
                .orElse(0L);
    }

    /**
     * 查询来源预留的归属用户，供缓存失效使用。
     *
     * @param sourceType 来源类型
     * @param sourceId 来源业务 ID
     * @return 归属用户；无预留时为空
     */
    @Transactional(readOnly = true)
    public Optional<UUID> ownerUserId(String sourceType, UUID sourceId) {
        return reservationRepository
                .findBySourceTypeAndSourceId(normalizeSourceType(sourceType), sourceId)
                .map(StorageQuotaReservation::getOwnerUserId);
    }

    private UserAccountSummary requireAccount(UUID userId) {
        return userAccountQuery.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
    }

    /**
     * 占用预留额度并返回本次是否受配额约束。
     *
     * <p>配额为 0 或负数表示无限制，与 checkQuota 的口径一致：无需占用预留额度，
     * 结算时直接按实际写入量记入 used_bytes。</p>
     */
    private boolean reserveAgainstAccount(UserAccountSummary owner, long bytes) {
        boolean quotaApplied = !owner.superAdmin() && owner.quotaBytes() > 0;
        if (quotaApplied && !userStorageCommand.tryReserveStorage(owner.id(), bytes)) {
            throw new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "存储配额不足");
        }
        return quotaApplied;
    }

    /**
     * 将来源预留结算为实际落库用量，未使用部分自动释放。
     *
     * <p>结算按增量入账：{@code committedBytes} 记录来源累计已记账字节数，
     * 同一来源重试完成、过期后才补记或重复调用都只处理差额，不会重复计入用量。
     * 预留已结束（COMMITTED / RELEASED / EXPIRED）时若仍报告了新的实际用量，
     * 直接补记差额——过期释放只退回了预留，并不代表字节没有落库。</p>
     *
     * @param sourceType 来源类型
     * @param sourceId 来源业务 ID
     * @param committedBytes 该来源累计实际写入字节数
     */
    @Transactional(rollbackFor = Exception.class)
    public void settle(String sourceType, UUID sourceId, long committedBytes) {
        StorageQuotaReservation reservation = reservationRepository
                .findBySourceTypeAndSourceId(normalizeSourceType(sourceType), sourceId)
                .orElse(null);
        if (reservation == null) {
            return;
        }
        long alreadyCommitted = reservation.getCommittedBytes();
        long requestedCommitted = Math.max(0L, committedBytes);
        if (RESERVED.equals(reservation.getStatus())) {
            long additionalNeeded = Math.max(0L, requestedCommitted - alreadyCommitted);
            long safeAdditional = Math.min(additionalNeeded, reservation.getReservedBytes());
            boolean updated;
            if (reservation.isQuotaApplied()) {
                updated = userStorageCommand.settleStorageReservation(
                        reservation.getOwnerUserId(),
                        reservation.getReservedBytes(),
                        safeAdditional
                );
            } else {
                if (safeAdditional > 0L) {
                    userStorageCommand.incrementUsage(reservation.getOwnerUserId(), safeAdditional);
                }
                updated = true;
            }
            if (!updated) {
                throw new IllegalStateException("存储配额预留结算失败");
            }
            long totalCommitted = alreadyCommitted + safeAdditional;
            reservation.setReservedBytes(0L);
            reservation.setCommittedBytes(totalCommitted);
            reservation.setStatus(totalCommitted == 0L ? RELEASED : COMMITTED);
            reservationRepository.save(reservation);
            return;
        }
        if (requestedCommitted <= alreadyCommitted) {
            return;
        }
        long delta = requestedCommitted - alreadyCommitted;
        userStorageCommand.incrementUsage(reservation.getOwnerUserId(), delta);
        reservation.setReservedBytes(0L);
        reservation.setCommittedBytes(requestedCommitted);
        reservation.setStatus(COMMITTED);
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
        return reclaimExpiredWithOwners().count();
    }

    /**
     * 有界回收过期预留，并返回受影响用户。
     *
     * <p>调用方需要按用户淘汰资料缓存：预留占用体现在用户资料里，回收后不淘汰会让
     * 配额页面在缓存 TTL 内继续显示已经释放的占用。</p>
     *
     * @return 回收数量与涉及的归属用户（去重）
     */
    @Transactional(rollbackFor = Exception.class)
    public ReclaimedReservations reclaimExpiredWithOwners() {
        List<StorageQuotaReservation> expired = reservationRepository
                .findByStatusAndExpiresAtBeforeOrderByExpiresAtAsc(
                        RESERVED,
                        Instant.now(),
                        PageRequest.of(0, RECLAIM_BATCH_SIZE)
                );
        Set<UUID> reclaimedOwners = new LinkedHashSet<>();
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
            reclaimedOwners.add(reservation.getOwnerUserId());
            reclaimedCount++;
        }
        return new ReclaimedReservations(reclaimedCount, List.copyOf(reclaimedOwners));
    }

    /**
     * 过期预留回收结果：数量用于日志与指标，归属用户用于淘汰资料缓存。
     *
     * @param count 回收的预留条数
     * @param ownerUserIds 涉及的归属用户（去重）
     */
    public record ReclaimedReservations(int count, List<UUID> ownerUserIds) {
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
