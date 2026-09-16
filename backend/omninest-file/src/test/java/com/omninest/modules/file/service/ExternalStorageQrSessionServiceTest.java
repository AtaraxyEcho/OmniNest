package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 扫码会话骨架测试。
 */
class ExternalStorageQrSessionServiceTest {

    private static final UUID OWNER = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ACCOUNT = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final StorageExternalAccountRepository accountRepository =
            mock(StorageExternalAccountRepository.class);
    private ExternalStorageQrSessionService service;

    @BeforeEach
    void setUp() {
        service = new ExternalStorageQrSessionService(accountRepository);
    }

    @Test
    void start_rejectsNonQrProvider() {
        StorageExternalAccount account = new StorageExternalAccount();
        account.setProvider("WEBDAV");
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT, OWNER))
                .thenReturn(Optional.of(account));

        assertThatThrownBy(() -> service.start(OWNER, ACCOUNT))
                .isInstanceOf(BusinessException.class)
                .extracting(e -> ((BusinessException) e).errorCode())
                .isEqualTo(ErrorCode.PARAM_ERROR);
    }

    @Test
    void start_createsPendingSessionForQuark() {
        StorageExternalAccount account = new StorageExternalAccount();
        account.setProvider("QUARK");
        when(accountRepository.findByIdAndOwnerUserId(ACCOUNT, OWNER))
                .thenReturn(Optional.of(account));

        var response = service.start(OWNER, ACCOUNT);

        assertThat(response.status()).isEqualTo("PENDING");
        assertThat(response.sessionId()).isNotBlank();
    }
}
