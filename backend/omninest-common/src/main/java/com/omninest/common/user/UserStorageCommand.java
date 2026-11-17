package com.omninest.common.user;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 用户存储用量和配额的跨模块写入端口。
 *
 * @author OmniNest
 */
public interface UserStorageCommand {

    /**
     * 增加用户已使用存储并返回更新后的摘要。
     *
     * @param userId 用户 ID
     * @param bytes 增加字节数
     * @return 更新后的用户摘要
     */
    UserAccountSummary incrementUsage(UUID userId, long bytes);

    /**
     * 在配额允许时原子预留用户存储空间。
     *
     * @param userId 用户 ID
     * @param bytes 预留字节数
     * @return 是否成功预留
     */
    boolean tryReserveStorage(UUID userId, long bytes);

    /**
     * 将存储预留原子结算为实际用量。
     *
     * @param userId 用户 ID
     * @param reservedBytes 原预留字节数
     * @param committedBytes 实际使用字节数
     * @return 是否成功结算
     */
    boolean settleStorageReservation(UUID userId, long reservedBytes, long committedBytes);

    /**
     * 减少用户已使用存储。
     *
     * @param userId 用户 ID
     * @param bytes 减少字节数
     */
    void decrementUsage(UUID userId, long bytes);

    /**
     * 设置用户存储配额。
     *
     * @param userId 用户 ID
     * @param quotaBytes 配额字节数
     */
    void updateQuota(UUID userId, long quotaBytes);

    /**
     * 批量设置用户存储配额。
     *
     * <p>只更新配额列，避免逐户整行 {@code save} 覆盖并发修改的密码、昵称与用量。</p>
     *
     * @param userIds 目标用户 ID 集合
     * @param quotaBytes 配额字节数
     * @return 更新的行数
     */
    int updateQuotaBatch(Collection<UUID> userIds, long quotaBytes);

    /**
     * 按实际用量校准指定批次用户的已使用存储。
     *
     * @param actualUsage 以用户 ID 为键的实际用量
     * @return 实际发生变更的用户 ID 列表，供调用方淘汰各自的资料缓存
     */
    List<UUID> reconcileUsage(Map<UUID, Long> actualUsage);
}
