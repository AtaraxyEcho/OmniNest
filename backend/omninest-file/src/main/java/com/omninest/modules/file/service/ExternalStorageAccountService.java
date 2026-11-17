package com.omninest.modules.file.service;

import com.omninest.common.json.JsonSupport;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.ExternalStorageStatus;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.dto.CreateExternalStorageRequest;
import com.omninest.modules.file.dto.ExternalStorageAccountDto;
import com.omninest.modules.file.dto.UpdateExternalStorageRequest;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import com.omninest.modules.file.repository.StorageRemoteMetadataCacheRepository;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import tools.jackson.core.type.TypeReference;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 外部存储账户管理服务。
 * 负责外部存储账户的创建、更新、停用与删除。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ExternalStorageAccountService {
    private final StorageExternalAccountRepository externalAccountRepository;
    private final StorageRemoteMetadataCacheRepository remoteMetadataCacheRepository;
    private final ExternalStorageService externalStorageService;
    private final ExternalStorageCredentialService externalStorageCredentialService;
    private final ExternalStorageOAuthService externalStorageOAuthService;
    private final ExternalStorageEndpointGuard endpointGuard;
    private final PlatformTransactionManager transactionManager;

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
     * OAuth 类连接器在实例级应用未配置时直接拒绝，避免保存出无法授权的僵尸连接。
     *
     * @param ownerUserId 用户 ID
     * @param request     创建请求
     * @return 创建后的外部存储安全展示信息
     */
    @Transactional(rollbackFor = Exception.class)
    public ExternalStorageAccountDto createExternalAccount(UUID ownerUserId, CreateExternalStorageRequest request) {
        String provider = ExternalStorageProviders.requireAllowed(request.provider());
        if (isOAuthProvider(provider) && externalStorageOAuthService.findAppCredentials(provider).isEmpty()) {
            throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID,
                    "该连接器尚未配置实例级 OAuth 应用，请联系管理员在管理后台的外部存储页面完成配置后再创建");
        }
        StorageExternalAccount account = new StorageExternalAccount();
        account.setOwnerUserId(ownerUserId);
        account.setProvider(provider);
        account.setDisplayName(request.displayName().trim());
        String sanitizedCredentials = ExternalStorageCredentialCodec.sanitize(provider, request.encryptedCredentials());
        endpointGuard.validate(provider, parseCredentials(sanitizedCredentials));
        account.setEncryptedCredentials(externalStorageCredentialService.encrypt(sanitizedCredentials));
        return toExternalAccountDto(externalAccountRepository.save(account));
    }

    private boolean isOAuthProvider(String provider) {
        return ExternalStorageProviders.isOAuth(provider);
    }

    private Map<String, Object> parseCredentials(String credentialsJson) {
        return JsonSupport.fromJson(credentialsJson, new TypeReference<Map<String, Object>>() {});
    }

    /**
     * 更新外部存储：修改显示名称和凭据，凭据变更时重建 rclone remote。
     *
     * @param ownerUserId 所有者用户 ID
     * @param accountId   外部存储账户 ID
     * @param request     更新请求
     * @return 更新后的外部存储安全展示信息
     */
    public ExternalStorageAccountDto updateExternalAccount(UUID ownerUserId, UUID accountId,
                                                           UpdateExternalStorageRequest request) {
        UpdateOutcome outcome = new TransactionTemplate(transactionManager).execute(status -> {
            StorageExternalAccount account = externalAccountRepository
                    .findByIdAndOwnerUserId(accountId, ownerUserId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储不存在"));

            String existingJson = externalStorageCredentialService.decryptToJson(account.getEncryptedCredentials());
            String mergedJson = ExternalStorageCredentialCodec.mergeForUpdate(
                    account.getProvider(),
                    existingJson,
                    request.encryptedCredentials()
            );
            endpointGuard.validate(account.getProvider(), parseCredentials(mergedJson));
            boolean credentialsChanged = !mergedJson.equals(existingJson);
            account.setDisplayName(request.displayName().trim());
            if (credentialsChanged) {
                account.setEncryptedCredentials(externalStorageCredentialService.encrypt(mergedJson));
            } else if (externalStorageCredentialService.isLegacyPlaintext(account.getEncryptedCredentials())) {
                account.setEncryptedCredentials(externalStorageCredentialService.encrypt(mergedJson));
            }
            boolean refreshRemote = credentialsChanged
                    || (request.encryptedCredentials() != null
                    && !request.encryptedCredentials().isBlank());
            return new UpdateOutcome(externalAccountRepository.save(account), refreshRemote);
        });
        if (outcome == null) {
            throw new BusinessException(ErrorCode.CONFLICT, "外部存储更新失败");
        }
        if (outcome.credentialsChanged()) {
            // rclone HTTP 调用在数据库事务提交后执行，避免长时间占用连接池。
            externalStorageService.deactivateRemote(outcome.account());
            if (ExternalStorageStatus.ACTIVE.getValue().equals(outcome.account().getStatus())) {
                externalStorageService.activateRemote(outcome.account());
            }
        }
        return toExternalAccountDto(outcome.account());
    }

    private record UpdateOutcome(StorageExternalAccount account, boolean credentialsChanged) {
    }

    /**
     * 停用外部存储挂载。
     *
     * @param ownerUserId 所有者用户 ID
     * @param accountId   外部存储账户 ID
     */
    public void disableExternalAccount(UUID ownerUserId, UUID accountId) {
        StorageExternalAccount account = new TransactionTemplate(transactionManager).execute(status -> {
            StorageExternalAccount current = externalAccountRepository
                    .findByIdAndOwnerUserId(accountId, ownerUserId)
                    .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储不存在"));
            current.setStatus(ExternalStorageStatus.DISABLED.getValue());
            return externalAccountRepository.save(current);
        });
        if (account != null) {
            externalStorageService.deactivateRemote(account);
        }
    }

    /**
     * 删除外部存储挂载：清理 rclone remote → 删除数据库记录与远程目录缓存。
     *
     * @param ownerUserId 所有者用户 ID
     * @param accountId   外部存储账户 ID
     */
    public void deleteExternalAccount(UUID ownerUserId, UUID accountId) {
        StorageExternalAccount account = new TransactionTemplate(transactionManager).execute(status ->
                externalAccountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                        .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储不存在")));
        if (account == null) {
            return;
        }
        // 远程注销在事务外执行；失败时保留数据库记录，管理员可重试。
        externalStorageService.deactivateRemote(account);
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            remoteMetadataCacheRepository.deleteByExternalAccountId(accountId);
            externalAccountRepository.deleteById(accountId);
        });
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
