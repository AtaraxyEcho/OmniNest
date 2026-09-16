package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.ExternalStorageStatus;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import com.omninest.modules.user.port.ExternalStorageAccountSummary;
import com.omninest.modules.user.port.ExternalStorageAdministration;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 基于文件域账户仓库的外部存储管理实现。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileExternalStorageAdministration implements ExternalStorageAdministration {

    private final StorageExternalAccountRepository accountRepository;
    private final ExternalStorageService externalStorageService;

    /**
     * 统计全部外部存储账户。
     *
     * @return 外部存储账户数量
     */
    @Override
    @Transactional(readOnly = true)
    public long countAccounts() {
        return accountRepository.count();
    }

    /**
     * 按最近更新时间查询全部外部存储账户。
     *
     * @return 外部存储账户摘要列表
     */
    @Override
    @Transactional(readOnly = true)
    public List<ExternalStorageAccountSummary> listAccounts() {
        return accountRepository.findAllByOrderByUpdatedAtDesc().stream()
                .map(this::toSummary)
                .toList();
    }

    /**
     * 更新外部存储账户状态。
     *
     * @param accountId 账户标识
     * @param status 目标状态
     * @return 更新后的账户摘要
     */
    @Override
    @Transactional(rollbackFor = Exception.class)
    public ExternalStorageAccountSummary updateStatus(UUID accountId, String status) {
        ExternalStorageStatus resolvedStatus = resolveStatus(status);
        StorageExternalAccount account = accountRepository.findById(accountId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储账户不存在"));
        boolean wasActive = ExternalStorageStatus.ACTIVE.getValue().equals(account.getStatus());
        boolean disable = resolvedStatus == ExternalStorageStatus.DISABLED;
        if (wasActive && disable) {
            externalStorageService.deactivateRemote(account);
        }
        account.setStatus(resolvedStatus.getValue());
        return toSummary(accountRepository.saveAndFlush(account));
    }

    private ExternalStorageStatus resolveStatus(String status) {
        try {
            String normalized = status == null ? "" : status.trim().toUpperCase(Locale.ROOT);
            return ExternalStorageStatus.fromValue(normalized);
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "外部存储状态不合法");
        }
    }

    private ExternalStorageAccountSummary toSummary(StorageExternalAccount account) {
        return new ExternalStorageAccountSummary(
                account.getId(),
                account.getProvider(),
                account.getDisplayName(),
                account.getStatus(),
                account.getCreatedAt(),
                account.getUpdatedAt()
        );
    }
}
