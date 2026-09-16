package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 文件域外部存储管理实现测试。
 *
 * @author OmniNest
 */
class FileExternalStorageAdministrationTest {

    private static final UUID OWNER_USER_ID =
            UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ACCOUNT_ID =
            UUID.fromString("20000000-0000-0000-0000-000000000002");

    private final StorageExternalAccountRepository accountRepository =
            mock(StorageExternalAccountRepository.class);
    private final ExternalStorageService externalStorageService = mock(ExternalStorageService.class);
    private final FileExternalStorageAdministration administration =
            new FileExternalStorageAdministration(accountRepository, externalStorageService);

    @Test
    void listsAccountsAsStableSummaries() {
        StorageExternalAccount account = account("ACTIVE");
        when(accountRepository.findAllByOrderByUpdatedAtDesc()).thenReturn(List.of(account));

        var summaries = administration.listAccounts();

        assertThat(summaries).hasSize(1);
        assertThat(summaries.getFirst().id()).isEqualTo(ACCOUNT_ID);
        assertThat(summaries.getFirst().displayName()).isEqualTo("归档存储");
    }

    @Test
    void updatesStatusUsingFileDomainRule() {
        StorageExternalAccount account = account("ACTIVE");
        when(accountRepository.findById(ACCOUNT_ID)).thenReturn(Optional.of(account));
        when(accountRepository.saveAndFlush(account)).thenReturn(account);

        var summary = administration.updateStatus(ACCOUNT_ID, "disabled");

        assertThat(summary.status()).isEqualTo("DISABLED");
    }

    @Test
    void rejectsUnsupportedStatus() {
        assertThatThrownBy(() -> administration.updateStatus(ACCOUNT_ID, "UNKNOWN"))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    @Test
    void rejectsMissingAccount() {
        when(accountRepository.findById(ACCOUNT_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> administration.updateStatus(ACCOUNT_ID, "ACTIVE"))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    private StorageExternalAccount account(String status) {
        StorageExternalAccount account = new StorageExternalAccount();
        account.setId(ACCOUNT_ID);
        account.setOwnerUserId(OWNER_USER_ID);
        account.setProvider("S3");
        account.setDisplayName("归档存储");
        account.setEncryptedCredentials("encrypted");
        account.setStatus(status);
        account.setCreatedAt(Instant.parse("2026-05-20T09:00:00Z"));
        account.setUpdatedAt(Instant.parse("2026-05-20T10:00:00Z"));
        return account;
    }
}
