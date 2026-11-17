package com.omninest.modules.quota.service;

import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.user.UserAccountDetails;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.quota.QuotaStatus;
import com.omninest.modules.quota.port.AdminActorVerifier;
import com.omninest.modules.quota.port.StorageMetricsQuery;
import com.omninest.modules.quota.port.StorageQuotaPolicy;
import com.omninest.modules.quota.port.UserProfileCacheEvictor;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

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
    private final StorageQuotaReservationService reservationService;
    private final AdminActorVerifier adminActorVerifier;
    private final UserProfileCacheEvictor userProfileCacheEvictor;
    private final QuotaNotificationDispatcher quotaNotificationDispatcher;

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
     * <p>定期结算才是主上传链路（普通上传晋升、外部导入、壁纸上传）真正把字节记进
     * {@code used_bytes} 的地方，因此配额阈值告警必须挂在这里，只挂 {@code incrementUsage}
     * 会让用户"正常上传占满空间却永远收不到预警"。</p>
     *
     * @param sourceType 来源类型
     * @param sourceId 来源 ID
     * @param committedBytes 实际使用字节数
     */
    public void settleReservation(String sourceType, UUID sourceId, long committedBytes) {
        reservationService.settle(sourceType, sourceId, committedBytes);
        reservationService.ownerUserId(sourceType, sourceId).ifPresent(userId -> {
            evictProfileCacheAfterCommit(userId);
            userAccountQuery.findById(userId).ifPresent(owner -> notifyQuotaStatus(userId, owner));
        });
    }

    /**
     * 释放来源预留。
     *
     * @param sourceType 来源类型
     * @param sourceId 来源 ID
     */
    public void releaseReservation(String sourceType, UUID sourceId) {
        reservationService.release(sourceType, sourceId);
        // 预留占用会出现在用户资料里，释放后不淘汰缓存会让配额页面在 TTL 内继续显示旧占用。
        reservationService.ownerUserId(sourceType, sourceId)
                .ifPresent(this::evictProfileCacheAfterCommit);
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
     * 查询来源预留最终结算进用量的字节数，供删除时按真实加计量退还。
     *
     * @param sourceType 来源类型
     * @param sourceId 来源 ID
     * @return 已结算字节数，无预留记录时返回 0
     */
    public long settledBytes(String sourceType, UUID sourceId) {
        return reservationService.settledBytes(sourceType, sourceId);
    }

    /**
     * 回收一批过期预留。
     *
     * <p>过期回收同样改动了用户的 reserved_bytes，必须同步淘汰资料缓存。</p>
     *
     * @return 回收数量
     */
    public int reclaimExpiredReservations() {
        StorageQuotaReservationService.ReclaimedReservations reclaimed =
                reservationService.reclaimExpiredWithOwners();
        reclaimed.ownerUserIds().forEach(this::evictProfileCacheAfterCommit);
        return reclaimed.count();
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
        // 配额为 0 或负数表示无限制，必须与 RuntimeStorageQuotaPolicy.resolveStatus 的口径一致，
        // 否则无限额账户的上传会在预检阶段被当成零配额拒绝。
        if (owner.superAdmin() || owner.quotaBytes() <= 0) {
            return;
        }
        long projected;
        try {
            projected = Math.addExact(
                    Math.addExact(owner.usedBytes(), owner.reservedBytes()),
                    Math.max(0L, incomingBytes)
            );
        } catch (ArithmeticException overflow) {
            throw new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "存储配额不足");
        }
        if (projected > owner.quotaBytes()) {
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
        evictProfileCacheAfterCommit(userId);
        notifyQuotaStatus(userId, owner);
    }

    /**
     * 原子计入一笔实际用量。
     *
     * <p>受限账户先以条件更新预留，再在同一事务内结算为已用字节。并发请求不会
     * 同时通过 {@link #checkQuota} 后一起写入，避免配额被写超。无限额账户直接累加。</p>
     *
     * @param userId 用户 ID
     * @param bytes 实际使用字节数
     */
    @Transactional(rollbackFor = Exception.class)
    public void chargeUsage(UUID userId, long bytes) {
        if (bytes <= 0) {
            return;
        }
        UserAccountSummary owner = userAccountQuery.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        if (owner.superAdmin() || owner.quotaBytes() <= 0) {
            UserAccountSummary updated = userStorageCommand.incrementUsage(userId, bytes);
            evictProfileCacheAfterCommit(userId);
            notifyQuotaStatus(userId, updated);
            return;
        }
        if (!userStorageCommand.tryReserveStorage(userId, bytes)
                || !userStorageCommand.settleStorageReservation(userId, bytes, bytes)) {
            throw new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "存储配额不足");
        }
        UserAccountSummary updated = userAccountQuery.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        evictProfileCacheAfterCommit(userId);
        notifyQuotaStatus(userId, updated);
    }

    private void notifyQuotaStatus(UUID userId, UserAccountSummary owner) {
        try {
            QuotaStatus status = storageQuotaPolicy.resolveStatus(
                    owner.usedBytes(),
                    owner.quotaBytes(),
                    owner.superAdmin()
            );
            if (status != QuotaStatus.WARNING && status != QuotaStatus.CRITICAL) {
                return;
            }
            int percent = owner.quotaBytes() > 0
                    ? (int) (owner.usedBytes() * 100 / owner.quotaBytes()) : 0;
            String title = status == QuotaStatus.CRITICAL ? "存储空间即将满额" : "存储空间预警";
            String message = "存储空间已使用 " + percent + "%，请及时清理";
            Map<String, Object> metadata =
                    Map.of("usedBytes", owner.usedBytes(), "quotaBytes", owner.quotaBytes());
            // 只在主事务真正提交后投递：回滚时不能留下幽灵预警；
            // 投递走独立线程，主线程不必在持有连接时等待第二条连接。
            if (TransactionSynchronizationManager.isSynchronizationActive()) {
                TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                    @Override
                    public void afterCommit() {
                        quotaNotificationDispatcher.dispatch(userId, "QUOTA_WARNING", title, message, metadata);
                    }
                });
                return;
            }
            quotaNotificationDispatcher.dispatch(userId, "QUOTA_WARNING", title, message, metadata);
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
        evictProfileCacheAfterCommit(userId);
    }

    /**
     * 配额变更提交后再清用户资料缓存，避免并发读在提交前把旧用量重新写回缓存。
     */
    private void evictProfileCacheAfterCommit(UUID userId) {
        userProfileCacheEvictor.evictProfileCacheAfterCommit(userId);
    }

    /**
     * 修改指定用户的存储配额。
     *
     * <p>操作者以库内当前角色绑定复核，不采信访问令牌里的 roles 声明：降权后旧令牌在有效期内
     * 仍能通过接口上的 {@code @PreAuthorize}，配额这类管理端写操作必须当场拒绝。</p>
     *
     * @param userId       目标用户 ID
     * @param newQuotaBytes 新配额字节数
     * @param operatorId 操作者用户 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void updateQuota(UUID userId, long newQuotaBytes, UUID operatorId) {
        adminActorVerifier.requireFreshAdminActor(operatorId);
        UserAccountSummary user = userAccountQuery.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "用户不存在"));
        if (user.superAdmin()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "超级管理员配额不能通过管理端修改");
        }
        // 配额是自我提权最近的一条路：自改、改同级管理员与设无限制都要更高层级把关。
        adminActorVerifier.requireQuotaMutationAuthority(
                operatorId, userId, newQuotaBytes <= 0);
        // 0 表示无限制，允许在已有用量时改回无限额；只有正数配额需要拦住低于已用量的设置。
        if (newQuotaBytes > 0 && newQuotaBytes < user.usedBytes()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR,
                    "新配额不能小于当前已使用空间（%d 字节）".formatted(user.usedBytes()));
        }
        long oldQuota = user.quotaBytes();
        userStorageCommand.updateQuota(userId, newQuotaBytes);
        // 资料缓存含配额字段，管理端改完必须驱逐，否则用户五分钟内读到的仍是旧配额
        evictProfileCacheAfterCommit(userId);
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
     * <p>批量入口的判定顺序必须是“先定位目标、再校验权限”：管理台“全选本页”天然包含
     * 操作者自身与超级管理员，若先做逐条权限校验，会因“不能修改自己的配额”直接 403
     * 让整批回滚，用户永远无法使用批量调额。</p>
     *
     * <p>操作者权限在循环外加载一次，目标用户与管理员身份各用一条批量查询解析，
     * 配额更新走单条 UPDATE，避免 4N 级 N+1。</p>
     *
     * @param userIds      目标用户 ID 列表
     * @param newQuotaBytes 新配额字节数
     * @param operatorId   操作者用户 ID
     * @return 实际修改用户数
     */
    @Transactional(rollbackFor = Exception.class)
    public int batchUpdateQuota(List<UUID> userIds, long newQuotaBytes, UUID operatorId) {
        if (userIds == null || userIds.isEmpty()) {
            return 0;
        }
        boolean operatorIsSuperAdmin = adminActorVerifier.requireFreshAdminAndCheckSuperAdmin(operatorId);
        if (!operatorIsSuperAdmin && newQuotaBytes <= 0) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "仅超级管理员可将存储配额设为无限制");
        }
        Set<UUID> targets = new LinkedHashSet<>(userIds);
        // 批量场景按“跳过操作者自身”处理，而不是照搬单条入口的拒绝语义。
        targets.remove(operatorId);
        if (targets.isEmpty()) {
            return 0;
        }
        Map<UUID, UserAccountSummary> summaries = userAccountQuery.findSummariesByIds(targets);
        Set<UUID> adminTargets = operatorIsSuperAdmin
                ? Set.of()
                : userAccountQuery.findAdminUserIds(targets);
        List<UserAccountSummary> updatable = new ArrayList<>();
        for (UUID userId : targets) {
            UserAccountSummary user = summaries.get(userId);
            if (user == null || user.superAdmin()) {
                continue;
            }
            // 普通管理员不得在批量列表里夹带同级管理员：越权必须显式失败，不能静默跳过。
            if (adminTargets.contains(userId)) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "仅超级管理员可调整管理员的存储配额");
            }
            // 0 表示无限制，批量修改同样允许已用账号切到无限额。
            if (newQuotaBytes > 0 && newQuotaBytes < user.usedBytes()) {
                continue;
            }
            updatable.add(user);
        }
        if (updatable.isEmpty()) {
            return 0;
        }
        List<UUID> targetIds = updatable.stream().map(UserAccountSummary::id).toList();
        userStorageCommand.updateQuotaBatch(targetIds, newQuotaBytes);
        for (UserAccountSummary user : updatable) {
            evictProfileCacheAfterCommit(user.id());
            auditRecorder.recordWithPayload(
                    operatorId,
                    "ADMIN_QUOTA_UPDATE",
                    "auth_users",
                    user.id(),
                    quotaAuditPayload(user.quotaBytes(), newQuotaBytes, operatorId)
            );
        }
        log.info("批量更新用户存储配额: 目标 {} 人, 实际修改 {} 人, 新配额={} bytes",
                userIds.size(), updatable.size(), newQuotaBytes);
        return updatable.size();
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
     * <p>对账修正的是用户资料里的 {@code used_bytes}，必须同步淘汰该用户的 Redis 资料缓存，
     * 否则个人中心与顶栏在缓存 TTL 内仍展示修正前的错误用量。</p>
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
            List<UUID> changedUserIds = userStorageCommand.reconcileUsage(Map.copyOf(actualUsage));
            changedUserIds.forEach(this::evictProfileCacheAfterCommit);
            updated += changedUserIds.size();
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
