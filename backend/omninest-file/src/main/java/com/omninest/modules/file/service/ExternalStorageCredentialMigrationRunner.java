package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 启动时将历史明文外部凭据加密为 AES-GCM 密文。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ExternalStorageCredentialMigrationRunner implements ApplicationRunner {

    private static final int BATCH_SIZE = 50;

    private final StorageExternalAccountRepository accountRepository;
    private final ExternalStorageCredentialService credentialService;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void run(ApplicationArguments args) {
        int migrated = 0;
        List<StorageExternalAccount> accounts = accountRepository.findAll();
        for (StorageExternalAccount account : accounts) {
            String stored = account.getEncryptedCredentials();
            if (stored == null || stored.isBlank()) {
                continue;
            }
            if (!credentialService.isLegacyPlaintext(stored)) {
                continue;
            }
            try {
                account.setEncryptedCredentials(credentialService.encrypt(stored));
                accountRepository.save(account);
                migrated++;
                if (migrated % BATCH_SIZE == 0) {
                    log.info("外部存储明文凭据加密进度: {}", migrated);
                }
            } catch (RuntimeException exception) {
                log.warn("外部存储凭据加密失败，账户需重连: accountId={}", account.getId());
            }
        }
        if (migrated > 0) {
            log.info("外部存储明文凭据加密完成: count={}", migrated);
        }
    }
}
