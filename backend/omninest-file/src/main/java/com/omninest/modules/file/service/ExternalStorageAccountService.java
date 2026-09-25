package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.ExternalStorageStatus;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.dto.CreateExternalStorageRequest;
import com.omninest.modules.file.dto.ExternalStorageAccountDto;
import com.omninest.modules.file.dto.UpdateExternalStorageRequest;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 外部存储账户管理服务。
 * 负责外部存储账户的创建、更新、停用与删除。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class ExternalStorageAccountService {
    private final StorageExternalAccountRepository externalAccountRepository;
    private final ExternalStorageService externalStorageService;
    private final ExternalStorageCredentialService externalStorageCredentialService;

    /**
     * 查询当前用户的外部存储账户列表。
     *
     * @param ownerUserId 用户 ID
     * @return 外部存储账户安全展示列表
     */
    @Transactional(readOnly = true)
    public List<ExternalStorageAccountDto> listExternalAccounts(UUID ownerUserId) {
        return externalAccountRepository.findByOwnerUserIdOrderByCreatedAtDesc(ownerUserId)
                .stream()
                .map(this::toExternalAccountDto)
                .toList();
    }

    /**
     * 创建外部存储账户。
     *
     * @param ownerUserId 用户 ID
     * @param request     创建请求
     * @return 创建后的外部存储安全展示信息
     */
    @Transactional(rollbackFor = Exception.class)
    public ExternalStorageAccountDto createExternalAccount(UUID ownerUserId, CreateExternalStorageRequest request) {
        StorageExternalAccount account = new StorageExternalAccount();
        account.setOwnerUserId(ownerUserId);
        account.setProvider(ExternalStorageProviders.requireAllowed(request.provider()));
        account.setDisplayName(request.displayName().trim());
        account.setEncryptedCredentials(externalStorageCredentialService.encrypt(request.encryptedCredentials()));
        return toExternalAccountDto(externalAccountRepository.save(account));
    }

    /**
     * 更新外部存储：修改显示名称和凭据，凭据变更时重建 rclone remote。
     *
     * @param ownerUserId 所有者用户 ID
     * @param accountId   外部存储账户 ID
     * @param request     更新请求
     * @return 更新后的外部存储安全展示信息
     */
    @Transactional(rollbackFor = Exception.class)
    public ExternalStorageAccountDto updateExternalAccount(UUID ownerUserId, UUID accountId,
                                                           UpdateExternalStorageRequest request) {
        StorageExternalAccount account = externalAccountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储不存在"));

        String existingJson = externalStorageCredentialService.decryptToJson(account.getEncryptedCredentials());
        String mergedJson = ExternalStorageCredentialCodec.mergeForUpdate(
                existingJson,
                request.encryptedCredentials()
        );
        boolean credentialsChanged = !mergedJson.equals(existingJson);
        account.setDisplayName(request.displayName().trim());
        if (credentialsChanged) {
            account.setEncryptedCredentials(externalStorageCredentialService.encrypt(mergedJson));
        } else if (externalStorageCredentialService.isLegacyPlaintext(account.getEncryptedCredentials())) {
            account.setEncryptedCredentials(externalStorageCredentialService.encrypt(mergedJson));
        }

        if (credentialsChanged) {
            externalStorageService.deactivateRemote(account);
            if (ExternalStorageStatus.ACTIVE.getValue().equals(account.getStatus())) {
                externalStorageService.activateRemote(account);
            }
        }

        return toExternalAccountDto(externalAccountRepository.save(account));
    }

    /**
     * 停用外部存储挂载。
     *
     * @param ownerUserId 所有者用户 ID
     * @param accountId   外部存储账户 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void disableExternalAccount(UUID ownerUserId, UUID accountId) {
        StorageExternalAccount account = externalAccountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储不存在"));
        externalStorageService.deactivateRemote(account);
        account.setStatus(ExternalStorageStatus.DISABLED.getValue());
        externalAccountRepository.save(account);
    }

    /**
     * 删除外部存储挂载：清理 rclone remote → 删除数据库记录。
     *
     * @param ownerUserId 所有者用户 ID
     * @param accountId   外部存储账户 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteExternalAccount(UUID ownerUserId, UUID accountId) {
        StorageExternalAccount account = externalAccountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储不存在"));
        externalStorageService.deactivateRemote(account);
        externalAccountRepository.delete(account);
    }

    private ExternalStorageAccountDto toExternalAccountDto(StorageExternalAccount account) {
        String credentialsJson = externalStorageCredentialService.decryptToJson(account.getEncryptedCredentials());
        return new ExternalStorageAccountDto(
                account.getId(),
                account.getProvider(),
                account.getDisplayName(),
                ExternalStorageCredentialCodec.extractEditableMetadata(
                        account.getProvider(),
                        credentialsJson
                ),
                account.getEncryptedCredentials() != null && !account.getEncryptedCredentials().isBlank(),
                account.getStatus(),
                account.getLastErrorCode(),
                account.getLastCheckedAt(),
                account.getCreatedAt(),
                account.getUpdatedAt()
        );
    }
}
