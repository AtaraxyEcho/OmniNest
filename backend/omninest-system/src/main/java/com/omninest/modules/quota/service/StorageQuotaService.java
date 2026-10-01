package com.omninest.modules.quota.service;

import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.user.UserAccountDetails;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.quota.QuotaStatus;
import com.omninest.modules.quota.port.StorageMetricsQuery;
import com.omninest.modules.quota.port.StorageQuotaPolicy;
import com.omninest.modules.notification.port.NotificationPublisher;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 集中存储配额管理服务。
 * 统一处理配额检查、用量更新、配额修改、定期校准等操作。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StorageQuotaService {
    private static final int USAGE_RECONCILE_BATCH_SIZE = 200;

    private final UserAccountQuery userAccountQuery;
    private final UserStorageCommand userStorageCommand;
    private final StorageMetricsQuery storageMetricsQuery;
    private final StorageQuotaPolicy storageQuotaPolicy;
    private final AdminAuditRecorder auditRecorder;
    private final NotificationPublisher notificationService;
    private final StorageQuotaReservationService reservationService;

    /**
     * 为持久业务来源预留存储配额。
     *
     * @param userId 用户 ID
     * @param sourceType 来源类型
     * @param sourceId 来源 ID
     * @param bytes 预留字节数
     * @param expiresAt 过期时间
     * @return 预留记录 ID
     */
    public UUID reserve(
            UUID userId,
            String sourceType,
            UUID sourceId,
            long bytes,
            Instant expiresAt
    ) {
        return reservationService.reserve(userId, sourceType, sourceId, bytes, expiresAt);
    }

    /**
     * 结算来源预留。
     *
     * @param sourceType 来源类型
     * @param sourceId 来源 ID
     * @param committedBytes 实际使用字节数
     */
    public void settleReservation(String sourceType, UUID sourceId, long committedBytes) {
        reservationService.settle(sourceType, sourceId, committedBytes);
    }

    /**
     * 释放来源预留。
     *
     * @param sourceType 来源类型
     * @param sourceId 来源 ID
     */
    public void releaseReservation(String sourceType, UUID sourceId) {
        reservationService.release(sourceType, sourceId);
    }

    /**
     * 延长来源预留。
     *
     * @param sourceType 来源类型
     * @param sourceId 来源 ID
     * @param expiresAt 新过期时间
     */
    public void extendReservation(String sourceType, UUID sourceId, Instant expiresAt) {
        reservationService.extend(sourceType, sourceId, expiresAt);
    }

    /**
     * 回收一批过期预留。
     *
     * @return 回收数量
     */
    public int reclaimExpiredReservations() {
        return reservationService.reclaimExpired();
    }

    /**
     * 检查用户存储配额是否足够，不足时抛出异常。
     *
     * @param userId       用户 ID
     * @param incomingBytes 待写入字节数
     */
    @Transactional(readOnly = true)
    public void checkQuota(UUID userId, long incomingBytes) {
        UserAccountSummary owner = userAccountQuery.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        if (owner.superAdmin()) {
            return;
        }
        if (owner.usedBytes() + incomingBytes > owner.quotaBytes()) {
            throw new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "存储配额不足");
        }
    }

    /**
     * 增加用户存储用量。
     *
     * @param userId 用户 ID
     * @param bytes  增加字节数
     */
    @Transactional(rollbackFor = Exception.class)
    public void incrementUsage(UUID userId, long bytes) {
        if (bytes <= 0) {
            return;
        }
        UserAccountSummary owner = userStorageCommand.incrementUsage(userId, bytes);

        // 检查配额状态，发送预警通知
        try {
            QuotaStatus status = storageQuotaPolicy.resolveStatus(
                    owner.usedBytes(),
                    owner.quotaBytes(),
                    owner.superAdmin()
            );
            if (status == QuotaStatus.WARNING || status == QuotaStatus.CRITICAL) {
                int percent = owner.quotaBytes() > 0
                        ? (int) (owner.usedBytes() * 100 / owner.quotaBytes()) : 0;
                String title = status == QuotaStatus.CRITICAL ? "存储空间即将满额" : "存储空间预警";
                String message = "存储空间已使用 " + percent + "%，请及时清理";
                notificationService.create(userId, "QUOTA_WARNING", title, message,
                        Map.of("usedBytes", owner.usedBytes(), "quotaBytes", owner.quotaBytes()));
            }
        } catch (Exception e) {
            log.warn("发送配额预警通知失败: userId={}", userId, e);
        }
    }

    /**
     * 减少用户存储用量（文件永久删除时调用）。
     *
     * @param userId 用户 ID
     * @param bytes  释放字节数
     */
    @Transactional(rollbackFor = Exception.class)
    public void decrementUsage(UUID userId, long bytes) {
        if (bytes <= 0) {
            return;
        }
        userStorageCommand.decrementUsage(userId, bytes);
    }

    /**
     * 修改指定用户的存储配额。
     *
     * @param userId       目标用户 ID
     * @param newQuotaBytes 新配额字节数
     * @param operatorId   操作者用户 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateQuota(UUID userId, long newQuotaBytes, UUID operatorId) {
        UserAccountSummary user = userAccountQuery.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "用户不存在"));
        if (user.superAdmin()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "超级管理员配额不能通过管理端修改");
        }
        if (newQuotaBytes < user.usedBytes()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR,
                    "新配额不能小于当前已使用空间（%d 字节）".formatted(user.usedBytes()));
        }
        long oldQuota = user.quotaBytes();
        userStorageCommand.updateQuota(userId, newQuotaBytes);
        auditRecorder.recordWithPayload(
                operatorId,
                "ADMIN_QUOTA_UPDATE",
                "auth_users",
                userId,
                quotaAuditPayload(oldQuota, newQuotaBytes, operatorId)
        );
        log.info("已更新用户存储配额: userId={}, 旧配额={}, 新配额={}", userId, oldQuota, newQuotaBytes);
    }

    /**
     * 修改指定用户的存储配额并返回更新后的账户详情。
     *
     * @param userId 目标用户 ID
     * @param newQuotaBytes 新配额字节数
     * @param operatorId 操作者用户 ID
     * @return 更新后的账户详情
     */
    @Transactional(rollbackFor = Exception.class)
    public UserAccountDetails updateQuotaAndGetDetails(UUID userId, long newQuotaBytes, UUID operatorId) {
        updateQuota(userId, newQuotaBytes, operatorId);
        return userAccountQuery.findDetailsById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "用户不存在"));
    }

    /**
     * 批量修改多个用户的存储配额。
     * 跳过超级管理员和新配额不足的用户，返回实际修改数。
     *
     * @param userIds      目标用户 ID 列表
     * @param newQuotaBytes 新配额字节数
     * @param operatorId   操作者用户 ID
     * @return 实际修改用户数
     */
    @Transactional(rollbackFor = Exception.class)
    public int batchUpdateQuota(List<UUID> userIds, long newQuotaBytes, UUID operatorId) {
        int updated = 0;
        for (UUID userId : userIds) {
            UserAccountSummary user = userAccountQuery.findById(userId).orElse(null);
            if (user == null || user.superAdmin()) {
                continue;
            }
            if (newQuotaBytes < user.usedBytes()) {
                continue;
            }
            long oldQuota = user.quotaBytes();
            userStorageCommand.updateQuota(userId, newQuotaBytes);
            auditRecorder.recordWithPayload(
                    operatorId,
                    "ADMIN_QUOTA_UPDATE",
                    "auth_users",
                    userId,
                    quotaAuditPayload(oldQuota, newQuotaBytes, operatorId)
            );
            updated++;
        }
        if (updated > 0) {
            log.info("批量更新用户存储配额: 目标 {} 人, 实际修改 {} 人, 新配额={} bytes", userIds.size(), updated, newQuotaBytes);
        }
        return updated;
    }

    /**
     * 构建配额变更审计载荷，记录变更前后值与操作者。
     *
     * <p>配额字节数与操作者标识非敏感，可直接进入 detail_payload。</p>
     *
     * @param oldQuotaBytes 变更前配额字节数
     * @param newQuotaBytes 变更后配额字节数
     * @param operatorId 操作者用户 ID
     * @return 变更上下文载荷
     */
    private Map<String, Object> quotaAuditPayload(long oldQuotaBytes, long newQuotaBytes, UUID operatorId) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("oldQuotaBytes", oldQuotaBytes);
        payload.put("newQuotaBytes", newQuotaBytes);
        payload.put("changeBy", operatorId.toString());
        return payload;
    }

    /**
     * 重算所有用户的存储用量（从 file_objects + file_nodes 实际数据）。
     *
     * @return 修正用户数
     */
    public int recalculateAllUsages() {
        int updated = 0;
        UUID cursor = null;
        while (true) {
            List<UUID> userIds = userAccountQuery.findIdsAfter(cursor, USAGE_RECONCILE_BATCH_SIZE);
            if (userIds.isEmpty()) {
                return updated;
            }
            Map<UUID, Long> actualUsage = new LinkedHashMap<>();
            userIds.forEach(userId -> actualUsage.put(userId, 0L));
            actualUsage.putAll(storageMetricsQuery.actualUsageByUsers(userIds));
            updated += userStorageCommand.reconcileUsage(Map.copyOf(actualUsage));
            cursor = userIds.getLast();
            if (userIds.size() < USAGE_RECONCILE_BATCH_SIZE) {
                return updated;
            }
        }
    }

    /**
     * 获取新用户默认存储配额（从 Config Center 读取，单位 GB，返回字节）。
     */
    @Transactional(readOnly = true)
    public long getDefaultQuotaBytes() {
        return storageQuotaPolicy.defaultQuotaBytes();
    }

    /**
     * 计算指定用户的配额状态。
     */
    @Transactional(readOnly = true)
    public QuotaStatus getQuotaStatus(UUID userId) {
        UserAccountSummary user = userAccountQuery.findById(userId).orElse(null);
        if (user == null || user.superAdmin()) {
            return QuotaStatus.NORMAL;
        }
        return storageQuotaPolicy.resolveStatus(user.usedBytes(), user.quotaBytes(), false);
    }

    /**
     * 计算指定用户的配额状态（直接传入数据，避免重复查询）。
     * 超级管理员始终返回 NORMAL。
     */
    @Transactional(readOnly = true)
    public QuotaStatus resolveQuotaStatus(long usedBytes, long quotaBytes, boolean isSuperAdmin) {
        return storageQuotaPolicy.resolveStatus(usedBytes, quotaBytes, isSuperAdmin);
    }

    /**
     * 校准所有用户的存储用量。
     */
    public void reconcileQuotaUsage() {
        int updated = recalculateAllUsages();
        if (updated > 0) {
            log.info("定时配额校准完成，修正 {} 个用户的存储用量", updated);
        }
    }
}
