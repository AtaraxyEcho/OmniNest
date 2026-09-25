package com.omninest.modules.integration.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.security.CredentialCipher;
import com.omninest.modules.integration.domain.IntegrationAccount;
import com.omninest.modules.integration.repository.IntegrationAccountRepository;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;

/**
 * 通用外部集成账号服务测试。
 *
 * @author OmniNest
 */
class IntegrationAccountServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    @Test
    void saveEncryptsCredentialsAndFindRestoresUserScopedAccount() {
        IntegrationAccountRepository repository = mock(IntegrationAccountRepository.class);
        AtomicReference<IntegrationAccount> stored = new AtomicReference<>();
        when(repository.findByOwnerUserIdAndIntegrationTypeAndProvider(OWNER_ID, "MUSIC", "NETEASE"))
                .thenAnswer(invocation -> Optional.ofNullable(stored.get()));
        when(repository.saveAndFlush(any(IntegrationAccount.class))).thenAnswer(invocation -> {
            IntegrationAccount account = invocation.getArgument(0);
            stored.set(account);
            return account;
        });
        CredentialCipher credentialCipher = mock(CredentialCipher.class);
        when(credentialCipher.encrypt(any(String.class))).thenReturn("encrypted-credentials");
        when(credentialCipher.currentKeyVersion()).thenReturn(1);
        when(credentialCipher.decrypt("encrypted-credentials"))
                .thenReturn("{\"cookie\":\"MUSIC_U=secret-cookie\"}");
        PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
        when(transactionManager.getTransaction(any())).thenReturn(mock(TransactionStatus.class));
        IntegrationAccountService service = new IntegrationAccountService(
                repository,
                credentialCipher,
                transactionManager
        );

        service.save(
                OWNER_ID,
                "music",
                "netease",
                "external-user",
                "Music User",
                "https://example.com/avatar.png",
                Map.of("cookie", "MUSIC_U=secret-cookie")
        );

        assertThat(stored.get().getEncryptedCredentials()).doesNotContain("secret-cookie");
        IntegrationAccountData restored = service.find(OWNER_ID, "music", "netease").orElseThrow();
        assertThat(restored.credentials()).containsEntry("cookie", "MUSIC_U=secret-cookie");
        assertThat(restored.ownerUserId()).isEqualTo(OWNER_ID);
    }

    @Test
    void saveRetriesOnceOnOptimisticLockingConflict() {
        IntegrationAccountRepository repository = mock(IntegrationAccountRepository.class);
        when(repository.findByOwnerUserIdAndIntegrationTypeAndProvider(OWNER_ID, "MUSIC", "NETEASE"))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.empty());
        when(repository.saveAndFlush(any(IntegrationAccount.class)))
                .thenThrow(new org.springframework.orm.ObjectOptimisticLockingFailureException(
                        IntegrationAccount.class, "1"))
                .thenAnswer(invocation -> invocation.getArgument(0));
        CredentialCipher credentialCipher = mock(CredentialCipher.class);
        when(credentialCipher.encrypt(any(String.class))).thenReturn("encrypted-credentials");
        when(credentialCipher.currentKeyVersion()).thenReturn(1);
        when(credentialCipher.decrypt("encrypted-credentials")).thenReturn("{\"cookie\":\"cookie\"}");
        PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
        when(transactionManager.getTransaction(any())).thenReturn(mock(TransactionStatus.class));
        IntegrationAccountService service = new IntegrationAccountService(
                repository,
                credentialCipher,
                transactionManager
        );

        IntegrationAccountData saved = service.save(
                OWNER_ID,
                "music",
                "netease",
                "external-user",
                "Music User",
                null,
                Map.of("cookie", "cookie")
        );

        assertThat(saved.ownerUserId()).isEqualTo(OWNER_ID);
    }
}
