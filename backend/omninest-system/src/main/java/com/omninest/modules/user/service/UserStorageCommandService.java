package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.Roles;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.common.user.UserStorageCommand;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 用户存储状态写入服务，集中维护账户配额和已使用字节数。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class UserStorageCommandService implements UserStorageCommand {

    private final AuthUserRepository authUserRepository;

    /**
     * 增加用户已使用存储并返回更新后的摘要。
     *
     * @param userId 用户 ID
     * @param bytes 增加字节数
     * @return 更新后的用户摘要
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public UserAccountSummary incrementUsage(UUID userId, long bytes) {
        if (authUserRepository.incrementUsageAtomic(userId, bytes) == 0) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在");
        }
        AuthUser user = authUserRepository.findWithRolesById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在"));
        return toSummary(user);
    }

    /**
     * 在配额允许时原子预留用户存储空间。
     *
     * @param userId 用户 ID
     * @param bytes 预留字节数
     * @return 是否成功预留
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean tryReserveStorage(UUID userId, long bytes) {
        return authUserRepository.reserveStorage(userId, bytes) == 1;
    }

    /**
     * 将存储预留原子结算为实际用量。
     *
     * @param userId 用户 ID
     * @param reservedBytes 原预留字节数
     * @param committedBytes 实际使用字节数
     * @return 是否成功结算
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public boolean settleStorageReservation(UUID userId, long reservedBytes, long committedBytes) {
        return authUserRepository.settleStorageReservation(userId, reservedBytes, committedBytes) == 1;
    }

    /**
     * 减少用户已使用存储。
     *
     * @param userId 用户 ID
     * @param bytes 减少字节数
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void decrementUsage(UUID userId, long bytes) {
        if (authUserRepository.decrementUsageAtomic(userId, bytes) == 0) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "当前用户不存在");
        }
    }

    /**
     * 设置用户存储配额。
     *
     * @param userId 用户 ID
     * @param quotaBytes 配额字节数
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void updateQuota(UUID userId, long quotaBytes) {
        AuthUser user = authUserRepository.findById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "用户不存在"));
        user.setQuotaBytes(quotaBytes);
        authUserRepository.save(user);
    }

    /**
     * 批量设置存储配额。
     *
     * <p>单条 UPDATE 只改配额列，既消除逐户读取 + 整行写回的 N+1，也避免把并发修改的
     * 密码、昵称、用量覆盖回旧快照。</p>
     *
     * @param userIds 目标用户 ID 集合
     * @param quotaBytes 配额字节数
     * @return 更新的行数
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public int updateQuotaBatch(Collection<UUID> userIds, long quotaBytes) {
        if (userIds == null || userIds.isEmpty()) {
            return 0;
        }
        return authUserRepository.updateQuotaBatch(userIds, quotaBytes);
    }

    /**
     * 按实际用量校准指定批次用户的已使用存储。
     *
     * @param actualUsage 以用户 ID 为键的实际用量
     * @return 实际发生变更的用户 ID 列表
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public List<UUID> reconcileUsage(Map<UUID, Long> actualUsage) {
        if (actualUsage == null || actualUsage.isEmpty()) {
            return List.of();
        }
        List<UUID> changedUserIds = new ArrayList<>();
        for (Map.Entry<UUID, Long> entry : actualUsage.entrySet()) {
            long actual = Math.max(0L, entry.getValue() == null ? 0L : entry.getValue());
            if (authUserRepository.reconcileUsedBytes(entry.getKey(), actual) > 0) {
                changedUserIds.add(entry.getKey());
            }
        }
        return List.copyOf(changedUserIds);
    }

    private UserAccountSummary toSummary(AuthUser user) {
        return new UserAccountSummary(
                user.getId(),
                user.getUsername(),
                user.getRoles().stream().map(AuthRole::getId).collect(Collectors.toSet()),
                user.getRoles().stream().anyMatch(role -> Roles.SUPER_ADMIN.equals(role.getCode())),
                user.getQuotaBytes(),
                user.getUsedBytes(),
                user.getReservedBytes()
        );
    }
}
